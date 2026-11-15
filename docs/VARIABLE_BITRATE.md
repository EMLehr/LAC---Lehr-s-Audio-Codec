# Quality-target variable bitrate

VBR is an optional rate-control mode alongside the unchanged fixed-rate baseline. It works with all 64 combinations of the six feature switches and the existing temporal submodes. CBR remains the default and the appropriate mode for the assignment's comparisons at closely matched 64/96/128 kb/s.

## Use from MATLAB or the GUI

```matlab
cfg = codec_config();
cfg.rateMode = 'vbr';
cfg.vbr.distortionDB = 0;
cfg.features.huffman = true;  % Independently optional
encode_audio('outputs/prepared/harpsichord.mat','outputs/example_vbr.lac',cfg);
```

Decode normally in another process with `decode_audio`. Version-3 files identify their framing and coding options themselves. `cfg.targetKbps` is ignored for VBR allocation; no 64/96/128 average-rate promise is made. The decoder reports targetKbps = 0 and rateMode = 'vbr'. Old saved configurations without rateMode continue to use CBR.

In `listening_gui`, each encoded side now has a **Fixed bitrate / Variable bitrate** selector. Fixed bitrate offers the original three rates. Variable bitrate offers:

| Preset | Distortion target | Meaning |
| --- | ---: | --- |
| Higher quality | -6 dB | Approximately one-quarter of the selected PAM's band allowance |
| Standard | 0 dB | The selected PAM's band allowance |
| Smaller file | +6 dB | Approximately four times the selected PAM's band allowance |

The API accepts -30 through +30 dB. Lower settings demand less quantization error. These are model-relative targets, not calibrated perceptual quality scores or guarantees of transparency. A and B can mix CBR and VBR or use different VBR presets. Both modes display actual bitrate, binary size, and percentage size reduction. The cache key and saved notes include the mode and quality setting.

Existing MATLAB windows keep their already loaded app instances. Open a fresh listening GUI to use the new controls; a new window is titled `LAC Listening Lab - CBR / VBR`.

## Allocation

For frame f and directly coded band b, define:

```text
target(b,f) = PAM_allowance(b,f) * 10^(distortionDB/10)
D = sum of squared MDCT coefficient quantization errors within the band
```

The encoder evaluates the same candidates as CBR: omitted bands or widths 2 through 15, with the existing stored logarithmic step size. It chooses the lowest-cost candidate satisfying `D <= target`. Costs include step metadata and, when enabled, the Huffman selector and exact coded symbols. Ties choose the first candidate in width order. CBR and VBR share candidate generation; CBR keeps its previous greedy fixed-budget allocation.

If no candidate meets a target, VBR chooses the candidate with minimum distortion (then minimum cost) and records a core target miss. It does not falsely claim success or increase beyond supported precision. Silence can omit every coefficient. Once candidates are chosen, each frame is packed into the minimum whole number of bytes. There is no padding to an arbitrary file bitrate, average-rate controller, reservoir, or user-set peak-rate cap.

With BWE enabled, VBR controls distortion in the directly coded lower half. The fixed high-band envelope/noise representation is still lossy and is not guaranteed to meet the same target. `coreTargetMisses` counts unattainable directly coded targets; `bandsOverScaledTarget` additionally checks all reconstructed bands, including BWE. These are model diagnostics, not listening judgments.

## File size and compatibility

Version 3 adds a two-byte length prefix to each frame and retains the existing payload syntax. A ten-second input has 470 frames, so its framing overhead is 940 bytes. Headers, band widths, steps, entropy selectors, BWE parameters, and final bit alignment are all counted. VBR permits only 0-7 alignment bits per frame. [BITSTREAM.md](BITSTREAM.md) specifies the format and validation rules.

```text
actual kb/s = total file bytes * 8 / original duration / 1000
size reduction (%) = 100 * (1 - total file bytes / (2 * original sample count))
```

The reference is 48 kHz mono 16-bit PCM, or 768 kb/s. Negative size reduction is possible when a very short file's mandatory overhead exceeds its PCM size. Unlike CBR, VBR can encode even a one-sample input because it does not have to fit a duration-derived target budget.

