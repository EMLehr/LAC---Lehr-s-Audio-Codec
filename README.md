# LAC — Lehr's Audio Codec

A MATLAB educational perceptual audio codec with a reproducible baseline and an architecture for independently selectable improvements. This is a custom AAC-style codec, **not a standards-compliant AAC or MP3 encoder**. `.lac` files need this project's decoder.

The baseline implements 48 kHz mono input, 2048-sample sine-window MDCT analysis, 1024 coefficients and a 1024-sample hop, a baseline psychoacoustic model (PAM), band-dependent scalar quantization, complete-file rate control, direct bit packing, and standalone decoding.

## Current status

Baseline stages 1–4 are implemented. Transform and bitstream tests run in MATLAB R2025b Update 1. Development outputs exist locally for harpsichord and castanets at 64, 96, and 128 kb/s. Speech is reserved for final quality testing after choosing PAM changes.

The original six optional features default to **off** and are independently selectable: four PAM options (tonal/noise classification, temporal masking, enhanced spreading, enhanced band-allowance mapping), Huffman coding, and SBR-inspired bandwidth extension. Five additional codec experiments and the piecewise/bucket allocation controls also default off. Temporal masking has separately controllable post-masking and pre-echo control. No improvement is silently included in the baseline.

## Requirements

### Settings for the assignment's PAM-only investigation

Use **fixed bitrate at 64, 96, or 128 kb/s**, 48 kHz mono, and the default **2048-sample MDCT window / 1024 coefficients / 1024-sample hop**. Compare the all-off baseline against one justified PAM change, holding every non-PAM setting fixed. Combinations of PAM changes are supplementary unless the report clearly isolates its focused hypothesis.

| Toggle or setting | Use in the required PAM-only comparison? | Reason |
| --- | --- | --- |
| Tonal vs noise maskers | **Yes** | Changes masker strength in the PAM |
| Temporal masking: post-masking / pre-echo controls | **Yes** | Changes PAM distortion allowances; keeps the original quantizer and allocator |
| Adaptive spreading | **Yes** | Changes the PAM's frequency spreading |
| Enhanced band mapping | **Yes** | Changes masking-curve to band-allowance mapping |
| CBR, 64 / 96 / 128 kb/s | **Required** | Matched actual file rates; unchanged baseline rate-control algorithm |
| Original MDCT dimensions | **Required** | Assignment explicitly fixes transform/window/hop sizes |
| VBR and its quality presets | **No; supplementary** | Changes rate control and does not match fixed target rates |
| Piecewise bit saving and its NMR/ratio controls | **No; supplementary** | Changes allocation policy |
| Bit bucket, capacity, and saving target | **No; supplementary** | Changes cross-frame allocation and framing |
| Fixed Huffman, per-file/per-window books, zero-run coding | **No; supplementary** | Changes entropy coding and its allocation costs |
| Smarter quantizer and step search radius | **No; supplementary** | Changes quantizer candidate selection |
| Perceptual entropy, PE boost, attack protection | **No; supplementary** | This implementation adds detection/allocation behavior, beyond the four PAM-only options |
| Variable MDCT windows and attack ratio | **No; experimental** | Short transforms violate the required fixed dimensions when enabled |
| Bandwidth extension | **No; supplementary** | Replaces directly coded high-band detail with parametric reconstruction |

Start with `cfg = codec_config()` and enable only the chosen fields among `cfg.features.tonalMaskers`, `temporalMasking`, `enhancedSpreading`, and `enhancedBandMapping`. Leave `features.huffman`, `features.bandwidthExtension`, `allocation.enabled`, `reservoir.enabled`, and **all five `cfg.experiments` switches false**. Leave `rateMode='cbr'` and set `targetKbps` to the required rate. Dormant numeric controls have no effect while their feature is off. Playback volume, seek/loop, and notes do not change encoding and may be used freely.

The baseline necessarily includes its original bit allocator, scalar quantizer, direct binary packing, frequency spreading, and band mapping. "PAM-only" means keeping those components unchanged between the baseline and improved PAM. The entropy/allocator experiments are not substitutes for the required PAM comparison, even if they improve quality or size.

### Environment

- MATLAB; verified with R2025b Update 1 on Windows.
- Signal Processing Toolbox for `resample` during input preparation.
- The encoder/decoder and transform use base MATLAB. Audio Toolbox is not required.
- Original test WAVs in the project root. References, originals, and generated artifacts are excluded from Git.

## Listen and compare

Run `listening_gui` in MATLAB to open the A/B listening window. Each side can be the prepared original or any codec configuration, with independent bitrate and feature controls. It supports all 64 six-switch combinations, plus temporal component variants. Missing versions are generated on demand and cached.

Switch A/B at the same playback position, seek, loop a chosen region, adjust shared volume, and save listening notes with the exact configurations. Speech is labelled as the final-test excerpt and is only loaded when requested. See [docs/LISTENING_GUI.md](docs/LISTENING_GUI.md) for operation, playback levels, testing, and the local MATLAB audio-driver shutdown limitation.

