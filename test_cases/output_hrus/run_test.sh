#!/usr/bin/env bash
# Test for the issue "output_hrus = 1 with n_hrus = 1 creates an HRU output file containing only
# a header".
#
# init_output_files (src/share/ioModule.f90) creates <output_root><hru_id>.txt for every HRU
# when output_hrus = 1, but write_snow17_output only writes per-HRU rows when n_hrus > 1.
#
# Runs the standalone executable for 4 hourly timesteps of snowfall with output_hrus = 1:
#
#   control. n_hrus = 2: each HRU file should have 4 rows.
#   A. n_hrus = 1: the HRU file should either not exist or have 4 rows.
#
# Observed (2026-11-20): in A, out.HRU1.txt exists with only the header.
#
# Usage: ./run_test.sh       (SNOW17_BUILD=<snow17 cmake build dir>, default <repo>/cmake_build)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
SB=$(cd "${SNOW17_BUILD:-$REPO/cmake_build}" 2>/dev/null && pwd) || SB=${SNOW17_BUILD:-$REPO/cmake_build}
[ -x "$SB/snow17" ] || { echo "Missing $SB/snow17; build Snow17 with cmake first."; exit 1; }
B="$T/build"
rm -rf "$B" && mkdir -p "$B" && cd "$B" || exit 1

params() {  # file hru_ids... (each HRU gets the same values)
  local f=$1; shift; local n=$#
  rep() { local v=$1 out=""; for _ in $(seq $n); do out="$out $v"; done; echo "$out"; }
  { echo "hru_id $*"
    for kv in hru_area=100.0 latitude=47.78 elev=1612.50 scf=1.15 mfmax=1.35 mfmin=0.35 \
              uadj=0.125 si=1515.0 pxtemp=1.0 nmf=0.15 tipm=0.125 mbase=0.0 plwhc=0.03 daygm=0.0 \
              adc1=0.05 adc2=0.09 adc3=0.16 adc4=0.31 adc5=0.54 adc6=0.74 adc7=0.84 adc8=0.89 \
              adc9=0.93 adc10=0.97 adc11=1.0; do
      echo "${kv%%=*}$(rep ${kv#*=})"
    done
  } > "$f"
}

# 4 hourly steps of snowfall, 1 mm/h at -5 degC
for id in HRU1 HRU2; do
  { echo "year,mo,dy,hr,prec_mm_s-1,tavg_degc"
    for h in 00 01 02 03; do echo "2016,03,01,$h,2.7777778e-04,-5.0"; done
  } > "forcing.$id.csv"
done

run() {  # name hru_ids...
  local name=$1; shift
  mkdir -p "$name"
  params "$name/params.txt" "$@"
  cat > "$name/namelist.input" <<END_NAMELIST
&SNOW17_CONTROL
main_id = "basin"
n_hrus = $#
forcing_root = "$B/forcing."
output_root = "$B/$name/out."
snow17_param_file = "$B/$name/params.txt"
output_hrus = 1
start_datehr = "2016030100"
end_datehr = "2016030103"
model_timestep = 3600
warm_start_run = 0
write_states = 0
snow_state_in_root = "$B/$name/st."
snow_state_out_root = "$B/$name/st."
/
END_NAMELIST
  (cd "$name" && timeout 20 "$SB/snow17" namelist.input > run.log 2>&1)
}
rows() { [ -f "$1" ] && echo $(( $(wc -l < "$1") - 1 )) || echo "missing"; }

fail=0
run control HRU1 HRU2
r1=$(rows control/out.HRU1.txt); r2=$(rows control/out.HRU2.txt)
if [ "$r1" = 4 ] && [ "$r2" = 4 ]; then echo "control. n_hrus = 2: out.HRU1.txt 4 rows, out.HRU2.txt 4 rows   ok"
else echo "control. n_hrus = 2: out.HRU1.txt $r1 rows, out.HRU2.txt $r2 rows (want 4)   FAIL"; fail=1; fi

run A HRU1
r=$(rows A/out.HRU1.txt); rb=$(rows A/out.basin.txt)
if [ "$r" = missing ] || [ "$r" = 4 ]; then echo "A. n_hrus = 1: out.HRU1.txt $r$([ "$r" = 4 ] && echo " rows"), out.basin.txt $rb rows   ok"
else echo "A. n_hrus = 1: out.HRU1.txt has $r rows (header only), out.basin.txt $rb rows   FAIL"; fail=1; fi

echo; [ $fail -eq 0 ] && echo "PASS" || echo "FAIL"
exit $fail
