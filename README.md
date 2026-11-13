# LAC — Lehr's Audio Codec

A MATLAB educational perceptual audio codec with a reproducible baseline and an architecture for independently selectable improvements. This is a custom AAC-style codec, **not a standards-compliant AAC or MP3 encoder**. `.lac` files need this project's decoder.

The baseline implements 48 kHz mono input, 2048-sample sine-window MDCT analysis, 1024 coefficients and a 1024-sample hop, a baseline psychoacoustic model (PAM), band-dependent scalar quantization, complete-file rate control, direct bit packing, and standalone decoding.

## Current status

Baseline stages 1–4 are implemented. Transform and bitstream tests run in MATLAB R2025b Update 1. Development outputs exist locally for harpsichord and castanets at 64, 96, and 128 kb/s. Speech is reserved for final quality testing after choosing PAM changes.

All optional features default to **off**. Temporal masking is implemented, with separately controllable post-masking and pre-echo control. Tonal/noise classification, enhanced spreading, enhanced band-allowance mapping, Huffman coding, and SBR-inspired bandwidth extension remain unimplemented; enabling those switches raises an explicit error. No improvement is silently included in the baseline.

## Requirements

- MATLAB; verified with R2025b Update 1 on Windows.
- Signal Processing Toolbox for `resample` during input preparation.
- The encoder/decoder and transform use base MATLAB. Audio Toolbox is not required.
- Original test WAVs in the project root. References, originals, and generated artifacts are excluded from Git.

