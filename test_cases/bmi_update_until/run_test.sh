#!/usr/bin/env bash
# Test for the issue "update_until ignores the requested time".
#
# snow17_update_until (src/bmi/bmi_snow17.f90) loops until end_datetime instead of the requested
# time, so one call runs every remaining timestep. Builds update_until_test.f90 against the
# Snow17 sources in this repo and runs it on 6 hourly timesteps of snowfall (no ngen needed).
# See update_until_test.f90 for the checks.
#
# Observed (2026-11-20): update_until(start + 2*dt) runs until the clock reaches end_datehr,
# 3 timesteps past the target (sneqv 5.750 mm instead of 2.300). The next
# update_until(start + 4*dt) returns BMI_FAILURE, because the clock is already past it.
#
# Usage: ./run_test.sh       (FC=<Fortran compiler>, default gfortran)
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$T/../.." && pwd)
FC=${FC:-gfortran}
FFLAGS="-cpp -ffree-line-length-none -fcheck=bounds"
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

# require the driver's PASS line too: a Fortran stop inside the model ends the driver with exit 0
./update_until_test namelist.input > run.log 2>&1
rc=$?
grep -v -E '^ +(Reading|Initializing|--)|^(#|Error termination|ERROR STOP)|^$' run.log
if [ $rc -eq 0 ] && grep -qx "PASS" run.log; then exit 0; fi
grep -qx -E "PASS|FAIL.*" run.log || { echo; echo "FAIL: the driver ended before reporting (exit $rc; see $B/run.log)"; }
exit 1
