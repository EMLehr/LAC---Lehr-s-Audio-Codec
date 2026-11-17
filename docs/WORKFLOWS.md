# Workflows and source organization

## MATLAB paths

From the project root, run `lac_setup` once per MATLAB session before calling the API, a stage, or a test. `listening_gui` does this automatically. Setup adds the root, `src/`, `stages/`, and `tests/` to the current session only; it does not modify MATLAB's saved path. Do not add `src/+pac` directly: MATLAB finds that package through `src/`.

The stage/test function names are unchanged after moving them into folders. Every fresh shell process needs setup, for example:

```text
matlab -batch "lac_setup; stage2_verify_transform;"
```

`pac.project_root()` resolves the project from its source location, so stage outputs still go to the root's `outputs/` even after changing MATLAB's current folder. Shell commands below assume they start in the project root. MATLAB examples in the algorithm documents assume `lac_setup` has already run.

## Prepare the audio

Keep these original files in the project root (not committed):

| Excerpt | Original filename |
| --- | --- |
| Harpsichord | `40_harpsichord_arpegio_melodious_phrase_stereo.wav` |
| Castanets | `27_castanets_single_tone_rhythm_stereo.wav` |
| English female speech | `49_female_speech_english_mono.wav` |

Download them from the [QOA SQAM collection](https://qoaformat.org/samples/) and follow the [EBU collection's usage terms](https://qc.ebu.io/testmaterials/523/) for testing and evaluation. The supplied files are 44.1 kHz stereo, including speech despite its filename.

```text
matlab -batch "lac_setup; stage1_prepare_inputs;"
```

Preparation selects the first ten seconds, averages channels, and resamples to 48 kHz using Signal Processing Toolbox without normalizing levels. `outputs/prepared/*.mat` contains authoritative double samples; float WAVs are playback copies. A manifest records the source metadata and preparation. Originals remain untouched. Speech is held out for final testing after selecting the PAM investigation; preparation alone does not evaluate it.

## Independently runnable stages

The functions are grouped by purpose, with their original stage numbers preserved:

| Stage | Function(s) | Purpose |
| --- | --- | --- |
| 1 | `stage1_prepare_inputs` | Prepare common inputs |
| 2 | `stage2_verify_transform` | Unquantized reconstruction |
| 3 | `stage3_verify_codec` | Packing and codec mechanics |
| 4 | `stage4_encode_baseline`, `stage4_decode_baseline`, `stage4_evaluate_baseline` | Baseline files and results |
| 5 | `stage5_temporal`, `stage5_verify_temporal` | Temporal masking |
| 6 | `stage6_tonality`, `stage6_verify_tonality` | Tonal/noise masking |
| 7 | `stage7_pam_options`, `stage7_verify_pam` | All four PAM options |
| 8 | `stage8_coding_features`, `stage8_verify_coding` | Fixed Huffman and BWE |
| 9 | `stage9_verify_listening` | GUI behavior and optional transport checks |
| 10 | `stage10_vbr`, `stage10_verify_vbr`, `stage10_verify_vbr_gui` | VBR |
| 11 | `stage11_allocation`, `stage11_verify_allocation`, `stage11_verify_gui` | Piecewise allocation and bucket |
| 12 | `stage12_experiments`, `stage12_verify_experiments`, `stage12_verify_gui` | Five additional codec experiments |

All `verify` functions are in `tests/`; preparation and encode/decode/evaluation workflows are in `stages/`. Later regression tests may require earlier generated fixtures; each feature document specifies its prerequisites. Stages consume files, not variables left in the base workspace.

Build the baseline with separate encoder/decoder processes:

```text
matlab -batch "lac_setup; stage2_verify_transform; stage3_verify_codec;"
matlab -batch "lac_setup; stage4_encode_baseline;"
matlab -batch "lac_setup; stage4_decode_baseline;"
matlab -batch "lac_setup; stage4_evaluate_baseline;"
```

Stages 5–8 and 10–12 accept `'encode'`, `'decode'`, or `'evaluate'`. For example:

```text
matlab -batch "lac_setup; stage12_verify_experiments;"
matlab -batch "lac_setup; stage12_experiments('encode');"
matlab -batch "lac_setup; stage12_experiments('decode');"
matlab -batch "lac_setup; stage12_experiments('evaluate');"
matlab -batch "lac_setup; stage12_verify_gui;"
```

After freezing PAM choices, `stage4_encode_baseline(true)` and `stage4_evaluate_baseline(true)` include speech. Decode as usual. Do not use held-out results to tune the model.

## Outputs and measurements

Each experiment has its own directory under `outputs/`: `baseline`, `temporal`, `tonality`, `pam_options`, `coding_features`, `vbr`, `allocation`, or `experiments`. Each contains `.lac` binaries, decoded WAVs, configuration/statistics JSON, allocation diagnostics, and measurements where applicable. `validation/` holds test fixtures; `listening/` holds the on-demand cache, previews, and saved notes.

Decoded WAVs use 32-bit float to preserve levels and overshoots. Compression measurements use the assignment's **48 kHz mono 16-bit PCM reference: 768 kb/s**. Actual bitrate counts all binary headers, side information, and padding over the original duration. Optional JSON/MAT experiment records are not decoder dependencies. Listening playback uses a common gain for both sides and does not change encoded files.

## Implementation locations

- `src/codec_config.m`: central defaults and settings.
- `src/encode_audio.m`, `src/decode_audio.m`: public API and format dispatch.
- `src/+pac/`: shared MATLAB package for transform, PAM, allocation, coding, I/O, and GUI implementation.
- Root `listening_gui.m`: small launch entry point.
- Root `lac_setup.m`: session path setup.

The listening cache fingerprints codec sources in `src/`, plus input/configuration. GUI-only changes and project-location helpers are excluded. Reference documents, original audio, generated files, and local agent instructions remain excluded from Git.
