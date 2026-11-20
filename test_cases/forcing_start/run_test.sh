#!/usr/bin/env bash
# Test for the issue "Standalone run hangs when a forcing file has no row for start_datehr".
#
# init_forcing_files (src/share/ioModule.f90) searches the forcing file for start_datehr with
# `do while(ios .ge. 0)`, but the read stores its status in ierr. At end of file the loop never
# exits, so the run hangs instead of stopping with the existing "found the starting date in
# only ..." error.
#
# Forcing has rows for 2016-03-01 00..05. Runs the standalone executable (20 s timeout each):
#
#   control. start_datehr 2016030100 (first row): should run normally.
#   A. start_datehr 2016022923 (before the first row): should stop with the "found the starting
#      date" error.
#   B. start_datehr 2016030112 (after the last row): same.
#
# Observed (2026-11-20): A and B hang until the timeout.
#
# A and B pass when the run ends by itself and prints the error. The exit status is reported but
# not checked: that error uses a plain stop, which exits 0 (separate issue).
#
# Usage: ./run_test.sh       (SNOW17_BUILD=<snow17 cmake build dir>, default <repo>/cmake_build)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
SB=$(cd "${SNOW17_BUILD:-$REPO/cmake_build}" 2>/dev/null && pwd) || SB=${SNOW17_BUILD:-$REPO/cmake_build}
[ -x "$SB/snow17" ] || { echo "Missing $SB/snow17; build Snow17 with cmake first."; exit 1; }
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1

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

{ echo "year,mo,dy,hr,prec_mm_s-1,tavg_degc"
  for h in 00 01 02 03 04 05; do echo "2016,03,01,$h,2.7777778e-04,-5.0"; done
} > forcing.HRU1.csv

run() {  # name start end
  mkdir -p "$1"
  cat > "$1/namelist.input" <<END_NAMELIST
&SNOW17_CONTROL
main_id = "basin"
n_hrus = 1
forcing_root = "$B/forcing."
output_root = "$B/$1/out."
snow17_param_file = "$B/params.txt"
output_hrus = 0
start_datehr = "$2"
end_datehr = "$3"
model_timestep = 3600
warm_start_run = 0
write_states = 0
snow_state_in_root = "$B/$1/st."
snow_state_out_root = "$B/$1/st."
/
END_NAMELIST
  (cd "$1" && timeout 20 "$SB/snow17" namelist.input > run.log 2>&1)
  echo $?
}
rows() { awk 'END {print (NR > 1 ? NR - 1 : 0)}' "$1/out.basin.txt" 2>/dev/null || echo 0; }

fail=0
rc=$(run control 2016030100 2016030105)
if [ "$rc" -eq 0 ] && [ "$(rows control)" -eq 6 ]; then echo "control (start at first row): 6 of 6 rows   ok"
else echo "control (start at first row): exit $rc, $(rows control) of 6 rows   FAIL"; fail=1; fi

for c in "A 2016022923 2016030100 before the first row" "B 2016030112 2016030113 after the last row"; do
  set -- $c; name=$1; start=$2; end=$3; shift 3; where="$*"
  rc=$(run "$name" "$start" "$end")
  if [ "$rc" -eq 124 ]; then
    echo "$name. start_datehr $start ($where): hung, killed after 20 s   FAIL"; fail=1
  elif grep -q "found the starting date" "$name/run.log"; then
    echo "$name. start_datehr $start ($where): stopped with the 'found the starting date' error (exit $rc)   ok"
  else
    echo "$name. start_datehr $start ($where): exit $rc without the expected error   FAIL"
    grep -m2 -iE "error|cannot" "$name/run.log" | sed 's/^ */     /'; fail=1
  fi
done

echo; [ $fail -eq 0 ] && echo "PASS" || echo "FAIL"
exit $fail
