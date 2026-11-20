#!/usr/bin/env bash
# Test for the state-file issues: "All model instances share one Fortran unit for state files",
# "NextGen catchments that share a state file name stop the whole run" and "Allow a warm-start
# run to also write states".
#
# Uses 6 hourly timesteps of snowfall. cat-27 gets 1 mm/h and cat-52 gets 2 mm/h, so their
# states differ and each state file can be traced to its catchment.
#
#   1. ngen, two catchments, same parameter file (same hru_id), same snow_state_out_root:
#      both catchments try to write <root>HRU1.txt. Reported only. Observed (2026-11-19): the
#      second open fails, Snow17 calls STOP, and ngen ends before the first timestep with exit
#      status 0.
#   2. ngen, two catchments, same parameter file, separate snow_state_out_root per catchment:
#      each state file should match a single-catchment run of that catchment.
#      Observed (2026-11-19): every instance writes on Fortran unit 751, so st52 gets both
#      catchments' rows and st27 only a header.
#   3. standalone, three chained runs (2 steps each), the middle one warm-starting and writing
#      states: the last run should match a continuous 6-step run.
#      Current code turns write_states off when warm_start_run = 1, so the chain breaks.
#      Passes only once the warm-start row lookup issue is also fixed (run2 and run3 start at
#      02 and 04, hours that read the wrong row).
#
# Usage: NGEN_EXE=<ngen> NGEN_DATA=<ngen/data> [NGEN_VENV=<venv>] [SNOW17_BUILD=<dir>] ./run_test.sh
#        (without NGEN_EXE, only part 3 runs)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
SB=$(cd "${SNOW17_BUILD:-$REPO/cmake_build}" 2>/dev/null && pwd) || SB=${SNOW17_BUILD:-$REPO/cmake_build}
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1
fail=0

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

HOURS="00 01 02 03 04 05"
{ echo "time,precip [mm/s],tair [degC]"; for h in $HOURS; do echo "2016-03-01 $h:00:00,2.7777778e-04,-5.0"; done; } > cat-27.csv
{ echo "time,precip [mm/s],tair [degC]"; for h in $HOURS; do echo "2016-03-01 $h:00:00,5.5555556e-04,-5.0"; done; } > cat-52.csv
# standalone forcing (same as cat-27)
{ echo "year,mo,dy,hr,prec_mm_s-1,tavg_degc"; for h in $HOURS; do echo "2016,03,01,$h,2.7777778e-04,-5.0"; done; } > forcing.HRU1.csv

namelist() {  # file start end warm write state_in state_out [main_id]
  cat > "$1" <<END_NAMELIST
&SNOW17_CONTROL
main_id = "${8:-basin}"
n_hrus = 1
forcing_root = "$B/forcing."
output_root = "$(dirname "$1")/out."
snow17_param_file = "$B/params.txt"
output_hrus = 0
start_datehr = "$2"
end_datehr = "$3"
model_timestep = 3600
warm_start_run = $4
write_states = $5
snow_state_in_root = "$6"
snow_state_out_root = "$7"
/
END_NAMELIST
}
rows() { [ -f "$1" ] && echo $(( $(wc -l < "$1") - 1 )) || echo "missing"; }
we() { [ -f "$1" ] && awk 'NR>1 {printf "%.4f ", $3}' "$1"; }   # cs1 = water equivalent (mm)

