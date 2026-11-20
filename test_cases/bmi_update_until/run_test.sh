#!/usr/bin/env bash
# Test for the issue "update_until ignores the requested time".
#
# snow17_update_until (src/bmi/bmi_snow17.f90) loops until end_datetime instead of the requested
# time, so one call runs every remaining timestep. Builds update_until_test.f90 against the
# Snow17 sources in this repo and runs it on 6 hourly timesteps of snowfall (no ngen needed).
# See update_until_test.f90 for the checks.
#
# If NGEN_EXE is set, also runs ngen. ngen calls UpdateUntil(current + step) instead of Update
# whenever its step length differs from model_timestep (ngen
# src/realizations/catchment/Bmi_Module_Formulation.cpp, Bmi_Module_Formulation::update). The
# step length is the surface layer's time_step, 3600 s by default (ngen src/core/Layer.cpp), not
# the realization's output_interval (which is set to match it here). Both runs have 1 mm/h of
# snowfall at -5 degC from 2016-03-01 00:00. ngen's end_time is inclusive, and the namelist
# period runs past it, so neither run depends on get_end_time being one timestep early
# (separate issue):
#
#   A. model_timestep 3600, layer time_step 7200, end_time 04:00: 3 calls of
#      UpdateUntil(current + 7200). sneqv (m) should be 0.00230, 0.00460, 0.00690.
#   B. model_timestep 7200, default layer (3600), end_time 05:00: each
#      UpdateUntil(current + 3600) asks for half a model timestep, so it should fail and ngen
#      should stop with an error. Advancing a full timestep instead runs the model at twice
#      ngen's clock.
#
# Observed (2026-11-20):
#   - BMI test: update_until(start + 2*dt) runs until the clock reaches end_datehr, 3 timesteps
#     past the target (sneqv 5.750 mm instead of 2.300). The next update_until(start + 4*dt)
#     returns BMI_FAILURE, because the clock is already past it.
#   - ngen A and B: the first UpdateUntil runs to the end of the namelist period, past ngen's
#     end_time. ngen finishes with exit 0 and reports that final sneqv at every timestep
#     (A: 0.00805 m, B: 0.00920 m).
#   - With the suggested fix in the issue, all BMI checks pass, A gives 0.00230, 0.00460,
#     0.00690, and B stops with "Model execution update to specified time failed".
#
# Usage: ./run_test.sh
#   FC=<compiler>            Fortran compiler for the BMI test (default gfortran)
#   NGEN_EXE=<ngen binary>   ngen built with NGEN_WITH_BMI_FORTRAN=ON (optional)
#   NGEN_DATA=<ngen/data>    ngen data dir with catchment_data.geojson and nexus_data.geojson
#   NGEN_VENV=<venv dir>     Python venv to activate for an ngen built with Python (e.g. ngen/.venv)
#   SNOW17_BUILD=<dir>       Snow17 cmake build dir with libsnow17bmi.so (default <repo>/cmake_build)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
FC=${FC:-gfortran}
FFLAGS="-cpp -ffree-line-length-none -fcheck=bounds"
SB=$(cd "${SNOW17_BUILD:-$REPO/cmake_build}" 2>/dev/null && pwd) || SB=${SNOW17_BUILD:-$REPO/cmake_build}
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1

# ---- build the test (share modules in dependency order)
for f in nrtype constants namelistModule parametersType forcingType dateTimeUtilsModule \
         runInfoType modelVarType ioModule runSnow17; do
  $FC -c $FFLAGS "$REPO/src/share/$f.f90" || exit 1
