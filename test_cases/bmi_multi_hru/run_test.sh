#!/usr/bin/env bash
# Test for the issue "Multiple HRUs (n_hrus > 1) only work standalone, and BMI doesn't check for them".
#
# BMI supports one HRU per model instance, but nothing checks n_hrus. Runs 6 hourly timesteps
# of snowfall in ngen three ways and reports the sneqv (m) and raim (mm/s) ngen receives:
#
#   A. n_hrus = 1                          control
#   B. n_hrus = 2                          should stop at initialization with a clear error
#   C. n_hrus = 2, model_params scf = 1.0  should stop at initialization with a clear error
#
# For B and C to pass, the error message must reach ngen.log. gfortran buffers its output even
# on stderr, and ngen aborts without flushing it, so write the message and flush it before
# returning BMI_FAILURE.
#
# Observed (2026-11-19): B runs without error. HRU 2 gets no forcing (tair and precip stay at
# huge(1.0)), so all its precipitation falls as rain and it never holds snow. sneqv is the
# area-weighted average of both HRUs, so it comes out at half the control value, and raim is inf.
# C stops in set_value with a bounds-check error (GNU builds use -fcheck=bounds).
#
# Usage: NGEN_EXE=<ngen> NGEN_DATA=<ngen/data> [NGEN_VENV=<venv>] [SNOW17_BUILD=<dir>] ./run_test.sh
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
NGEN_EXE=${NGEN_EXE:?set NGEN_EXE to an ngen binary built with NGEN_WITH_BMI_FORTRAN=ON}
NGEN_DATA=${NGEN_DATA:?set NGEN_DATA to ngen/data}
LIB=${SNOW17_BUILD:-$REPO/cmake_build}/libsnow17bmi.so
[ -f "$LIB" ] || { echo "Missing $LIB; build Snow17 with the BMI library first."; exit 1; }
if [ -n "${NGEN_VENV:-}" ]; then source "$NGEN_VENV/bin/activate"; fi
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1

# 2-HRU parameter file (HRU 1 is used alone in run A, since list-directed reads take the first value)
cat > params.txt <<'END_PARAMS'
hru_id HRU1 HRU2
hru_area 100.0 100.0
latitude 47.78 47.78
elev 1612.50 2153.35
scf 1.15 1.15
mfmax 1.35 1.35
mfmin 0.35 0.35
uadj 0.125 0.125
si 1515.0 1515.0
pxtemp 1.0 1.0
nmf 0.15 0.15
tipm 0.125 0.125
mbase 0.0 0.0
plwhc 0.03 0.03
daygm 0.0 0.0
adc1 0.05 0.05
adc2 0.09 0.09
adc3 0.16 0.16
adc4 0.31 0.31
adc5 0.54 0.54
adc6 0.74 0.74
adc7 0.84 0.84
adc8 0.89 0.89
adc9 0.93 0.93
adc10 0.97 0.97
adc11 1.0 1.0
END_PARAMS

# 6 hourly steps of snowfall: 1 mm/h at -5 degC
{ echo "time,precip [mm/s],tair [degC]"
  for h in 00 01 02 03 04 05; do echo "2016-03-01 $h:00:00,2.7777778e-04,-5.0"; done
} > cat-27.csv

run() {  # name n_hrus model_params_json
  local d="$B/$1"; mkdir -p "$d/out"
  cat > "$d/namelist.input" <<END_NAMELIST
&SNOW17_CONTROL
main_id = "basin"
n_hrus = $2
forcing_root = "$B/forcing."
output_root = "$d/out."
snow17_param_file = "$B/params.txt"
output_hrus = 0
start_datehr = "2016030100"
end_datehr = "2016030105"
model_timestep = 3600
warm_start_run = 0
write_states = 0
snow_state_in_root = "$d/st."
snow_state_out_root = "$d/st."
/
END_NAMELIST
  cat > "$d/realization.json" <<END_REALIZATION
{ "global": { "formulations": [ { "name": "bmi_fortran", "params": {
      "model_type_name": "snow17", "library_file": "$LIB",
      "init_config": "$d/namelist.input", "allow_exceed_end_time": true,
      "main_output_variable": "sneqv", "output_variables": ["sneqv", "raim"],
      "uses_forcing_file": false $3 } } ],
    "forcing": { "file_pattern": "{{id}}.csv", "path": "$B/", "provider": "CsvPerFeature" } },
  "time": { "start_time": "2016-03-01 00:00:00", "end_time": "2016-03-01 05:00:00", "output_interval": 3600 },
  "output_root": "$d/out/" }
END_REALIZATION
  (cd "$d" && "$NGEN_EXE" "$NGEN_DATA/catchment_data.geojson" cat-27 "$NGEN_DATA/nexus_data.geojson" nex-26 \
     realization.json > ngen.log 2>&1)
  echo $?
}
col() { [ -f "$B/$1/out/cat-27.csv" ] && awk -F, -v c=$2 'NR>1 {printf "%s ", $c}' "$B/$1/out/cat-27.csv"; }
sneqv() { col $1 3; }
raim() { col $1 4; }
has_nhrus_error() { grep -qi "n_hrus" "$B/$1/ngen.log"; }   # an error message that names n_hrus

rcA=$(run A 1 "")
rcB=$(run B 2 "")
rcC=$(run C 2 ', "model_params": { "scf": 1.0 }')

fail=0
echo "A. n_hrus = 1: exit $rcA"
echo "   sneqv (m):   $(sneqv A)"
echo "   raim (mm/s): $(raim A)"
if [ "$rcA" -ne 0 ] || [ -z "$(sneqv A)" ]; then echo "   control run failed   FAIL"; fail=1; else echo "   control   ok"; fi

for r in B C; do
  rc=$([ $r = B ] && echo $rcB || echo $rcC)
  label=$([ $r = B ] && echo "n_hrus = 2" || echo "n_hrus = 2, model_params scf")
  echo "$r. $label: exit $rc"
  [ -n "$(sneqv $r)" ] && { echo "   sneqv (m):   $(sneqv $r)"; echo "   raim (mm/s): $(raim $r)"; }
  if [ "$rc" -ne 0 ] && has_nhrus_error $r; then
    echo "   stopped with a clear error about n_hrus   ok"
  else
    [ "$rc" -eq 0 ] && echo "   ran without error   FAIL"
    [ "$rc" -ne 0 ] && { echo "   stopped, but not with a clear n_hrus error   FAIL"; \
      grep -m2 -E "Fortran runtime error|what\(\)|Error|error" "$B/$r/ngen.log" | sed 's/^/     /'; }
    fail=1
  fi
done

echo; [ $fail -eq 0 ] && echo "PASS" || echo "FAIL"
exit $fail