Each encoded side also offers **Fixed bitrate / Variable bitrate**. VBR selects a quality target instead of a bitrate; the GUI shows the resulting actual bitrate and percentage size reduction. See [docs/VARIABLE_BITRATE.md](docs/VARIABLE_BITRATE.md) for its interpretation, results, and reproduction commands. Fixed bitrate remains the default for the assignment.

VBR presets now include **+9 and +12 dB**. The **Piecewise saving / bit bucket...** button opens three editable NMR boundaries and **x in y bits saved** ratios, including the lowest layer. Piecewise allocation works with either rate mode. The optional capped bit bucket carries unused fixed-rate capacity to later frames. Both options default off; see [docs/PIECEWISE_ALLOCATION.md](docs/PIECEWISE_ALLOCATION.md) for controls, accounting, experiments, and limitations.

## Five additional codec experiments

Open **Codec experiments (5 options)...** on an encoded side in `listening_gui`. Each option is independent and defaults off:

1. **Zero-run coding:** exact representation of quantized zero runs, with direct/Huffman fallbacks.
2. **Per-file Huffman:** a learned category book stored in the file, with automatic fixed-book fallback. The book-selection setting optionally tests **per-window books** too; each local book must save complete payload bytes after its metadata.
3. **Smarter quantizer search:** multiple step sizes at each width, including controlled clipping candidates and the original choice.
4. **Perceptual entropy:** PE-informed precision and attack protection in either window mode; also contributes to window switching when enabled.
5. **Variable MDCT windows:** long/start/eight-short/stop sequences, using eight 256-sample transforms around detected attacks. This is experimental and outside the assignment's fixed dimensions. With PE off, switching uses energy detection alone.

The decoder reads version 5 for these experiments; versions 1–4 remain supported. All new toggles off uses the original encoding path. See [docs/CODEC_EXPERIMENTS.md](docs/CODEC_EXPERIMENTS.md) for algorithms, overhead checks, settings, validation, and measured limitations.

```text
matlab -batch "stage12_verify_experiments;"
matlab -batch "stage12_experiments('encode');"
matlab -batch "stage12_experiments('decode');"
matlab -batch "stage12_experiments('evaluate');"
matlab -batch "stage12_verify_gui;"
```

## Prepare the source audio

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

## Tonal/noise comparison stage

Set `cfg.features.tonalMaskers = true` to enable spectral-flatness-based masker classification. It can run alone or with `cfg.features.temporalMasking = true`. The decoder is unchanged. The defaults remain all-off.

After stage 4 and stage 5 development encoding, run separate processes:

```text
matlab -batch "stage6_verify_tonality;"
matlab -batch "stage6_tonality('encode');"
matlab -batch "stage6_tonality('decode');"
matlab -batch "stage6_tonality('evaluate');"
```

This generates baseline, temporal-only, tonal-only, and combined configurations at all three rates for both development clips. It checks twelve existing baseline/temporal bitstreams for byte-identical output. Results are mixed, including pre-onset error regressions; see [docs/TONAL_MASKERS.md](docs/TONAL_MASKERS.md) for assumptions, measurements, and limitations. Speech remains held out.

## Final PAM options and combined experiments

The remaining two PAM options are enabled independently:

```matlab
cfg = codec_config();
cfg.features.enhancedSpreading = true;
cfg.features.enhancedBandMapping = true;
```

Enhanced spreading uses source frequency and level to control the upward masking slope. Enhanced mapping uses a harmonic mean of bin thresholds to protect low-threshold regions within a band. Either can be combined with tonal classification and temporal masking; setting all four flags false restores the original baseline.

After stage 6 encoding, run:

```text
matlab -batch "stage7_verify_pam;"
matlab -batch "stage7_pam_options('encode');"
matlab -batch "stage7_pam_options('decode');"
matlab -batch "stage7_pam_options('evaluate');"
```

Stage 7 produces all 16 PAM combinations for both development excerpts at all three rates: 96 encoded/decoded pairs. It verifies 24 earlier configurations byte for byte. Synthetic checks cover all combinations, state continuity, mapping bounds, spreading behavior, and 48 exact codec round trips. The decoder and file format are unchanged.

See [docs/FINAL_PAM_OPTIONS.md](docs/FINAL_PAM_OPTIONS.md) for equations, assumptions, results, and instructions. Mapping improves overall SNR substantially on harpsichord, but some configurations increase pre-onset error on castanets. All-on is not automatically best. The listening GUI is available; human observations and final speech evaluation remain pending.

## Optional Huffman coding and bandwidth extension

```matlab
cfg = codec_config();
cfg.features.huffman = true;
cfg.features.bandwidthExtension = true;
```

Either switch works alone or with any PAM configuration. Huffman coding losslessly stores quantized coefficient symbols using a fixed canonical category codebook and a per-band direct-packing fallback. Its exact bit costs enter allocation, so saved bits can buy precision within the fixed file budget. It does not make the entire audio codec lossless, and fixed-rate output files keep the same total size.

Bandwidth extension directly codes the lower 12 kHz, then reconstructs the upper half from mirrored decoded coefficients with transmitted energy envelopes and noise fractions. This is a lossy SBR-inspired experiment, not standards-compliant SBR. The required 2048/1024 MDCT dimensions and 48 kHz output are preserved.

