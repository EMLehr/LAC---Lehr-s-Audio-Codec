# Optional Huffman coding and bandwidth extension

Stage 8 implements the two approved non-PAM features. They default off and can be used separately, together, or with any of the four PAM switches. Both use the existing 48 kHz mono, 2048-sample window, 1024-coefficient MDCT, and 1024-sample hop. Neither changes the source preparation or playback normalization.

## Running the features

```matlab
cfg = codec_config();
cfg.features.huffman = true;
cfg.features.bandwidthExtension = true;
cfg.targetKbps = 96;
encode_audio('outputs/prepared/harpsichord.mat','outputs/example.lac',cfg);
```

In a fresh MATLAB process, run:

```matlab
decode_audio('outputs/example.lac','outputs/example_decoded.wav');
```

The decoder reads the options from the compressed file. No configuration, original audio, encoder workspace, random-number state, or sidecar is needed. The new decoder reads both version-1 and version-2 files. Both coding switches off still produce the same version-1 bytes as before. Version 2 carries Huffman/BWE flags and all reconstruction parameters. Its fixed Huffman book is part of the versioned decoder specification, not an external dictionary. See [BITSTREAM.md](BITSTREAM.md) for exact syntax and reconstruction rules.

After preparing the development excerpts and running stage 7 encoding:

```text
matlab -batch "lac_setup; stage8_verify_coding;"
matlab -batch "lac_setup; stage8_coding_features('encode');"
matlab -batch "lac_setup; stage8_coding_features('decode');"
matlab -batch "lac_setup; stage8_coding_features('evaluate');"
```

These actions are independently runnable. The comparison produces 48 encoded/decoded pairs in `outputs/coding_features/`, divided into `baseline_pam/` and `all_pam/`. Within each group, only the two coding switches vary. Each group covers neither, Huffman, BWE, and both at 64/96/128 kb/s for harpsichord and castanets. Speech remains held out. Full measurements, regression records, and decoding records are saved per group. `coding_comparison.png` shows original and reanalyzed decoded spectra for harpsichord frame 95 at 96 kb/s, with the 12 kHz boundary marked. The [listening GUI](LISTENING_GUI.md) can now audition these configurations and generate additional combinations on demand.

## Huffman coding

The quantized MDCT integers, rather than source samples, are entropy-coded. A fixed canonical Huffman book represents magnitude categories 0 through 15. Zero has a one-bit code; nonzero symbols carry a category code, sign bit, and remaining magnitude bits. The book is generated with Huffman's merging algorithm from explicit integer design weights, with deterministic tie-breaking and canonical assignment. It is not trained on either development audio or speech.

Each active band has a one-bit selector. The encoder chooses Huffman only if its coefficient payload is shorter than direct signed packing. Both alternatives include the selector overhead. The eight-bit quantizer step and four-bit band width remain explicit. Width-zero bands carry neither step nor selector.

For every candidate quantizer, the allocator counts the actual category codes and suffix bits. It can use savings to purchase finer precision. Variable-length costs need not rise monotonically with precision, so free or cost-reducing distortion improvements are considered before positive-cost upgrades. Quantizer candidates and PAM allowances are unchanged. The original allocator path remains unchanged with Huffman off.

Huffman packing itself is lossless: a fixed integer/step sequence reconstructs identically. A full encode with Huffman enabled can choose different quantizers because its bit costs differ. Thus its audio can differ from direct packing, and improvements in a PAM-weighted objective need not improve unweighted SNR or every transient region.

The fixed-rate file size does not shrink. `entropySavingsBits` reports the difference between direct packing of the **selected** quantized symbols and the actual entropy-coded representation, including selector overhead. It is not a file-size saving and is not the saving relative to the baseline's different quantization. Saved capacity may buy precision or remain padding. The baseline-PAM Huffman-only runs saved 215,324 / 249,914 / 245,765 bits on harpsichord and 19,604 / 18,254 / 11,953 bits on castanets at 64 / 96 / 128 kb/s by this measure. Some individual bands/frames can incur selector overhead without a payload saving; aggregate savings are reported honestly.

## SBR-inspired bandwidth extension

