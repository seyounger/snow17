#!/usr/bin/env bash
# Test for the issue "`get_end_time` reports the end time one timestep early": does Snow17's
# get_end_time let a caller run every timestep from start_datehr to end_datehr?
#
# 1. Builds end_time_test.f90 against the Snow17 sources and runs it (no ngen needed).
# 2. Runs the standalone snow17 executable (from SNOW17_BUILD) and checks it writes exactly 4 rows.
# 3. If NGEN_EXE is set, runs the same 4 timesteps in ngen with allow_exceed_end_time = false
#    and end_datehr equal to the realization end_time. That run should finish all 4 timesteps.
#
# Part 1 compiles the sources in this repo; parts 2 and 3 use the binaries in SNOW17_BUILD, so
# build them from the same source.
#
# Usage: ./run_test.sh
#   FC=<compiler>            Fortran compiler for the BMI test (default gfortran)
#   NGEN_EXE=<ngen binary>   ngen built with NGEN_WITH_BMI_FORTRAN=ON (optional)
#   NGEN_DATA=<ngen/data>    ngen data dir with catchment_data.geojson and nexus_data.geojson
#   NGEN_VENV=<venv dir>     Python venv to activate for an ngen built with Python (e.g. ngen/.venv)
#   SNOW17_BUILD=<dir>       Snow17 cmake build dir with snow17 and libsnow17bmi.so (default <repo>/cmake_build)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
FC=${FC:-gfortran}
FFLAGS="-cpp -ffree-line-length-none -fcheck=bounds"
SB=$(cd "${SNOW17_BUILD:-$REPO/cmake_build}" 2>/dev/null && pwd) || SB=${SNOW17_BUILD:-$REPO/cmake_build}
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1

# ---- build the BMI test (share modules in dependency order)
for f in nrtype constants namelistModule parametersType forcingType dateTimeUtilsModule \
         runInfoType modelVarType ioModule runSnow17; do
  $FC -c $FFLAGS "$REPO/src/share/$f.f90" || exit 1
done
$FC -c "$REPO"/src/snow19/*.f || exit 1
$FC -c $FFLAGS "$REPO/src/bmi/bmi.f90" "$REPO/src/bmi/bmi_snow17.f90" || exit 1
$FC -c $FFLAGS "$T/end_time_test.f90" || exit 1
$FC -o end_time_test ./*.o || exit 1

# ---- inputs: 6 hourly forcing rows; the namelist runs 4 of them (2016-03-01 00..03)
cat > forcing.HRU1.csv <<'END_FORCING'
year,mo,dy,hr,prec_mm_s-1,tavg_degc
2016,03,01,00,1.0e-03,-5.0
2016,03,01,01,1.0e-03,-4.0
2016,03,01,02,0.0,-3.0
2016,03,01,03,0.0,-2.0
2016,03,01,04,0.0,-1.0
2016,03,01,05,0.0,0.0
END_FORCING

cat > params.txt <<'END_PARAMS'
hru_id HRU1
hru_area 100.0
latitude 47.78
elev 1612.50
scf 1.15
mfmax 1.35
mfmin 0.35
uadj 0.125
si 1515.0
pxtemp 1.0
nmf 0.15
tipm 0.125
mbase 0.0
plwhc 0.03
daygm 0.0
adc1 0.05
adc2 0.09
adc3 0.16
adc4 0.31
adc5 0.54
adc6 0.74
adc7 0.84
adc8 0.89
adc9 0.93
adc10 0.97
adc11 1.0
END_PARAMS

cat > namelist.input <<END_NAMELIST
&SNOW17_CONTROL
main_id             = "basin"
n_hrus              = 1
forcing_root        = "$B/forcing."
output_root         = "$B/out."
snow17_param_file   = "$B/params.txt"
output_hrus         = 0
start_datehr        = "2016030100"
end_datehr          = "2016030103"
model_timestep      = 3600
warm_start_run      = 0
write_states        = 0
snow_state_in_root  = "$B/st."
snow_state_out_root = "$B/st."
/
END_NAMELIST

# ---- 1. BMI test
echo "== BMI test (no ngen)"
./end_time_test namelist.input 2>&1 | grep -v -E '^ +(Reading|Initializing|--)|^(#|Error termination|ERROR STOP)|^$'
bmi_rc=${PIPESTATUS[0]}

# ---- 2. standalone driver
echo; echo "== standalone snow17 executable"
if [ -x "$SB/snow17" ]; then
  "$SB/snow17" namelist.input > standalone.log 2>&1
  rows=$(awk 'END {print (NR > 1 ? NR - 1 : 0)}' out.basin.txt 2>/dev/null || echo 0)   # 0 if missing or empty
  if [ "$rows" -eq 4 ]; then echo "output rows 4 of 4  ok"; drv_rc=0
  else echo "output rows $rows of 4  FAIL"; drv_rc=1; fi
else
  echo "Missing $SB/snow17; build Snow17 with cmake first."; drv_rc=1
fi
bmi_rc=$(( bmi_rc || drv_rc ))

verdict() { echo; [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; exit "$1"; }

if [ -z "${NGEN_EXE:-}" ]; then
  echo; echo "NGEN_EXE not set; skipping the ngen run."
  verdict $bmi_rc
fi

# ---- 3. ngen run
echo; echo "== ngen run: allow_exceed_end_time = false, end_datehr = end_time"
NGEN_DATA=${NGEN_DATA:?set NGEN_DATA to ngen/data}
LIB=$SB/libsnow17bmi.so
[ -f "$LIB" ] || { echo "Missing $LIB; build Snow17 with the BMI library first."; exit 1; }
if [ -n "${NGEN_VENV:-}" ]; then source "$NGEN_VENV/bin/activate"; fi

# same forcing in ngen's CsvPerFeature format
{ echo "time,precip [mm/s],tair [degC]"
  tail -n +2 forcing.HRU1.csv | while IFS=, read -r y mo d h p t; do echo "$y-$mo-$d $h:00:00,$p,$t"; done
} > cat-27.csv

cat > realization.json <<END_REALIZATION
{ "global": { "formulations": [ { "name": "bmi_fortran", "params": {
      "model_type_name": "snow17", "library_file": "$LIB",
      "init_config": "$B/namelist.input", "allow_exceed_end_time": false,
      "main_output_variable": "sneqv", "output_variables": ["sneqv"],
      "uses_forcing_file": false } } ],
    "forcing": { "file_pattern": "{{id}}.csv", "path": "$B/", "provider": "CsvPerFeature" } },
  "time": { "start_time": "2016-03-01 00:00:00", "end_time": "2016-03-01 03:00:00", "output_interval": 3600 },
  "output_root": "$B/ngen_out/" }
END_REALIZATION
mkdir -p ngen_out

"$NGEN_EXE" "$NGEN_DATA/catchment_data.geojson" cat-27 "$NGEN_DATA/nexus_data.geojson" nex-26 \
  realization.json > ngen.log 2>&1
ngen_rc=$?
grep -E "Finished [0-9]+ timesteps|exceeds model end time" ngen.log
if [ $ngen_rc -eq 0 ] && grep -q "Finished 4 timesteps" ngen.log; then
  echo "ngen: ok"; ngen_fail=0
else
  echo "ngen: FAIL (exit $ngen_rc, log: $B/ngen.log)"; ngen_fail=1
fi

verdict $(( bmi_rc || ngen_fail ))