done
$FC -c "$REPO"/src/snow19/*.f || exit 1
$FC -c $FFLAGS "$REPO/src/bmi/bmi.f90" "$REPO/src/bmi/bmi_snow17.f90" || exit 1
$FC -c $FFLAGS "$T/update_until_test.f90" || exit 1
$FC -o update_until_test ./*.o || exit 1

# ---- inputs: 6 hourly steps of snowfall, 1 mm/h at -5 degC
{ echo "year,mo,dy,hr,prec_mm_s-1,tavg_degc"
  for h in 00 01 02 03 04 05; do echo "2016,03,01,$h,2.7777778e-04,-5.0"; done
} > forcing.HRU1.csv

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
end_datehr          = "2016030105"
model_timestep      = 3600
warm_start_run      = 0
write_states        = 0
snow_state_in_root  = "$B/st."
snow_state_out_root = "$B/st."
/
END_NAMELIST

# ---- 1. BMI test
# require the driver's PASS line too: a Fortran stop inside the model ends the driver with exit 0
echo "== BMI test (no ngen)"
timeout 30 ./update_until_test namelist.input > run.log 2>&1
rc=$?
grep -v -E '^ +(Reading|Initializing|--)|^(#|Error termination|ERROR STOP)|^$' run.log
bmi_fail=1
if [ $rc -eq 0 ] && grep -qx "PASS" run.log; then bmi_fail=0
elif ! grep -qx -E "PASS|FAIL.*" run.log; then
  if [ $rc -eq 124 ]; then echo "FAIL: the driver did not finish within 30 s"
  else echo "FAIL: the driver ended before reporting (exit $rc; see $B/run.log)"; fi
fi

verdict() { echo; [ "$1" -eq 0 ] && echo "PASS" || echo "FAIL"; exit "$1"; }

if [ -z "${NGEN_EXE:-}" ]; then
  echo; echo "NGEN_EXE not set; skipping the ngen runs."
  verdict $bmi_fail
fi

# ---- 2. ngen runs
NGEN_DATA=${NGEN_DATA:?set NGEN_DATA to ngen/data}
LIB=$SB/libsnow17bmi.so
[ -f "$LIB" ] || { echo "Missing $LIB; build Snow17 with the BMI library first."; exit 1; }
if [ -n "${NGEN_VENV:-}" ]; then source "$NGEN_VENV/bin/activate"; fi

# hourly forcing through 2016-03-01 08:00, past both namelist periods
{ echo "time,precip [mm/s],tair [degC]"
  for h in 00 01 02 03 04 05 06 07 08; do echo "2016-03-01 $h:00:00,2.7777778e-04,-5.0"; done
} > cat-27.csv

ngen_run() {  # name model_timestep end_datehr end_time output_interval layers_json
  local d="$B/ngen_$1"; mkdir -p "$d/out"
  sed -e "s|^model_timestep .*|model_timestep      = $2|" -e "s|^end_datehr .*|end_datehr          = \"$3\"|" \
      -e "s|\"$B/out.\"|\"$d/out.\"|" namelist.input > "$d/namelist.input"
  cat > "$d/realization.json" <<END_REALIZATION
{ "global": { "formulations": [ { "name": "bmi_fortran", "params": {
      "model_type_name": "snow17", "library_file": "$LIB",
      "init_config": "$d/namelist.input", "allow_exceed_end_time": true,
      "main_output_variable": "sneqv", "output_variables": ["sneqv"],
      "uses_forcing_file": false } } ],
    "forcing": { "file_pattern": "{{id}}.csv", "path": "$B/", "provider": "CsvPerFeature" } },
  $6
  "time": { "start_time": "2016-03-01 00:00:00", "end_time": "2016-03-01 $4", "output_interval": $5 },
  "output_root": "$d/out/" }
END_REALIZATION
  (cd "$d" && timeout 30 "$NGEN_EXE" "$NGEN_DATA/catchment_data.geojson" cat-27 \
     "$NGEN_DATA/nexus_data.geojson" nex-26 realization.json > ngen.log 2>&1) 2>/dev/null  # no "Aborted" line
  echo $?
}
# one value per time step: with a layers block, ngen writes each output row twice
sneqv() { [ -f "$B/ngen_$1/out/cat-27.csv" ] && awk -F, 'NR>1 && !seen[$1]++ {printf "%s ", $3}' "$B/ngen_$1/out/cat-27.csv"; }
summary() {  # name rc
  local f s; f=$(grep -oE "Finished [0-9]+ timesteps" "$B/ngen_$1/ngen.log"); s=$(sneqv $1)
  echo "exit $2${f:+. $f}${s:+. sneqv (m): $s}"
}

ngen_fail=0
echo; echo "== ngen A: model_timestep 3600, layer time_step 7200 (ngen calls UpdateUntil(current + 7200))"
rc=$(ngen_run A 3600 2016030107 04:00:00 7200 '"layers": [ { "name": "surface layer", "id": 0, "time_step": 7200 } ],')
got=$(sneqv A)
summary A $rc
if [ "$rc" -eq 0 ] && echo "$got" | awk '{ want[1]=0.0023; want[2]=0.0046; want[3]=0.0069
     if (NF != 3) exit 1; for (i = 1; i <= 3; i++) if ($i < want[i] - 1e-5 || $i > want[i] + 1e-5) exit 1 }'; then
  echo "ngen A: ok"
else
  [ "$rc" -eq 124 ] && echo "ngen hung, killed after 30 s"
  echo "ngen A: want sneqv 0.0023 0.0046 0.0069 and exit 0   FAIL (log: $B/ngen_A/ngen.log)"; ngen_fail=1
fi

echo; echo "== ngen B: model_timestep 7200, default layer time_step 3600 (half a timestep per call)"
rc=$(ngen_run B 7200 2016030108 05:00:00 3600 "")
summary B $rc
if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && grep -q "update to specified time failed" "$B/ngen_B/ngen.log"; then
  echo "ngen B: stopped with an UpdateUntil error   ok"
else
  if [ "$rc" -eq 124 ]; then echo "ngen hung, killed after 30 s"
  elif [ "$rc" -eq 0 ]; then echo "ran without error"
  else grep -m2 -iE "error|what\(\)" "$B/ngen_B/ngen.log" | sed 's/^/     /'; fi
  echo "ngen B: want a failed UpdateUntil   FAIL (log: $B/ngen_B/ngen.log)"; ngen_fail=1
fi

verdict $(( bmi_fail || ngen_fail ))