The motivating idea is parametric high-frequency reconstruction from lower-frequency content and compact envelope information, as reviewed in [Herre and Dick, section 4.1](https://www.mdpi.com/2076-3417/9/14/2854). This implementation is a simplified MDCT-domain experiment, not standardized SBR or HE-AAC. It uses spectral mirroring rather than a commercial SBR filterbank and transposition system.

The version-2 design fixes the boundary at 12 kHz so the 512 lower coefficients can supply a template for the 512 upper coefficients while preserving the required full-size MDCT. The existing auditory band crossing this boundary is split, increasing the band count from 25 to 26. PAM settings are held fixed, but this necessary band-boundary change also affects the adjacent band's analysis/allocation. The boundary is a design choice made before these comparisons, not an experimentally selected optimum or a runtime parameter.

The encoder directly quantizes only coefficients 1:512. For each of four 128-coefficient high-frequency groups it transmits:

- An eight-bit logarithmic RMS envelope: `e = round(20*log10(RMS)) + 160`. Nonpositive codes become silence; codes above 255 raise a range error. Reconstructed nonzero RMS is `10^((e-160)/20)`, giving at most 0.5 dB envelope rounding error within range.
- A two-bit noise fraction: `round(3*flatness)`, clipped to 0:3, with geometric/arithmetic mean power flatness and a relative `1e-12` logarithm floor. This is BWE shaping information, independent of the tonal-masker PAM switch.

The decoder reverses the decoded low-frequency coefficients into the upper half, normalizes each group's template, mixes deterministic noise according to the transmitted fraction, and scales to the envelope. Empty templates fall back to deterministic noise; zero envelopes remain zero. The generator uses the frame/group indices and fixed integer arithmetic, never MATLAB's global random state. All high-band widths must be zero, preventing ambiguous direct-plus-parametric reconstruction.

The four envelope/noise pairs cost 40 bits per frame, including silent frames: 18,800 bits over a ten-second, 470-frame input. The additional band boundary also adds header and width metadata. All of this is reserved before allocating core coefficients and counted in actual bitrate. Low-frequency quantization can benefit from omitting direct high-frequency symbols, but the reconstructed high-frequency phase, pitch structure, and transient timing are approximate. Long windows, framewise envelopes, broad shaping groups, and reflected frequency structure can produce artifacts. We do not automatically disable BWE when it performs poorly, because the explicit toggle should run a reproducible experiment.

## Verification

Verified in MATLAB R2025b Update 1:

- Exact signed-symbol/scale recovery at all widths 2 through 15, including zeros and signed extrema. Tests exercise 351 Huffman band cases and 349 direct fallback cases.
- A fixed codebook fixture and independently specified three-byte golden stream guard against encoder/decoder agreeing on an unintended syntax.
- Exact cost/packing agreement, complete header/side/payload/padding accounting, and malformed-prefix/range/padding checks.
- BWE envelope accuracy, correct mirroring when the noise fraction is zero, preserved core coefficients, deterministic empty-core fallback, and no global RNG changes.
- All 64 combinations of the six toggles: 80 exact full-codec round trips, including all combinations at 96 kb/s and baseline/all-four PAM configurations at 64 and 128 kb/s. Decoding matches encoder-side quantization and BWE reconstruction exactly.
- Additional full-file silence and high-frequency-only inputs across all three optional coding modes, including arbitrary input lengths.
- Rejection of truncated files, invalid version/flag combinations, missing BWE boundaries, and nonzero padding.
- Existing codec, temporal, tonality, and final-PAM test suites pass.
- Twelve previous PAM-only development files remain byte-identical. All 48 development files decode in a fresh MATLAB process with correct lengths and rates.
- MATLAB Code Analyzer reports zero messages across the project MATLAB sources.

## Measured development results

Every ten-second file is exactly 80,000 / 120,000 / 160,000 bytes at 64 / 96 / 128 kb/s, including all overhead and padding. Compression ratios against 768 kb/s mono 16-bit PCM are 12:1 / 8:1 / 6:1. Reconstructed WAVs preserve levels without normalization or clipping.

The tables report **SNR changes in dB relative to the no-coding-tool configuration with the same PAM settings**. These are waveform metrics, not listening scores.

| PAM | Source | kb/s | Huffman | BWE | Both |
| --- | --- | ---: | ---: | ---: | ---: |
| Baseline | Harpsichord | 64 | +0.709 | -0.951 | -0.371 |
| Baseline | Harpsichord | 96 | +0.267 | -1.136 | -0.873 |
| Baseline | Harpsichord | 128 | +0.487 | -1.169 | -1.037 |
| Baseline | Castanets | 64 | +0.039 | -1.498 | -1.256 |
| Baseline | Castanets | 96 | +0.095 | -2.037 | -2.005 |
| Baseline | Castanets | 128 | -0.003 | -2.213 | -2.220 |
| All four | Harpsichord | 64 | +2.017 | -1.646 | -0.500 |
| All four | Harpsichord | 96 | +2.573 | -2.361 | -1.667 |
| All four | Harpsichord | 128 | +2.056 | -3.630 | -3.500 |
| All four | Castanets | 64 | +0.323 | -1.582 | -1.139 |
| All four | Castanets | 96 | +0.027 | -2.179 | -2.107 |
| All four | Castanets | 128 | +0.112 | -2.806 | -2.810 |

Huffman saves useful coefficient capacity and generally improves overall SNR here, especially on harpsichord with all PAM options. It still has a small baseline-PAM castanet SNR regression at 128 kb/s, and some pre-onset windows get worse. For example, all-PAM castanets at 128 kb/s gain 0.112 dB overall SNR with Huffman but have 1.199 dB higher pre-onset error.

BWE lowers overall SNR in every tested condition and raises pre-onset error. At 128 kb/s with baseline PAM, BWE-only castanet pre-onset error rises 9.330 dB; with all PAM options, BWE-only harpsichord pre-onset error rises 10.896 dB. The latter metric covers just one detected harpsichord onset; castanets has 31. These regressions remain in the recorded results, rather than tuning them away after seeing the evaluation. Parametric high-frequency synthesis is not waveform-preserving, but these measurements do not establish perceptual benefit either.

Each group's `measurements.csv/json` contains absolute SNR, segmental SNR, RMSE, pre/post-onset errors, actual sizes/rates, padding, entropy savings, and allocation differences. `changedBandWidths` is undefined across a band-layout change; `changedCoefficientWidths` expands widths onto the common 1024-bin grid for that comparison. Listening remains explicitly marked not assessed. Speech has not been used to select or tune these changes. BWE should remain an experimental toggle pending listening, and neither tool changes the separately controlled PAM investigation.
