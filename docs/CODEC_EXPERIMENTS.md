# Optional coding, quantizer, PE, and window experiments

These five additions default off under `cfg.experiments`. They are supplementary experiments, **not part of the assignment's PAM-only comparison**. The README identifies the four PAM switches and exact settings to use for that comparison. The original path and versions 1–4 remain active when every new switch is false. Any new switch uses version 5; decoding never needs the encoder configuration, original audio, or diagnostic sidecars.

## Configuration and GUI

```matlab
cfg = codec_config();
cfg.experiments.zeroRun = true;
cfg.experiments.fileHuffman = true;
cfg.experiments.huffmanScope = 'window'; % 'file' or 'window'
cfg.experiments.smartQuantizer = true;
cfg.experiments.perceptualEntropy = true;
cfg.experiments.variableWindows = true;
encode_audio('outputs/prepared/castanets.mat','outputs/experiment.lac',cfg);
```

Each flag can be enabled alone or in combination. The GUI exposes them in **Codec experiments (5 options)...** for each encoded side. It also exposes the settings below, preserves independent A/B configurations, includes settings in saved notes/cache keys, and labels variable windows as experimental.

| Setting | Default | Meaning |
| --- | ---: | --- |
| `huffmanScope` | `'file'` | Test a learned file book; `'window'` additionally tests local books |
| `stepRadius` | 3 | Search stored step codes from c−3 through c+3, retaining c |
| `peStrengthDB` | 3 | Maximum PE-dependent tightening of band allowances |
| `attackProtectionDB` | 6 | Additional tightening for frames overlapping detected attacks |
| `attackRatio` | 8 | Short-interval energy increase threshold, before PE adjustment |

The book and step controls are coding/quantizer settings; the final three detection/precision settings are not calibrated psychoacoustic constants. They are declared experimental defaults, not tuned against held-out speech. No subjective quality benefit is assumed.

## Zero-run coding

Version 5 tests direct packing, ordinary category Huffman coding when enabled, and zero-run coding when enabled. Each active band stores a two-bit selector if either entropy option is available. Selection includes that overhead; ties prefer direct packing, then ordinary Huffman.

In zero-run mode a zero token stores one flag bit and `ceil(log2(bandCoefficientCount))` bits for run length minus one. A nonzero token stores the opposite flag plus the original signed integer (direct packing), or its Huffman category/sign/magnitude suffix when a book is active. Runs cannot cross band boundaries. Entirely omitted bands still use width zero and need no coefficient tokens. Sign separation is retained; nonzero Huffman symbols have exactly one raw sign bit.

This is lossless with respect to the selected quantized integers. Reintegrating cheaper costs into allocation may select different integers, so enabling the whole feature is not a promise of sample-identical output. The symbol tests separately require exact recovery.

## File and window Huffman books, including size safeguards

The category alphabet remains 0 through 15. A preliminary allocation using the existing fixed book counts the selected quantized categories. Huffman tree construction uses a pseudocount of one for absent symbols, ties by creation order, and canonical codes sorted by length then category. Sixteen one-byte code lengths fully describe a learned book; no external dictionary is required.

The encoder computes complete alternative plans using the fixed and learned file book. For VBR, it selects the learned plan only if the **entire file** is strictly smaller, counting its sixteen book bytes, framing, selectors, and alignment. For CBR, total bytes already tie; it selects the learned plan only if total size does not increase and header/framing plus minimally padded payload bytes decrease. Otherwise it uses the fixed book. The comparison is between version-5 plans, not a guarantee against every older container version. File learning is a bounded two-pass heuristic, not an iterative global optimum. Different plans can choose different quantizers at the same model-relative targets.

With scope `'window'`, each 1024-sample-hop frame additionally builds a local book from its already selected symbols. The encoder repacks those **same symbols** both ways. A local book replaces the inherited fixed/file book only if the complete byte-aligned payload, **including sixteen book bytes**, becomes strictly smaller. The local-book flag shares the always-present frame mode byte, so there is no hidden selector cost. Local books apply to all eight short transforms when a frame uses short windows; they are not separately repeated eight times. Each next frame returns to the inherited book unless it explicitly stores a local one.

Per-window selection cannot enlarge the tested representation or change its reconstructed samples. The global plan comparison runs with local-book selection included. In CBR, actual savings can feed the bucket or become padding. Diagnostic fields distinguish a learned global book actually used (`fileBookUsed`), local book count, local byte savings, total bytes, and useful bytes before whole-byte padding. The GUI's file-Huffman toggle permits fixed-book fallback even if the older fixed-Huffman checkbox is off; this is the intended independently usable adaptive-book mode.

## Smarter quantizer search

The original encoder tests widths 2–15 plus omission. At each width it chooses the smallest stored step that avoids clipping the band's peak. The new search retains that candidate and tries neighboring logarithmic step codes in both directions (codes remain 0–255). Steps are still `2^((code−128)/4)`; each code changes step size by about 1.5 dB.

