# Final PAM options: spreading and band mapping

The four approved PAM options are implemented, independently selectable, and default off. This stage adds `features.enhancedSpreading` and `features.enhancedBandMapping` to the existing tonal and temporal options. It preserves the baseline, quantizer, allocator, transform, byte budget, binary format, and decoder. Huffman coding and bandwidth extension are separate future codec features.

## Hypotheses

1. Source-frequency- and level-dependent spreading may better distribute allowed distortion across neighboring auditory bands than fixed slopes.
2. A harmonic mapping from bin thresholds to a single band allowance may reduce errors in sensitive parts of a band that an ordinary sum underweights.

Both are experiments, not guaranteed perceptual improvements. Parameters and mapping were chosen before the development comparison below, without tuning on speech. Speech remains held out. The baseline uses meaningful fixed spreading and summed allowances; neither feature is required to make the baseline functional.

## Enhanced spreading

The baseline uses +30 dB/Bark on the lower-frequency side and -15 dB/Bark on the upper-frequency side. The new option uses +27 on the lower side and a variable negative upper slope. This is an adaptation of the slope relation in [ITU-R BS.1387-2, section 2.1.7](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1387-2-202305-I%21%21PDF-E.pdf), not an implementation of its complete PEAQ ear model. The broader motivation for level/frequency-dependent spreading is discussed in [Herre and Dick's tutorial review](https://www.mdpi.com/2076-3417/9/14/2854).

For source band b in frame t, with raw squared MDCT energy E, arithmetic-mean bin frequency fc in Hz, and N = 1024:

```text
L(b,t) = clamp(referenceSPL + 10 log10(max(E(b,t)/N, realmin)), -20, 100)
u(b,t) = clamp(24 + 230/fc(b) - 0.2 L(b,t), 8, 40)
d(a,b) = BarkCenter(a) - BarkCenter(b)
S(a,b,t) = 27 min(d(a,b),0) - u(b,t) max(d(a,b),0)
M(a,t) = sum_b 10^(S(a,b,t)/10) * W(b,t)
```

Here a is the target band. W is source energy after the existing masking offset: fixed 29 dB when tonality is off, or the existing tonal/noise offset when on. L uses raw E, before that offset. Higher source levels give a shallower upward slope, within bounds; lower-side attenuation stays fixed. Band centers and boundaries remain unchanged. Gains are one on the diagonal and at most one elsewhere. Spreading is not column-normalized, matching the baseline's summation convention.

Our level proxy uses the existing assumption that digital mean-square 1 corresponds to 96 dB SPL. It does not reproduce the ITU model's internal-noise/excitation calculation or its complete normalization. The level bounds and slope bounds are explicit engineering guards for this simplified codec, not fitted listening data. Silent source bands contribute zero despite the finite logarithm guard.

Implementation: `+pac/spread_maskers.m`. Settings live under `cfg.pam.spreading`. `details.spreading` records source frequencies, levels, and slopes; `details.spreadingDB` is target-by-source-by-frame when enabled (the baseline remains a fixed 2-D matrix).

## Enhanced mapping

Let T(k,t) be the positive global threshold in squared MDCT units. For a band containing n coefficients, the baseline allowance is the sum of its bin thresholds. The optional mapping instead uses n times their harmonic mean:

```text
A_sum = sum_k T(k)
A_harmonic = n^2 / sum_k (1/T(k))
```

For thresholds `[1, 1, 9, 9]`, the sum is 20 and the new allowance is 7.2. Uniform thresholds produce the same allowance under either mapping. In general:

```text
n * min(T) <= A_harmonic <= A_sum
```

One interpretation assumes expected error energy D/n per coefficient. Then average threshold-normalized error is `D/n^2 * sum(1/T)`. Setting that average to one yields the harmonic allowance. This is a scalar approximation: quantization error is not actually uniform, and an average cannot guarantee that every bin remains below threshold. The allocator also operates under a finite rate budget and can exceed allowances.

The existing allocator still minimizes band squared error divided by its allowance, using the same candidate quantizers and bit costs. Lowering an allowance increases that band's priority. Because this PAM distributes signal masking uniformly inside each band, within-band variation comes from threshold in quiet where it dominates. The mapping therefore particularly affects such regions, rather than adding finer signal-masker resolution.

Implementation: `+pac/map_allowances.m`. It evaluates the harmonic expression after scaling by the smallest threshold to avoid reciprocals of very small numbers. It also returns the ordinary sum for diagnostics. Mapping never changes the global masking curve itself.

## Combination and reproduction

Processing order is source energy and optional tonal offsets, fixed or enhanced spreading, optional temporal processing, combination with threshold in quiet, then summed or harmonic band allowances. Explicit temporal state continues across chronological chunks; no state leaks between files. The decoder reconstructs stored symbols and step sizes without rerunning any PAM.

```matlab
cfg = codec_config();
cfg.features.enhancedSpreading = true;
cfg.features.enhancedBandMapping = true;
% Independently optional:
cfg.features.tonalMaskers = true;
cfg.features.temporalMasking = true;
cfg.targetKbps = 96;
encode_audio('outputs/prepared/harpsichord.mat', 'outputs/example.lac', cfg);
```

Run `decode_audio('outputs/example.lac','outputs/example_decoded.wav')` in a fresh MATLAB process. No encoder state, source audio, or sidecars are needed by decoding.

For the complete comparison, after stage 6 encoding:

```text
matlab -batch "stage7_verify_pam;"
matlab -batch "stage7_pam_options('encode');"
matlab -batch "stage7_pam_options('decode');"
matlab -batch "stage7_pam_options('evaluate');"
```

`pac.pam_config(mask,rate)` enumerates masks 0 through 15, with bit values 1 = tonal, 2 = temporal, 4 = spreading, 8 = mapping. Mask 0 is baseline and mask 15 enables all four. Model names record the enabled options. The comparison covers two development excerpts, three rates, and all 16 combinations: 96 files. Results go to `outputs/pam_options/` and are excluded from Git.

## Verification

Verified with MATLAB R2025b Update 1:

- Spreading responds to frequency and level, preserves the lower slope, and stays finite on silence.
- Mapping passes the known example, uniform-threshold equivalence, and analytic bounds across thresholds spanning 40 orders of magnitude; global curves are unchanged.
- All 16 combinations pass finite-silence checks and chronological chunk/state equivalence.
- 48 synthetic codec round trips (16 combinations at three rates) exactly match encoder-side quantized reconstruction.
- Existing codec, temporal, and tonality test suites pass.
- All 24 prior development files (baseline, temporal, tonal, tonal+temporal) remain byte-identical with the new options off.
- All 96 development files decode in a fresh process with the unchanged decoder and correct sample counts. MATLAB Code Analyzer reports zero messages across project MATLAB sources.

## Development measurements

All ten-second files are exactly 80,000, 120,000, or 160,000 bytes, including headers, side information, and padding: actual rates match 64, 96, and 128 kb/s. Compression ratios against 768 kb/s PCM are 12:1, 8:1, and 6:1. Padding is reported separately and is not useful coded information. Inputs and reconstructed playback levels are unchanged.

The table reports changes from baseline. Each cell is **overall SNR change / pre-onset error change**, both in dB. Positive SNR change means less total squared error; negative pre-onset change means less squared error in the selected pre-onset windows.

| Source | kb/s | Spreading only | Mapping only | Spreading + mapping | All four |
| --- | ---: | ---: | ---: | ---: | ---: |
| Harpsichord | 64 | +0.020 / 0.000 | +2.760 / -12.418 | +2.731 / -12.418 | +2.344 / -14.028 |
| Harpsichord | 96 | -0.009 / 0.000 | +3.887 / -12.255 | +3.902 / -12.255 | +3.685 / -17.384 |
| Harpsichord | 128 | +0.001 / 0.000 | +5.376 / -21.729 | +5.404 / -21.729 | +5.294 / -18.363 |
| Castanets | 64 | +0.158 / -1.140 | +0.016 / -0.085 | +0.161 / -1.138 | -0.173 / +3.843 |
| Castanets | 96 | +0.045 / -0.248 | +0.020 / -0.002 | +0.064 / -0.250 | +0.025 / -0.550 |
| Castanets | 128 | +0.008 / -0.217 | +2.472 / +6.946 | +2.522 / +6.773 | +0.610 / +2.287 |

The source-only onset detector and 20 ms pre/post windows are unchanged from the temporal stage: one detected harpsichord onset and 31 castanet onsets. These windows are a limited proxy for transient distortion, not a perceptual pre-echo score. In particular, the large harpsichord pre-onset reductions describe just one selected region.

Spreading alone has small effects on these inputs. Mapping produces substantial overall error reductions on harpsichord, but the 128 kb/s castanet result demonstrates a tradeoff: total error falls while pre-onset error rises. Enabling all options does not consistently outperform the simpler combinations. Full absolute measurements, segmental SNR, RMSE, post-onset error, padding, and allocation changes for all 96 conditions are in `measurements.csv/json`; `selected_measurements.csv/json` contains the configurations above.

No listening observations have been collected, and speech has not been quality-tested. These results do not establish perceptual superiority or justify automatically enabling every switch. Final model selection and the assignment's focused investigation remain pending listening and the reserved evaluation.

## Masking-curve example

`final_pam_comparison.png` uses harpsichord frame 95, centered at approximately 2.0053 seconds, the same frame used in earlier comparisons. The spectrum and thresholds use `10 log10(power/1024)`, in dB relative to mean-square 1, not PSD. The plot states the 96 dB SPL reference assumption. It shows global curves, band allowances, and actual 96 kb/s widths.

Mapping-only has exactly the baseline global curve. In this frame it reduces the first band's allowance substantially and changes its width from zero to four bits per coefficient. Other bands give up some precision under the same total budget. The spreading-only curve is close to baseline here; the all-four curve also reflects the already implemented tonal and temporal models. Machine-readable curves, allowances, widths, and spreading levels/slopes are saved alongside the plot in `masking_frame.mat/json`.
