# Baseline development checkpoint — 2026-11-13

Environment: MATLAB R2025b Update 1 on Windows. All optional features off. Source preparation: first 10 seconds, channel average, MATLAB `resample` from 44.1 kHz to 48 kHz, no normalization. Prepared double-precision MAT data are the reference. Decoded float32 WAV data are used for these measurements.

Speech is held out. These are development results for harpsichord and castanets, not the final assignment submission or evidence of a PAM improvement.

## Measured development results

| Source | Target / actual kb/s | File bytes | PCM compression ratio | SNR dB | Segmental SNR dB | Padding bits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Harpsichord | 64 / 64 | 80,000 | 12:1 | 9.955 | 6.100 | 69,859 |
| Harpsichord | 96 / 96 | 120,000 | 8:1 | 10.919 | 8.061 | 107,254 |
| Harpsichord | 128 / 128 | 160,000 | 6:1 | 11.298 | 10.775 | 144,676 |
| Castanets | 64 / 64 | 80,000 | 12:1 | 9.311 | 10.347 | 43,550 |
| Castanets | 96 / 96 | 120,000 | 8:1 | 12.776 | 13.632 | 66,632 |
| Castanets | 128 / 128 | 160,000 | 6:1 | 13.650 | 17.303 | 89,688 |

All six files decode to exactly 480,000 samples. No reconstructed development WAV samples exceeded full scale. That observation does not guarantee all future inputs stay in range; float WAV output preserves overshoots rather than concealing them.

SNR alone does not establish perceptual quality. Listening observations are **not yet assessed**. The measured error is substantial and the baseline should not be described as perceptually transparent.

## Rate accounting example

Harpsichord at 96 kb/s, 10 seconds:

- Header: 88 bytes = 704 bits.
- Frame side information: 117,888 bits.
- Quantized coefficients: 734,154 bits.
- Zero padding: 107,254 bits.
- Total: 960,000 bits = 120,000 bytes = 96 kb/s.

All required rates are exact for ten-second files because their budgets are integer bytes. For other lengths, total bytes are rounded down; the discrepancy is less than one byte per file. Silence or unusable residual frame capacity can produce substantial padding. Padding is counted in actual bitrate but is not useful compression performance. The format has no bit reservoir.

## Executed validation

1. `stage1_prepare_inputs`: all three files prepared at 48 kHz mono, 480,000 samples each.
2. `stage2_verify_transform`: 55 cases covering silence, random noise, a sinusoid, first-sample and last-sample impulses at lengths 1, 2, 17, 1023, 1024, 1025, 2047, 2048, 2049, 7919, and 480000. Worst absolute reconstruction error approximately 3.41e-13; energy consistency also checked.
3. `stage3_verify_codec`: exact signed-symbol/scale packing recovery for 15 supported widths; nine synthetic file round trips at all required rates; comparison against independently reconstructed encoder-side quantized coefficients; exact sample count; complete-file accounting; float-WAV fidelity; finite silent PAM and masking spread; unsupported toggles and selected malformed files rejected.
4. `stage4_encode_baseline`: six development conditions generated.
5. `stage4_decode_baseline`: invoked in a separate MATLAB process after encoding; reads encoded `.lac` files, not prepared inputs or encoder diagnostic files.
6. `stage4_evaluate_baseline`: objective measurements and an identified baseline masking plot generated.

Machine-readable validation and measurements are in the local ignored outputs/ directory and can be regenerated with README commands. The masking example uses harpsichord frame 95, centered at approximately 2.0053 seconds. The plot includes the input MDCT spectrum, baseline global threshold, and threshold in quiet. An improved-PAM curve will be added once an improvement exists.

## Remaining work

- Listen to development outputs at matched levels and document artifacts.
- Implement the approved optional features individually, preserving this baseline configuration and recording any baseline correctness fixes.
- Select a focused PAM hypothesis and compare at closely matched actual rates, keeping non-PAM coding settings fixed.
- Evaluate held-out speech only after model choices are frozen.
- Produce the final baseline/improved submission matrix and report.