# ======================================================================================
if [ -n "${NGEN_EXE:-}" ]; then
  NGEN_DATA=${NGEN_DATA:?set NGEN_DATA to ngen/data}
  LIB=$SB/libsnow17bmi.so
  [ -f "$LIB" ] || { echo "Missing $LIB; build Snow17 with the BMI library first."; exit 1; }
  if [ -n "${NGEN_VENV:-}" ]; then source "$NGEN_VENV/bin/activate"; fi

  ngen_run() {  # dir catchments nexuses
    local d="$1"; mkdir -p "$d/out"
    cat > "$d/realization.json" <<END_REALIZATION
{ "global": { "formulations": [ { "name": "bmi_fortran", "params": {
      "model_type_name": "snow17", "library_file": "$LIB",
      "init_config": "$d/{{id}}.namelist.input", "allow_exceed_end_time": true,
      "main_output_variable": "sneqv", "output_variables": ["sneqv"],
      "uses_forcing_file": false } } ],
    "forcing": { "file_pattern": "{{id}}.csv", "path": "$B/", "provider": "CsvPerFeature" } },
  "time": { "start_time": "2016-03-01 00:00:00", "end_time": "2016-03-01 05:00:00", "output_interval": 3600 },
  "output_root": "$d/out/" }
END_REALIZATION
    (cd "$d" && "$NGEN_EXE" "$NGEN_DATA/catchment_data.geojson" "$2" "$NGEN_DATA/nexus_data.geojson" "$3" \
       realization.json > ngen.log 2>&1)
    echo $? > "$d/ngen.rc"
  }
  ngen_summary() {  # dir
    local d="$1" fin
    fin=$(grep -oE "Finished [0-9]+ timesteps" "$d/ngen.log" || echo "did not finish")
    echo "   ngen exit $(cat $d/ngen.rc), $fin"
    grep -h -E "Problem opening|STOP|what\(\)" "$d/ngen.log" | sed 's/^ */   log: /'
  }

  # references: each catchment alone
  for c in 27 52; do
    d="$B/ref$c"; mkdir -p "$d"
    namelist "$d/cat-$c.namelist.input" 2016030100 2016030105 0 1 "" "$d/st." "cat-$c"
    n=$([ $c = 27 ] && echo nex-26 || echo nex-34)
    ngen_run "$d" "cat-$c" "$n"
  done

  # 1. shared state root
  d="$B/shared"; mkdir -p "$d"
  for c in 27 52; do namelist "$d/cat-$c.namelist.input" 2016030100 2016030105 0 1 "" "$d/st." "cat-$c"; done
  ngen_run "$d" "cat-27,cat-52" "nex-26,nex-34"

  # 2. separate state roots
  d="$B/separate"; mkdir -p "$d"
  for c in 27 52; do namelist "$d/cat-$c.namelist.input" 2016030100 2016030105 0 1 "" "$d/st$c." "cat-$c"; done
  ngen_run "$d" "cat-27,cat-52" "nex-26,nex-34"

  echo "Reference (each catchment alone), water equivalent cs1 (mm):"
  echo "   cat-27: $(we $B/ref27/st.HRU1.txt)"
  echo "   cat-52: $(we $B/ref52/st.HRU1.txt)"
  echo
  echo "1. two catchments, same hru_id, same snow_state_out_root (reported only):"
  ngen_summary "$B/shared"
  echo "   st.HRU1.txt: $(rows $B/shared/st.HRU1.txt) rows"
  echo
  echo "2. two catchments, separate snow_state_out_root:"
  ngen_summary "$B/separate"
  ok2=1
  for c in 27 52; do
    [ -n "$(we $B/ref$c/st.HRU1.txt)" ] || { echo "   reference run for cat-$c wrote no states (see $B/ref$c/ngen.log)"; ok2=0; }
  done
  for c in 27 52; do
    f="$B/separate/st$c.HRU1.txt"
    echo "   st$c.HRU1.txt: $(rows $f) rows: $(we $f)"
    [ "$(we $f)" = "$(we $B/ref$c/st.HRU1.txt)" ] || ok2=0
  done
  if [ $ok2 -eq 1 ]; then echo "   each file matches its catchment's reference   ok"
  else echo "   files don't match their catchment's reference   FAIL"; fail=1; fi
  echo
else
  echo "NGEN_EXE not set; skipping parts 1 and 2."; echo
fi

# ======================================================================================
# 3. standalone warm-start chain
[ -x "$SB/snow17" ] || { echo "Missing $SB/snow17; build Snow17 with cmake first."; exit 1; }
for r in cont run1 run2 run3; do mkdir -p "$B/$r"; done
namelist "$B/cont/namelist.input" 2016030100 2016030105 0 1 "" "$B/cont/st."
namelist "$B/run1/namelist.input" 2016030100 2016030101 0 1 "" "$B/run1/st."
namelist "$B/run2/namelist.input" 2016030102 2016030103 1 1 "$B/run1/st." "$B/run2/st."
namelist "$B/run3/namelist.input" 2016030104 2016030105 1 0 "$B/run2/st." ""
for r in cont run1 run2 run3; do (cd "$B/$r" && "$SB/snow17" namelist.input > run.log 2>&1); done

echo "3. standalone chain: run1 (00-01) -> run2 (02-03, warm start + write states) -> run3 (04-05)"
echo "   continuous WE (mm):       $(we $B/cont/st.HRU1.txt)"
echo "   run2 state file:          $(rows $B/run2/st.HRU1.txt) rows"
grep -h "WARNING" "$B/run2/run.log" | sed 's/^ */   run2 log: /'
cont_swe=$(awk 'NR>1 {print $8}' "$B/cont/out.basin.txt" 2>/dev/null | tail -2 | tr '\n' ' ')
run3_swe=$(awk 'NR>1 {print $8}' "$B/run3/out.basin.txt" 2>/dev/null | tr '\n' ' ')
echo "   SWE 04-05, continuous:    $cont_swe"
echo "   SWE 04-05, run3:          ${run3_swe:-none (run3 failed: $(grep -m1 -iE 'error|cannot|not found' $B/run3/run.log | sed 's/^ *//'))}"
if [ -n "$run3_swe" ] && [ "$run3_swe" = "$cont_swe" ]; then echo "   run3 matches the continuous run   ok"
else echo "   chain broken   FAIL"; fail=1; fi

echo; [ $fail -eq 0 ] && echo "PASS" || echo "FAIL"
exit $fail