Fixed-rate files remain version 1 or 2 and preserve their bytes. The decoder supports all three versions; older decoders reject version 3 rather than misinterpreting it. No codec feature is silently enabled by selecting VBR.

## Why PAM switches now change size

PAM settings change distortion allowances. Stricter allowances can require more bits; looser allowances can permit fewer. Therefore a smaller VBR file from a different PAM is not automatically a more efficient representation at equal perceived quality. In particular, the enhanced mapping deliberately protects sensitive regions more strongly and can increase the file size.

Huffman can now reduce the actual file size because entropy savings are no longer padded back to a fixed budget. Its selector overhead can still hurt bands with little symbol redundancy. The least-cost satisfying candidate can occasionally differ from direct packing, so equal decoded audio is a result to verify, not a blanket guarantee. BWE can reduce directly coded bandwidth while adding parameter overhead and different high-frequency distortion.

## Reproduce and verify

After the earlier prepared inputs and stage 8 development encodes exist:

```text
matlab -batch "stage10_verify_vbr;"
matlab -batch "stage10_vbr('encode');"
matlab -batch "stage10_vbr('decode');"
matlab -batch "stage10_vbr('evaluate');"
matlab -batch "stage10_verify_vbr_gui;"
```

The development stage covers 12 configurations, three targets, and the two development excerpts: 72 encoded/decoded pairs. Configurations include baseline, each PAM option alone, all four PAM options, and the optional coding-tool combinations with baseline/all-four PAM. Results are in `outputs/vbr/`; speech remains held out. The GUI can generate other combinations on demand.

Verified with MATLAB R2025b Update 1:

- 192 exact encoder/decoder round trips: all 64 six-switch combinations at all three VBR targets, with finite aligned output and complete bit accounting.
- Lowest-cost feasible candidate selection, reported unattainable targets, and nonincreasing file sizes as the target is loosened for a fixed configuration.
- Four tiny/arbitrary silent lengths, malformed prefixes, truncation, trailing bytes, invalid flags/rates, and excess frame padding.
- Sixteen earlier CBR development files remain byte-identical, covering both file versions, both PAM groups, both sources, and all coding-tool modes at 96 kb/s.
- Existing stage 3 and stage 8 codec tests pass, including 80 fixed-rate round trips across all feature combinations.
- All 72 development files decode in a fresh MATLAB process. No directly coded band missed its chosen target in these development runs; BWE errors are separately reported.
- GUI checks pass for independent modes, quality presets, percentages, and cache identity. Existing listening-GUI regression checks pass. Code Analyzer reports zero messages across project MATLAB files.

## Development measurements

At the standard 0 dB target, selected results are:

| Source | Configuration | Actual kb/s | Size reduction | Waveform SNR (dB) |
| --- | --- | ---: | ---: | ---: |
| Harpsichord | Baseline | 94.898 | 87.64% | 11.851 |
| Harpsichord | Baseline + Huffman | 70.137 | 90.87% | 11.851 |
| Harpsichord | Enhanced mapping only | 110.775 | 85.58% | 19.465 |
| Harpsichord | All four PAM options | 96.231 | 87.47% | 17.419 |
| Castanets | Baseline | 114.963 | 85.03% | 16.976 |
| Castanets | Baseline + Huffman | 114.010 | 85.15% | 16.976 |
| Castanets | Enhanced mapping only | 128.585 | 83.26% | 17.542 |
| Castanets | All four PAM options | 93.602 | 87.81% | 16.219 |

The baseline harpsichord payload varies from 13 to 545 bytes per frame at this setting, plus each two-byte prefix. Its overall rates at -6 / 0 / +6 dB are 117.096 / 94.898 / 76.134 kb/s. `frame_rates.png` plots the changing frame rates; `measurements.csv/json` reports every condition, including percentages, framing/payload/padding, waveform and onset errors, and target misses.

For the standard harpsichord example, baseline and baseline-plus-Huffman decoding were also verified sample-identical: Huffman reduces the file from 118,623 to 87,671 bytes without changing those reconstructed samples. This measured example distinguishes lossless representation savings from changes in PAM allowances.

These are unmatched-rate experiments. They supplement rather than replace the fixed-rate PAM investigation. Listening observations remain uncollected, and lower VBR size or higher SNR alone does not establish better perceived quality.