Smaller steps can clip large coefficients while representing the rest more accurately. Larger steps may create cheaper symbol distributions. Every candidate is measured using exact band squared error and actual symbol/step/selector costs. Dominated candidates are removed from the rate/distortion frontier. Ordinary VBR chooses the least-cost candidate meeting its scaled allowance; unattainable targets select minimum distortion and are reported. Budget allocation uses normalized error reduction per bit. Piecewise mode walks the next affordable frontier step and charges the configured saved fraction, preserving the existing meaning of `x in y bits saved`.

For a fixed book/representation and the same feasible allowance, adding candidates cannot increase the minimum candidate cost. This property does not promise equal perceived quality, monotonic waveform SNR, or global optimality under greedy fixed-budget allocation. Decoder scalar quantization is unchanged, but version-5 packing/costs differ from older formats; cross-version comparisons include that overhead.

## Perceptual-entropy-informed detection and allocation

This is an explicitly simplified PE proxy, not an implementation of an official MPEG PAM. For band energy E, unmodified selected-PAM allowance A, and coefficient count n:

```text
PE_band = 0.5 * n * max(0, log2(max(E,realmin)/max(A,realmin)))
PE_density = PE_band / n
precisionBoostDB = peStrengthDB * min(1, PE_density/max(1,mean(PE_density)))
effectiveAllowance = A * 10^(-(precisionBoostDB + attackProtectionDB*attackStrength)/10)
```

The proxy relates signal-to-mask demand to precision; it is neither measured Shannon entropy nor a calibrated audibility guarantee. Silence has zero PE. These effective allowances guide ordinary CBR allocation, VBR target selection, and piecewise allocation. With a bucket enabled, a stricter target can spend available saved bytes; there is no borrowing from future frames. PE does not automatically enable the bucket. For plain CBR without a bucket, PE can only redistribute that frame's existing capacity. In VBR it can increase bitrate.

Attack detection measures mean-square energy in chronological 128-sample intervals, compared with the maximum of the preceding two intervals and a `1e-10` floor. An attack requires a ratio at least `attackRatio` and energy at least `1e-9`. Strength is capped at one using `log2(ratio)/log2(attackRatio)`; every overlapping long frame receives protection. The detector uses the input already available to the offline encoder.

When PE is enabled, a rise in long-frame PE density above both 0.5 bits/coefficient and 1.25 times its predecessor halves the attack ratio threshold (with a minimum of two). This contributes to detection and, when variable windows are enabled, switching. With variable windows off, modes remain long while PE still changes effective allowances. With PE off, variable windows use the energy detector alone. PE uses raw PAM allowances before its own tightening, avoiding recursive self-inflation. Short-window PAM allowances use short-transform energies and normalization; PE is recomputed on those bands for allocation.

