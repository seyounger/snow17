# 3-Parameter Areal Depletion Curve (ADC) Enhancement

## Overview

Thhis BMI Snow17 implementation supports both the traditional 11-parameter ADC and 3-parameter ADC calibration method, based on the approach used in the NWRFC `nwsrfs-hydro-models` repository.

## Background

The Snow17 model uses an Areal Depletion Curve (ADC) to represent how snow-covered area decreases as snow water equivalent decreases. Traditionally, this is specified as 11 discrete points from 0.0 to 1.0 in 0.1 increments.

The 3-parameter approach calibrates a non-linear functional form and generates the 11 points along the curve.

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

To use 3-parameter ADC, specify the three parameters in your calibration config or in the parameter files instead of the 11 individual `adc1` through `adc11` parameters:

```
adc_a    0.2
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
- `adc_a`: 0.1 to 0.25
- `adc_b`: 0.05 to 50
- `adc_c`: 0.5 to 50

## Implementation Details

When 3-parameter ADC is used:

1. The BMI interface automatically detects the presence of `adc_a`, `adc_b`, `adc_c` parameters
2. Sets the `use_3param_adc` flag for the corresponding HRUs
3. Computes the 11-point ADC using the NWRFC reverse lookup algorithm
4. The Snow17 model uses the computed 11-point ADC normally

The reverse lookup algorithm ensures monotonicity and applies the standard 0.05 minimum value constraint.

## References

Based on the implementation in:
- NOAA-NWRFC/nwsrfs-hydro-models repository
- `model-source/sac_snow.f90` 
- `rfchydromodels/R/sac-snow-uh.R` (adc3 function)