Download the originals from the [QOA SQAM sample collection](https://qoaformat.org/samples/), following the [EBU usage terms](https://qc.ebu.io/testmaterials/523/):

- [English female speech](https://qoaformat.org/samples/sqam/49_female_speech_english_mono.wav)
- [Harpsichord](https://qoaformat.org/samples/sqam/40_harpsichord_arpegio_melodious_phrase_stereo.wav)
- [Castanets](https://qoaformat.org/samples/sqam/27_castanets_single_tone_rhythm_stereo.wav)

Keep these filenames unchanged. The supplied speech WAV actually has two channels despite its filename. Preparation reads metadata, averages channels, takes the first 10 seconds at the original sample rate, and resamples to 48 kHz with no level normalization. Prepared `.mat` doubles are the authoritative encoder inputs; float WAVs are listening copies.

## Run the stages

Open MATLAB in the project root, or use these shell commands from the root. Each `-batch` starts a separate MATLAB process:

```text
matlab -batch "stage1_prepare_inputs;"
matlab -batch "stage2_verify_transform;"
matlab -batch "stage3_verify_codec;"
matlab -batch "stage4_encode_baseline;"
matlab -batch "stage4_decode_baseline;"
matlab -batch "stage4_evaluate_baseline;"
```

The stages are MATLAB functions, so the same names can be run in the Command Window. They never require variables left in the base workspace. Stage 2 and stage 3 use synthetic signals and do not require the source audio. Stage 4 consumes saved preparation results. Run decoding in its own batch process to demonstrate independence from encoder state.

To encode/decode a single file in MATLAB:

```matlab
cfg = codec_config();
cfg.targetKbps = 96;
stats = encode_audio('outputs/prepared/harpsichord.mat', ...
    'outputs/harpsichord_96k.lac', cfg);
[y, info] = decode_audio('outputs/harpsichord_96k.lac', ...
    'outputs/harpsichord_96k_decoded.wav');
```

The output directory must exist. The encoder also accepts an already prepared 48 kHz mono WAV. It rejects unprepared stereo/44.1 kHz inputs. The decoder only needs the `.lac` file and its MATLAB source dependencies; JSON and diagnostic MAT files are optional encoder-side records.

After PAM choices are frozen, `stage4_encode_baseline(true)` includes speech. Decode as usual, then `stage4_evaluate_baseline(true)` includes it in measurements. Do not use this held-out quality result to tune parameters.

## Temporal masking

Enable it for an individual encode with:

```matlab
cfg = codec_config();
cfg.features.temporalMasking = true;
cfg.targetKbps = 96;
stats = encode_audio('outputs/prepared/castanets.mat', ...
    'outputs/castanets_temporal_96k.lac', cfg);
```

Setting the master toggle back to false restores the baseline. With it true, `cfg.pam.temporal.postMasking` and `cfg.pam.temporal.preEchoControl` independently enable its two components (both true by default). The standard decoder works without any new settings or metadata files. PAM choices are recorded in encoder JSON; the decoder does not need them.

After stages 1 and 4 have created the baseline development files, run:

```text
matlab -batch "stage5_verify_temporal;"
matlab -batch "stage5_temporal('encode');"
matlab -batch "stage5_temporal('decode');"
matlab -batch "stage5_temporal('evaluate');"
```

The encoding stage verifies that all-off outputs match existing baseline files byte for byte, then generates combined temporal, post-only, and pre-echo-only modes. All modes use the same rates, quantizer, allocator, and binary format. Decoding in the separate process reads `.lac` files only. The evaluation stage produces measurements and an input/baseline/temporal masking plot with corresponding band allocations. Speech remains held out.

See [docs/TEMPORAL_MASKING.md](docs/TEMPORAL_MASKING.md) for the hypothesis, equations, state handling, parameter choices, and measured benefits/regressions. Initial measured gains mainly come from pre-echo control at 64/96 kb/s on castanets; listening is pending.

## Outputs

| Location | Contents |
| --- | --- |
| `outputs/prepared/` | Prepared samples, float WAVs, source/preparation manifest |
| `outputs/validation/` | Transform results, synthetic codec fixtures and verification results |
| `outputs/baseline/` | Compressed `.lac`, reconstructed WAVs, per-file statistics/configuration, allocation diagnostics, measurement CSV/JSON, masking plot |
| `outputs/temporal/` | Baseline byte-regression checks, three temporal configurations, matched-rate measurements, onset records, and comparison plot |

Reconstructed WAVs use 32-bit IEEE float samples. This preserves playback levels and overshoots without clipping or normalizing them; the 768 kb/s compression reference is still **48 kHz mono 16-bit PCM**. The WAV writer's output is checked against MATLAB `audioread`.

## How the baseline works

The PAM estimates masking directly from MDCT-domain band energies. It combines a threshold-in-quiet curve, a conservative 29 dB masking offset, and fixed asymmetric spreading (+30/−15 dB per Bark). It sums normalized threshold energies into band allowances. Its equations and assumptions are in [docs/BASELINE.md](docs/BASELINE.md).

The allocator considers omitting a band or quantizing it with 2–15 bits per coefficient and a stored step size. It greedily buys the greatest reduction of threshold-normalized squared error per extra bit. The byte schedule includes the global header, all band metadata, and frame padding. There is no bit reservoir or entropy coding. The bitstream format is fully described in [docs/BITSTREAM.md](docs/BITSTREAM.md).

For a 10-second input the complete files are exactly 80,000, 120,000, and 160,000 bytes at 64, 96, and 128 kb/s. Other durations are rounded down to whole bytes. Unused frame capacity is explicit zero padding and separately reported. Extremely short clips cannot fit the mandatory metadata at low rates and produce an explanatory error; the unquantized transform itself supports any positive input length.

## Validation and limitations

- 55 unquantized transform cases: silence, noise, tones, first/last impulses, lengths from 1 to 480,000 samples; maximum absolute reconstruction error approximately `3.41e-13`.
- Exact packing recovery across all 15 supported width modes (zero plus 2–15 bits), with signed extrema.
- Nine synthetic full-file round trips across all required rates, matching encoder-side quantized reconstruction exactly.
- Complete byte accounting, exact output length, float-WAV fidelity, silent PAM behavior, masking spread, unsupported-feature rejection, and malformed-file checks.
- Six development outputs decoded in a separate MATLAB process using only compressed input files.

See [docs/BASELINE_RESULTS.md](docs/BASELINE_RESULTS.md) for measured development results. Listening observations have **not** been collected. SNR is not a perceptual quality score. Fixed long windows, broad quantization bands, uniform scalar quantization, direct bit packing, and a simplified PAM can cause substantial distortion, especially on transients. Improvements and final held-out evaluation remain future stages.

Project decisions and development instructions are in [AGENTS.md](AGENTS.md).
