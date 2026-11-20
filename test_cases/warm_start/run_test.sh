#!/usr/bin/env bash
# Test: does a warm start resume from the right state row?
#
# read_snow17_statefiles (src/share/ioModule.f90) looks for the state row dated one timestep
# before start_datehr. It computes that time in single precision (`real :: prev_datetime`),
# and unix times near 1.46e9 s are only stored to the nearest 128 s. When the rounded time falls
# a few seconds before the hour, the lookup picks the row one timestep too early, so the run
# resumes from states one timestep old, without any error.
#
# Runs a continuous 24-hour standalone run (1 mm/h of snowfall at -5 degC, writing states),
# then a 2-step warm start (start hour and the next) from those states at every start hour
# 01..22, and checks that each warm start used the state row from the hour before and that its
# SWE matches the continuous run at the same hours.
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
  for h in $(seq -w 0 23); do echo "2016,03,01,$h,2.7777778e-04,-5.0"; done
} > forcing.HRU1.csv

namelist() {  # dir start end warm write
  mkdir -p "$1"
  cat > "$1/namelist.input" <<END_NAMELIST
&SNOW17_CONTROL
main_id = "basin"
n_hrus = 1
forcing_root = "$B/forcing."
output_root = "$1/out."
snow17_param_file = "$B/params.txt"
output_hrus = 0
start_datehr = "$2"
end_datehr = "$3"
model_timestep = 3600
warm_start_run = $4
write_states = $5
snow_state_in_root = "$B/cont/st."
snow_state_out_root = "$B/cont/st."
/
END_NAMELIST
  (cd "$1" && "$SB/snow17" namelist.input > run.log 2>&1)
}

namelist "$B/cont" 2016030100 2016030123 0 1
[ -s "$B/cont/st.HRU1.txt" ] || { echo "FAIL: continuous run wrote no states (see $B/cont/run.log)"; exit 1; }
swe_at() { awk -v h="$2" 'NR>1 && $4==h {print $8}' "$1/out.basin.txt" 2>/dev/null; }

bad=""
for h in $(seq -w 1 22); do
  e=$(printf "%02d" $((10#$h + 1)))   # 10# so 08/09 aren't read as octal
  p=$(printf "%02d" $((10#$h - 1)))
  namelist "$B/w$h" "20160301$h" "20160301$e" 1 0
  got=$(swe_at "$B/w$h" "$h"); want=$(swe_at "$B/cont" "$h")
  used=$(grep -o "state datehr: [0-9]*" "$B/w$h/run.log" | awk '{print substr($3,9,2)}')
  if [ "$got" != "$want" ] || [ "$used" != "$p" ]; then bad="$bad $h"; mark="FAIL"; else mark="ok"; fi
  printf "start %s:00  state row used %s:00  SWE %s (continuous %s)  %s\n" "$h" "${used:-??}" "${got:-none}" "$want" "$mark"
done

echo
if [ -z "$bad" ]; then echo "PASS"; exit 0
else echo "FAIL: warm starts at hours$bad resumed from the wrong state row"; exit 1; fi
