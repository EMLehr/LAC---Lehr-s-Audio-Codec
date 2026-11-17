# Documentation

Start with the [project README](../README.md) for setup, listening, and a short description of each option.

## Usage and reproduction

- [Workflows](WORKFLOWS.md): input preparation, stage commands, tests, outputs, and source organization.
- [Assignment settings](ASSIGNMENT.md): exact restrictions for the PAM-only comparison.
- [Listening GUI](LISTENING_GUI.md): A/B playback, shared gain, cache, notes, and controls.

## Algorithms and results

| Document | Contents |
| --- | --- |
| [Baseline](BASELINE.md) | Transform normalization, quantization, masking equations, and assumptions |
| [Baseline results](BASELINE_RESULTS.md) | Reconstruction checks, fixed-rate measurements, and limitations |
| [Temporal masking](TEMPORAL_MASKING.md) | Post-masking, pre-echo allowance control, and measurements |
| [Tonal maskers](TONAL_MASKERS.md) | Tonality estimation and tonal/noise masking comparison |
| [Final PAM options](FINAL_PAM_OPTIONS.md) | Adaptive spreading, enhanced band mapping, and all 16 PAM combinations |
| [Coding features](CODING_FEATURES.md) | Original fixed Huffman and bandwidth extension |
| [Variable bitrate](VARIABLE_BITRATE.md) | Quality targets, file rates, and compression percentages |
| [Piecewise allocation](PIECEWISE_ALLOCATION.md) | Saving ratios, bit bucket, and accounting |
| [Codec experiments](CODEC_EXPERIMENTS.md) | Zero runs, learned books, smarter quantization, PE, and switched windows |
| [Bitstream](BITSTREAM.md) | Standalone decoding specification for versions 1–5 |

The feature documents contain historical measurements at their stated configurations. They do not claim human listening results or that every added option improves quality. Run `lac_setup` once before the MATLAB examples; fresh batch processes also need setup.