The pre-echo motivation is established in [the AudioLabs tutorial](https://www.audiolabs-erlangen.de/content/resources/aesCodingTutorial/preecho.html). Block PE and energy-based transient detectors are distinct alternatives discussed in [Transient Detection Methods for Audio Coding](https://aes.org/publications/elibrary/elibrary-page/?id=22285). The particular formulas, thresholds, and combination above are this project's declared adaptation, not values attributed to those sources. PE is supplementary here because it explicitly changes allocation/detection behavior beyond the four original PAM-only options.

## Experimental variable MDCT windows

The long transform remains N=1024 (2048 samples) with a 1024-sample macroframe hop. A short macroframe contains eight N=128 MDCTs (256 samples each), offset by 128 samples, beginning 448 samples into the macroframe. It still contains 1024 coefficients in total, but the individual MDCTs do **not** satisfy the assignment dimensions. Do not submit these as the required fixed-window results.

Four sequence modes are used: long, start, eight-short, stop. The long sine window is unchanged. Start uses the first 1024 samples of the long sine, 448 ones, the falling half of the 256-sample sine, then 448 zeros. Stop is its time reverse. Short transforms each use the full 256-sample sine. The MDCT basis remains `sqrt(2/N)*cos(pi/N*(n+0.5+N/2)*(k+0.5))`.

Attacks select short macroframes covering their location; first/last frames cannot be short because they need transition support. The scheduler fills one-frame gaps between requested short sequences and inserts start/stop windows. Allowed transitions are long→long/start, start→short, short→short/stop, stop→long/start. The padded stream starts long/start and ends long/stop. The decoder validates these rules, performs matching overlap-add, and removes the same 1024 leading samples and trailing padding to return exactly the original length.

Long and short bands use the same one-Bark grouping rule at their respective frequency resolutions. Each short transform has its own widths/steps and allowances; their metadata is included in the macroframe budget. Temporal-PAM history is preserved while resolution stays unchanged and reset when switching between long and short dimensions; this approximation is documented rather than mixing incompatible band histories. BWE, when enabled, splits each transform at 12 kHz and uses four high-band groups, with deterministic per-subtransform seeds. Short-window metadata and BWE parameters can materially increase overhead and harm low-rate performance.

This follows the long/start/eight-short/stop structure described in [Adaptive Window Switching for Audio Coding](https://scl.ece.ucsb.edu/sites/default/files/publications/e08_1_0.pdf), while retaining our own quantizer, PAM, format, and band definitions. It is not AAC compatibility. Switching uses lookahead implicit in the offline analysis and is not advertised as a low-delay streaming implementation.

## Reproduction

Run `lac_setup` in each new MATLAB session, then `stage12_verify_experiments`, followed by `stage12_experiments('encode')`, `'decode'`, and `'evaluate'` in separate processes. See [copyable workflow commands](WORKFLOWS.md). The development stage covers baseline, each new option alone, optional local books, PE+windows, and all five, in CBR96 and VBR0 for harpsichord/castanets; four additional all-on/bucket/piecewise files cover CBR64/128. This is 40 files. Speech remains held out. `stage12_verify_gui` checks the UI and baseline restoration. Generated files and JSON/CSV diagnostics are under `outputs/experiments/`; structural fixtures are under `outputs/validation/experiments/`.

No listening observations are synthesized by tests. Lower byte counts or pre-onset error do not establish a universal perceptual improvement. In particular, tests of VBR settings across different PAM/allocation/window choices are not matched-quality experiments. Use fixed-rate, PAM-only settings from the README for the assignment.

## Verified results

MATLAB R2025b Update 1 checks passed:

- 84 transform cases, including silence, random signals, tones, first/last/interior impulses, arbitrary lengths, and transition sequences. Maximum unquantized reconstruction error: `1.215e-12` (rounded upward).
- 12 exact symbol cases spanning long/short geometry, signed extrema, zero runs, fixed/custom books; explicit malformed canonical-tree and transition rejection.
- 256 codec round trips: all 32 new-switch combinations, all four original Huffman/BWE combinations, and CBR/VBR, with rotating original PAM settings. The 248 cases with new options enabled match encoder-side switched reconstruction exactly; eight all-new-off cases use the legacy path. Bucket/piecewise interactions, tiny silent VBR, invalid framing/flags/padding, and book-overhead guards are covered. This is not an exhaustive cross product of all eleven feature switches.
- Stage 11's 128 existing allocation round trips and sixteen earlier byte regressions pass; stage 3 and stage 8 regression suites also pass, including eighty prior coding-tool round trips.
- All forty development files decode in a fresh process, returning exactly 480,000 samples. No held-out speech is encoded.
- New GUI controls and existing stage 9/10 GUI checks pass; baseline bytes are restored with new controls off. Code Analyzer reports zero messages.

Ordinary VBR at 0 dB, with the baseline PAM and each named option alone:

| Option | Harpsichord kb/s | Castanets kb/s |
| --- | ---: | ---: |
| Original baseline | 94.898 | 114.963 |
| Zero-run coding | 82.454 | 116.368 |
| Per-file Huffman, guarded | 70.357 | 111.992 |
| File + local window books, guarded | 70.118 | 111.992 |
| Smarter quantizer | 93.856 | 112.913 |
| PE | 102.631 | 130.718 |
| Variable windows | 95.670 | 118.163 |
| PE + variable windows | 103.006 | 132.052 |
| All five, local books permitted | 72.070 | 124.013 |

Zero-run overhead hurts castanets at this setting, despite band-level fallbacks. Learned books are not automatically retained: both file-only CBR96 examples fall back to the fixed book. For harpsichord VBR, the local-book mode uses 51 local books and saves 299 bytes versus its inherited global book after counting all local descriptions. The whole selected file is 87,647 bytes versus its version-5 fixed-book reference of 88,189 bytes. Castanets VBR uses the learned file book but rejects every local book. These are real decisions, not assumed savings.

The older version-3 fixed-Huffman harpsichord file was 70.137 kb/s, slightly smaller than the version-5 file-only result despite its learned-book improvement within version 5. The extended mode/header syntax explains why the size guard is explicitly scoped to comparable version-5 plans; it is not a guarantee against every older format or unrelated feature configuration.

At matched CBR96, selected waveform SNR and pre-onset error measurements are:

| Source / option | Waveform SNR (dB) | Pre-onset MSE |
| --- | ---: | ---: |
| Harpsichord baseline | 10.919 | 9.790e-6 |
| Harpsichord smarter quantizer | 11.006 | 9.560e-6 |
| Harpsichord PE | 10.883 | 9.685e-6 |
| Harpsichord variable windows | 10.929 | 2.123e-8 |
| Castanets baseline | 12.776 | 3.183e-5 |
| Castanets smarter quantizer | 13.050 | 2.164e-5 |
| Castanets PE | 12.717 | 3.380e-5 |
| Castanets variable windows | 8.695 | 1.507e-5 |

Short windows reduce these pre-onset errors but substantially worsen castanets' overall error at 96 kb/s. More subtransform side information and poorer frequency resolution create real tradeoffs. PE alone slightly harms castanets' measured pre-onset error at fixed rate; in VBR it lowers that error while increasing bitrate. All-on is not a recommended quality preset. The detector selects five short macroframes for harpsichord, 57 for castanets without PE, and 58 for castanets with PE. Human listening is still needed to judge audibility and preferences.

The expanded quantizer and complete alternative-book plans cost encoding time. Initial GUI generation can take substantially longer than the original encoder, particularly with all options, short windows, and the reservoir. Results are cached; controls remain disabled during synchronous encoding.
