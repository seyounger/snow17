#!/usr/bin/env bash
# Test for the issue "Sub-hourly or non-hourly model_timestep crashes or scales melt wrongly":
# model_timestep values that aren't a multiple of 3600 s.
#
# EXSNOW19 gets the timestep as whole hours, IDT = int(dt/3600) (src/share/runSnow17.f90:158),
# and scales mfmax, mfmin, nmf, uadj, daygm and tipm with it (src/snow19/exsnow19.f:80-86).
#
# Runs the standalone executable on the same 8-step event at different timesteps: 2 steps of
# snowfall (10 mm per step, -5 degC), then 6 steps of melt (+5 degC, no precipitation). The
# snowfall depth per step is the same for every timestep, so any difference in SWE comes from
# how the model scales melt to the timestep. All runs stay within one day, so the seasonal melt
# factor is the same.
#
#   1800 s: IDT = 0. Should either stop with a clear error, or (if sub-hourly timesteps are
#           supported) run all 8 steps with SWE that differs from the 3600 s run.
#           Observed (2026-11-19): crashes with SIGFPE (exit 136) in EXSNOW19.
#   3600 s: reference.
#   5400 s: IDT should be 1.5 but is truncated to 1. Should either run all 8 steps and melt
#           faster than 3600 s, or stop with a clear error.
#           Observed (2026-11-19): SWE identical to the 3600 s run at every step. Also,
#           end_datehr can only hold whole hours, so the last step (10:30) is cut to 10:00 and
#           only 7 of 8 steps run.
#   7200 s: control. IDT = 2, so it should melt faster than 3600 s.
#
# A clear error must exit non-zero and name model_timestep. gfortran's stop "message" exits 0,
# so use error stop (or a non-zero stop code).
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
scf 1.0
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

# forcing.<dt>.HRU1.csv and namelist.<dt> for each timestep; rows are labeled YYYYMMDDHH like the model
python3 -I - "$B" <<'END_PY'
import sys, datetime as dt
B = sys.argv[1]
t0 = dt.datetime(2016, 3, 1, 0)
for step in (1800, 3600, 5400, 7200):
    with open(f"{B}/forcing.{step}.HRU1.csv", "w") as f:
        f.write("year,mo,dy,hr,prec_mm_s-1,tavg_degc\n")
        for k in range(8):
            t = t0 + dt.timedelta(seconds=k * step)
            p, ta = (10.0 / step, -5.0) if k < 2 else (0.0, 5.0)
            f.write(f"{t:%Y},{t:%m},{t:%d},{t:%H},{p:.8e},{ta}\n")
    end = t0 + dt.timedelta(seconds=7 * step)
    with open(f"{B}/namelist.{step}", "w") as f:
        f.write(f"""&SNOW17_CONTROL
main_id = "basin"
n_hrus = 1
forcing_root = "{B}/forcing.{step}."
output_root = "{B}/out.{step}."
snow17_param_file = "{B}/params.txt"
output_hrus = 0
start_datehr = "{t0:%Y%m%d%H}"
end_datehr = "{end:%Y%m%d%H}"
model_timestep = {step}
warm_start_run = 0
write_states = 0
snow_state_in_root = "{B}/st."
snow_state_out_root = "{B}/st."
/
""")
END_PY

declare -A rc
for step in 1800 3600 5400 7200; do
  timeout 20 "$SB/snow17" "namelist.$step" > "run.$step.log" 2>&1
  rc[$step]=$?
done

swe() { awk 'NR>1 {printf "%s ", $8}' "out.$1.basin.txt" 2>/dev/null; }
has_timestep_error() {  # exited by itself (not a signal or timeout) and mentions model_timestep
  [ "${rc[$1]}" -ne 0 ] && [ "${rc[$1]}" -lt 124 ] && grep -qi "model_timestep" "run.$1.log"
}

fail=0
echo "SWE (mm) after each step:"
for step in 1800 3600 5400 7200; do printf "  %5s s: %s\n" "$step" "$(swe $step)"; done
echo

rows() { awk 'END {print (NR > 1 ? NR - 1 : 0)}' "out.$1.basin.txt" 2>/dev/null || echo 0; }   # data rows, 0 if missing or empty

# 1800 s
n18=$(rows 1800)
if has_timestep_error 1800; then
  echo "1800 s: stopped with a clear error   ok"
elif [ "${rc[1800]}" -eq 0 ] && [ "$n18" -eq 8 ] && [ "$(swe 1800)" != "$(swe 3600)" ]; then
  echo "1800 s: all 8 steps, SWE differs from 3600 s   ok"
else
  echo "1800 s: exit ${rc[1800]}, $n18 of 8 steps, no clear error   FAIL"
  grep -m2 -E "Floating|Program received|SIG|Error|error" run.1800.log | sed 's/^/        /'
  fail=1
fi

# 5400 s
n54=$(rows 5400)
same_prefix=no
[ "$n54" -gt 0 ] && [ "$(swe 5400)" = "$(swe 3600 | cut -d' ' -f1-$n54) " ] && same_prefix=yes
if has_timestep_error 5400; then
  echo "5400 s: stopped with a clear error   ok"
elif [ "${rc[5400]}" -eq 0 ] && [ "$n54" -eq 8 ] && [ "$same_prefix" = no ]; then
  echo "5400 s: all 8 steps, SWE differs from 3600 s   ok"
else
  [ "$same_prefix" = yes ] && echo "5400 s: SWE identical to the 3600 s run at every step (melt scaled for 1 h, not 1.5 h)   FAIL"
  [ "$n54" -eq 0 ] && echo "5400 s: exit ${rc[5400]}, no output and no clear error   FAIL"
  [ "$n54" -gt 0 ] && [ "$n54" -ne 8 ] && echo "5400 s: wrote $n54 of 8 steps (end_datehr cut to a whole hour)   FAIL"
  fail=1
fi

# 7200 s control
if [ "${rc[7200]}" -eq 0 ] && [ "$(swe 7200)" != "$(swe 3600)" ]; then
  echo "7200 s: SWE differs from 3600 s (control)   ok"
else
  echo "7200 s: control run failed or matched 3600 s   FAIL"; fail=1
fi

echo; [ $fail -eq 0 ] && echo "PASS" || echo "FAIL"
exit $fail