Both options use explicit flags in version-2 `.lac` files under the original fixed-rate allocator. The decoder detects all five supported format versions. With both coding switches and all allocation/experiment controls off in fixed-rate mode, the encoder still produces byte-identical version-1 output.

After stage 7 encoding:

```text
matlab -batch "stage8_verify_coding;"
matlab -batch "stage8_coding_features('encode');"
matlab -batch "stage8_coding_features('decode');"
matlab -batch "stage8_coding_features('evaluate');"
```

Stage 8 compares neither tool, Huffman only, BWE only, and both, with baseline PAM and all-four PAM settings in separate groups. This creates 48 development encoded/decoded pairs. Synthetic checks exercise all 64 combinations of the six switches. See [docs/CODING_FEATURES.md](docs/CODING_FEATURES.md) for design, measurements, and limitations, and [docs/BITSTREAM.md](docs/BITSTREAM.md) for decoding semantics. Speech and listening remain reserved for the final stage.

## Outputs

| Location | Contents |
| --- | --- |
| `outputs/prepared/` | Prepared samples, float WAVs, source/preparation manifest |
| `outputs/validation/` | Transform results, synthetic codec fixtures and verification results |
| `outputs/baseline/` | Compressed `.lac`, reconstructed WAVs, per-file statistics/configuration, allocation diagnostics, measurement CSV/JSON, masking plot |
| `outputs/temporal/` | Baseline byte-regression checks, three temporal configurations, matched-rate measurements, onset records, and comparison plot |
| `outputs/tonality/` | Four model combinations, regression checks, measurements, classifier scores, and masking/allocation plot |
| `outputs/pam_options/` | All 16 PAM combinations, 96 encoded/decoded pairs, regression checks, measurements, and global-curve/band-allowance/allocation plot |
| `outputs/coding_features/` | Separate baseline-PAM/all-PAM comparisons of Huffman and BWE, 48 encoded/decoded pairs, byte regressions, measurements, and reconstructed-spectrum plot |
| `outputs/listening/` | On-demand encoded/decoded comparison cache, saved listening notes, GUI verification, and preview |
| `outputs/vbr/` | Quality-target VBR comparisons, actual compression percentages, reconstructed WAVs, target diagnostics, and frame-rate plot |
| `outputs/allocation/` | Piecewise/bucket comparisons, fresh-process decoded WAVs, measurements, and bucket-balance plot |
| `outputs/experiments/` | Five-option development comparisons, learned-book decisions, window modes, PE diagnostics, and reconstructed WAVs |

Reconstructed WAVs use 32-bit IEEE float samples. This preserves playback levels and overshoots without clipping or normalizing them; the 768 kb/s compression reference is still **48 kHz mono 16-bit PCM**. The WAV writer's output is checked against MATLAB `audioread`.

## How the baseline works

The PAM estimates masking directly from MDCT-domain band energies. It combines a threshold-in-quiet curve, a conservative 29 dB masking offset, and fixed asymmetric spreading (+30/−15 dB per Bark). It sums normalized threshold energies into band allowances. Its equations and assumptions are in [docs/BASELINE.md](docs/BASELINE.md).

The allocator considers omitting a band or quantizing it with 2–15 bits per coefficient and a stored step size. It greedily buys the greatest reduction of threshold-normalized squared error per extra bit. The byte schedule includes the global header, all band metadata, and frame padding. There is no bit reservoir or entropy coding. The bitstream format is fully described in [docs/BITSTREAM.md](docs/BITSTREAM.md).

In fixed-bitrate mode, a 10-second input produces complete files of exactly 80,000, 120,000, and 160,000 bytes at 64, 96, and 128 kb/s. Other durations are rounded down to whole bytes. Unused frame capacity is explicit zero padding and separately reported. Extremely short clips cannot fit the mandatory metadata at low fixed rates and produce an explanatory error; the unquantized transform itself supports any positive input length. Optional quality-target VBR instead writes minimally padded variable-size frames and reports the resulting bitrate.

## Validation and limitations

- 55 unquantized transform cases: silence, noise, tones, first/last impulses, lengths from 1 to 480,000 samples; maximum absolute reconstruction error approximately `3.41e-13`.
- Exact packing recovery across all 15 supported width modes (zero plus 2–15 bits), with signed extrema.
- Nine synthetic full-file round trips across all required rates, matching encoder-side quantized reconstruction exactly.
- Complete byte accounting, exact output length, float-WAV fidelity, silent PAM behavior, masking spread, unsupported-feature rejection, and malformed-file checks.
- Six development outputs decoded in a separate MATLAB process using only compressed input files.

See [docs/BASELINE_RESULTS.md](docs/BASELINE_RESULTS.md) for measured baseline results and the feature documents above for optional configurations. Listening observations have **not** been collected. SNR is not a perceptual quality score. Fixed long windows, broad quantization bands, uniform scalar quantization, and a simplified PAM can cause substantial distortion, especially on transients. Bandwidth extension additionally changes high-frequency fine structure. Listening and final held-out evaluation remain future stages.

Implementation details and experiment records are in the `docs/` directory.
