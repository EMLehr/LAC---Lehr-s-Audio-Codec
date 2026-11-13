# Tonal/noise masker option — 2026-11-13

Enable `cfg.features.tonalMaskers = true`. The option defaults off and can be combined with temporal masking. It changes the PAM only; the MDCT, quantizer, allocator, binary representation, and decoder are unchanged.

## Hypothesis and design

Noise-like maskers can hide more noise than tonal maskers. The hypothesis is that distinguishing them will direct relatively more precision toward tonal regions at the same file rate. [Herre and Dick, section 2.2](https://www.mdpi.com/2076-3417/9/14/2854) discuss tonality estimation and spectral flatness. This is a simple MDCT-domain adaptation, not a reproduction of MPEG Model 1 or Model 2.

Within each auditory band, compute coefficient power `p[k] = X[k]^2`, its arithmetic mean `mu`, and spectral flatness:

`SFM_dB = min(0, 10 * mean(log10(max(p[k]/mu, 1e-12))))`.

The geometric/arithmetic mean ratio is computed in the log domain. The floor is relative to band power, so classification is gain-independent apart from extreme floating-point limits. Silent bands receive score zero and contribute zero masker energy.

Convert flatness into a continuous score:

`alpha = clip((-6 - SFM_dB)/24, 0, 1)`.

Flatness at or above -6 dB means noise-like (alpha 0); at or below -30 dB means tonal (alpha 1). These initial engineering endpoints were chosen before development comparisons, not established as universal perceptual boundaries. Random real MDCT coefficients need not have perfectly flat power, motivating a noise endpoint below 0 dB.

The masking offset is `offset[b,t] = 15 + alpha[b,t]*(29-15)` dB. Strongly tonal maskers receive the conservative baseline 29 dB offset; noise-like maskers receive 15 dB. These endpoints are design choices, not laboratory masking thresholds. This experiment changes both type-dependent offsets and their average relative to baseline; a future uniform-offset control would help isolate these effects.

Weight the **source masker** before applying the unchanged spreading function:

`M[b,t] = sum_m(S[b,m] * E[m,t] * 10^(-offset[m,t]/10))`.

The source band's character controls its masking influence on neighboring bands. Temporal processing, when enabled, operates on these weighted simultaneous masking values. Quiet-threshold combination and sum-to-band allowance mapping are unchanged.

Parameters are in `cfg.pam.tonal`: `noiseFlatnessDB`, `toneFlatnessDB`, `noiseOffsetDB`, and `toneOffsetDB`. The disabled path preserves the original arithmetic exactly. Tonality itself carries no time state; combined operation uses the temporal option's explicit history.

## Reproduction and validation

Use the stage 6 commands in README.md. The encoding stage creates baseline, temporal-only, tonal-only, and combined files for harpsichord and castanets at 64/96/128 kb/s. Speech remains held out. Executed checks:

- Equal-energy flat and concentrated spectra receive the expected relative masking strengths.
- Sign/scale invariance and finite silence behavior in all toggle combinations.
- A real 997 Hz sinusoid receives higher tonality than white noise near its peak: mean test scores approximately 0.403 and 0.005. The non-unit tone score illustrates leakage/phase limitations.
- Source-masker weighting propagates consistently into neighboring target bands.
- Combined temporal state agrees across chunks and resets between files.
- Disabled classification is baseline-exact; equal offset endpoints reproduce baseline thresholds within floating-point tolerance.
- Six synthetic tonal/combined matched-rate round trips recover exactly the encoder-side quantized reconstruction.
- Existing baseline and temporal synthetic suites still pass.
- Twelve existing baseline/temporal development files remain byte-identical; all 24 stage 6 files decode in a fresh MATLAB process.
- Shared evaluation code reproduces the previous temporal measurement JSON exactly. MATLAB Code Analyzer reports zero messages.

## Development results

Every 10-second file is exactly 80,000 / 120,000 / 160,000 bytes at 64 / 96 / 128 kb/s, including metadata and padding. Compression ratios against 768 kb/s PCM are 12:1 / 8:1 / 6:1. Complete statistics and onset records are saved in local `outputs/tonality/` JSON/CSV files.

Changes below are relative to the all-off baseline. Higher SNR change means less global squared error. **Negative pre-onset error change means less error; positive means worse.** The original-signal onset detector and 20 ms windows are unchanged from the temporal stage and are not standardized auditory tests.

| Source | kb/s | Tonal SNR change dB | Combined SNR change dB | Tonal pre-onset error change dB | Combined pre-onset error change dB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Harpsichord | 64 | -0.1032 | -0.1146 | -0.0009 | -0.0486 |
| Harpsichord | 96 | -0.0695 | -0.0830 | -0.0475 | -0.2318 |
| Harpsichord | 128 | +0.0004 | -0.0117 | -0.0037 | +0.0169 |
| Castanets | 64 | -0.4290 | -0.0851 | -0.8780 | +3.6899 |
| Castanets | 96 | -0.0881 | -0.0188 | +0.3688 | -0.4340 |
| Castanets | 128 | +1.3214 | -0.0012 | +8.2619 | +0.5604 |

This candidate does **not** show a consistent objective improvement. The large castanets SNR gain at 128 kb/s coexists with substantially worse pre-onset error. Feature combinations are not automatically beneficial: at 64 kb/s, combined pre-onset error worsens even though each feature individually reduces that measure. These outcomes are retained; parameters were not retuned to erase regressions.

Listening is **not yet assessed**. No final model selection or quality claim is made. The feature stays toggleable and off by default.

## Identified masking example and limitations

The generated `tonality_masking_comparison.png` uses harpsichord frame 95, center 2.0053 s, the same fixed frame as the original baseline plot. It overlays input and all relevant global thresholds, shows per-band scores, and compares actual widths at 96 kb/s. Levels are `10*log10(X^2/1024)` relative to digital mean-square 1 per bin, not PSD; the unity-power reference remains 96 dB SPL.

Band 7 changes from 4 to 5 bits, bands 16/17 from 3/4 to 4/5, while bands 2/3 drop from 5 to 4 and band 20 from 4 to 3. Temporal processing happens to give the same allocation in this frame. Full classifier values and threshold sequences are retained locally.

Spectral flatness can confuse sparse noise, spectral tilt, multiple harmonics, and narrow-band content. MDCT phase and leakage affect scores, especially in bands with few coefficients. Band classification is not explicit extraction of individual tonal peaks/noise maskers. No tonality smoothing or predictability estimator is included. These limitations and the measured regressions require listening and further controlled investigation before claiming improved quality.
