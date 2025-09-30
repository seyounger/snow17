# 3-Parameter Areal Depletion Curve (ADC) Enhancement

## Overview

The enhanced BMI Snow17 implementation now supports both the traditional 11-parameter ADC and an advanced 3-parameter ADC calibration method, based on the approach used in the NWRFC `nwsrfs-hydro-models` repository.

## Background

The Snow17 model uses an Areal Depletion Curve (ADC) to represent how snow-covered area decreases as snow water equivalent decreases. Traditionally, this is specified as 11 discrete points from 0.0 to 1.0 in 0.1 increments.

The 3-parameter approach uses a non-linear functional form to generate these 11 points automatically, reducing the parameter space and potentially improving calibration efficiency.

## 3-Parameter ADC Formula

```
ADC = a * x^b + (1-a) * x^c
```

Where:
- `x` is the ratio from 0.0 to 1.0 (corresponding to the 11 ADC points)
- `a` is a shape parameter (0 < a < 1)
- `b` is an exponent parameter (b ≥ 0)  
- `c` is an exponent parameter (c ≥ 0)

## Curve Shape Control

The parameters control different curve shapes:
- **b < 1 & c < 1**: Concave up curve
- **b > 1 & c > 1**: Concave down curve  
- **b < 1 & c > 1** OR **b > 1 & c < 1**: S-shaped curve

## Usage

### Configuration Files

To use 3-parameter ADC, specify the three parameters in your parameter file instead of the 11 individual `adc1` through `adc11` parameters:

```
adc_a    0.65
adc_b    0.8
adc_c    3.0
```

### BMI Interface

The 3-parameter ADC parameters are accessible via the BMI interface:

- **Variable names**: `adc_a`, `adc_b`, `adc_c`
- **Type**: `real`
- **Units**: `unitless`
- **Grid**: scalar (grid=0)

### Parameter Ranges

Recommended parameter ranges based on NWRFC implementation:
- `adc_a`: 0.1 to 0.9 (typical: 0.4 to 0.8)
- `adc_b`: 0.1 to 5.0 (typical: 0.5 to 2.0)
- `adc_c`: 0.1 to 5.0 (typical: 1.0 to 4.0)

## Implementation Details

When 3-parameter ADC is used:

1. The BMI interface automatically detects the presence of `adc_a`, `adc_b`, `adc_c` parameters
2. Sets the `use_3param_adc` flag for the corresponding HRUs
3. Computes the 11-point ADC using the NWRFC reverse lookup algorithm
4. The Snow17 model uses the computed 11-point ADC normally

The reverse lookup algorithm ensures monotonicity and applies the standard 0.05 minimum value constraint.

## Advantages

1. **Reduced parameter space**: 3 parameters instead of 11
2. **Automatic monotonicity**: The functional form ensures valid ADC curves
3. **Calibration efficiency**: Fewer parameters to optimize
4. **Physical interpretation**: Parameters have more direct physical meaning
5. **Backward compatibility**: Can still use traditional 11-point specification

## Example Usage

See the example configuration files:
- `configs/example_3param_adc_config.json`
- `configs/snow17-init-cat-27-3param-adc.namelist.input` 
- `configs/snow17-params-cat-27-3param-adc.txt`

## References

Based on the implementation in:
- NOAA-NWRFC/nwsrfs-hydro-models repository
- `model-source/sac_snow.f90` 
- `rfchydromodels/R/sac-snow-uh.R` (adc3 function)