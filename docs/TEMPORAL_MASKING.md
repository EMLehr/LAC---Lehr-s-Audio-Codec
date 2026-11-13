# Temporal masking option — 2026-11-13

## Scope and hypothesis

`cfg.features.temporalMasking = true` enables temporal processing of the baseline PAM's masking allowances. The all-off baseline is unchanged. The quantizer, allocation algorithm, MDCT dimensions, binary format, and decoder are unchanged too. Six re-encoded development files were verified byte-identical to the baseline produced before this feature.

The working hypothesis is that limiting abrupt threshold increases will reduce some distortion before attacks, while a brief post-masking allowance can redistribute precision after loud events. Neither component is assumed to help universally at fixed rate. The fixed frame byte schedule has no reservoir: savings cannot move bits to other frames, only change allocation within a frame or become padding.

[Herre and Dick, sections 2.1 and 2.2](https://www.mdpi.com/2076-3417/9/14/2854) discuss post-masking over roughly 100–200 ms and distinguish codec pre-echo control, which limits threshold increases between frames. This implementation is a deliberately simple engineering approximation motivated by those mechanisms. The specific decay rate, boost limit, and growth caps below are our declared initial parameters, not values claimed to reproduce a standardized PAM or every listener's masking curve. They were chosen before running these development comparisons; no held-out speech quality data were used.

## Controls

All settings live in `codec_config.m`:

| Setting | Default | Meaning |
| --- | ---: | --- |
| `features.temporalMasking` | false | Master switch; false follows the original baseline path |
| `pam.temporal.postMasking` | true | Use recent raw masking energy after a masker |
| `pam.temporal.preEchoControl` | true | Cap sudden increases in allowable masking energy |
| `pam.temporal.postMaxMs` | 100 | Maximum history age, rounded down to whole frame hops |
| `pam.temporal.postDecayDBPerSecond` | 200 | Linear decay in dB with history age |
| `pam.temporal.postMaxBoostDB` | 6 | Maximum boost relative to current masking/quiet band reference |
| `pam.temporal.riseOneFrameDB` | 6 | Growth cap relative to the previous raw frame |
| `pam.temporal.riseTwoFramesDB` | 12 | Growth cap relative to the raw frame two hops earlier |

The sub-switches are ignored when the master is false. With the master true and both sub-switches false, the PAM is also an exact bypass. Post-only and pre-echo-only configurations are generated for comparison with the combined mode.

No anticipatory/backward masking is implemented. Pre-echo control is protection against transform-noise spreading before an attack, not a claim that the ear masks earlier audio. Processing uses no future PAM frames, although the MDCT itself still spans its required 42.67 ms window.

## Algorithm

Let `M[b,t]` be the baseline signal-dependent masking energy after frequency spreading, before the quiet-threshold maximum. Let `Q[b]` be the sum of per-bin quiet thresholds in that band. The hop interval is `dt = 1024/48000` seconds.

Post-masking uses at most `K = floor(0.100/dt) = 4` previous raw frames. Thus the oldest included frame center is 85.33 ms earlier; the next one at 106.67 ms is excluded. The history contribution is:

`R[b,t] = max_{j=1..K}(M[b,t-j] * 10^(-200*j*dt/10))`.

Only available past frames are considered. No history means R = 0. The decay is about 4.27 dB per hop, with a hard age limit. Post-masking proposes:

`P[b,t] = min(max(M[b,t],R[b,t]), max(M[b,t],Q[b])*10^(6/10))`.

The upper bound prevents an old large masker from granting an arbitrarily large allowance after the signal becomes quiet. It is relative to the band reference, not a universal per-bin audibility guarantee. With post-masking disabled, P = M.

Pre-echo control forms a cap from the previous **raw**, unmodified masking values:

`C1[b,t] = max(M[b,t-1],Q[b]) * 10^(6/10)`

`C2[b,t] = max(M[b,t-2],Q[b]) * 10^(12/10)`.

Use the minimum of the available caps and set `Mtemporal = min(P,C1,C2)`. With no previous frame, or with pre-echo control disabled, there is no cap. A sustained masker is therefore not held down indefinitely by previously reduced thresholds. Applying this cap after post-masking prevents the post component from overriding onset protection.

Finally, use the original bin-level construction and band mapping:

`T[k,t] = max(Tquiet[k], Mtemporal[b,t]/n_b)`

`A[b,t] = sum_{k in b}(T[k,t])`.

The optional feature changes the masking estimate, not the baseline mapping rule. The quiet threshold remains a floor. Thresholds are estimates and are not guaranteed to be met by quantization under a limited bit budget.

## State and file independence

`pac.pam(X,cfg,bands)` processes the columns of X in chronological order with a fresh history. For chunked analysis:

```matlab
[A1,T1,details1,state] = pac.pam(X1,cfg,bands);
[A2,T2,details2,state] = pac.pam(X2,cfg,bands,state);
```

History contains raw masking values, never recursively enhanced thresholds. Reset it when starting a new file or changing configuration. There is no persistent/global state. Whole-sequence and chunked results are tested within floating-point tolerance. An isolated-frame plot must compute history first; simply analyzing that one frame starts an empty history.

The encoder labels models in JSON and retains temporal diagnostics in its ignored diagnostic MAT files. All settings needed to reconstruct audio already reside in ordinary coefficient/quantizer fields. Decoder code and binary flags need no changes.

## Reproduction and checks

Run `stage5_verify_temporal`, then `stage5_temporal('encode')`, `stage5_temporal('decode')`, and `stage5_temporal('evaluate')`, using separate MATLAB batch processes as shown in README.md. Stages 1 and 4 must have prepared the development inputs and baseline files first.

Executed checks:

- Post-masking persists after a masker, decays, respects its boost bound, and expires.
- Pre-echo control limits sudden rises and recovers on sustained input.
- Silence and steady inputs remain stable; thresholds stay finite and positive.
- Whole-sequence versus chunked state, prefix causality, and independence between files.
- Master-off and both-components-off equivalence.
- Three synthetic burst round trips at matched 64/96/128 kb/s, with decoder samples exactly matching encoder-side quantized reconstruction.
- Existing nine synthetic baseline round trips still pass.
- Six existing development baseline bitstreams reproduce byte for byte.
- All 24 development comparison files decoded in a separate MATLAB process through the unchanged decoder.
- MATLAB Code Analyzer: zero messages.

## Measurements

There are four configurations for each source/rate: baseline, combined temporal, post-only, and pre-echo-only. Complete files are exactly 80,000 / 120,000 / 160,000 bytes for the 10-second clips, giving 64 / 96 / 128 kb/s and 12:1 / 8:1 / 6:1 ratios against the 768 kb/s PCM reference. Coefficient bits, side information, and padding are recorded separately. Full results and onset locations are in the local `outputs/temporal/` JSON/CSV files.

The combined option's changes relative to baseline are:

| Source | Rate kb/s | Global SNR change dB | Pre-onset error change dB |
| --- | ---: | ---: | ---: |
| Harpsichord | 64 | +0.0929 | -0.0089 |
| Harpsichord | 96 | +0.0196 | -0.0055 |
| Harpsichord | 128 | +0.0006 | -0.0013 |
| Castanets | 64 | +0.4746 | -0.9593 |
| Castanets | 96 | +0.1862 | -1.3297 |
| Castanets | 128 | +0.0015 | +0.1213 |

Positive SNR change means less overall squared error. **Negative pre-onset error change means less error** in the measured pre-onset regions; the positive castanets result at 128 kb/s is a small regression, not an improvement.

Onsets are detected solely from the original signal using fixed 1 ms block powers: power above 1e-6 and a rise of at least 12 dB over the preceding 10 ms mean, with a 100 ms refractory interval. Windows cover 20 ms before and after the detected onset. The detector found one harpsichord onset and 31 castanets onsets. The measure is `10*log10(MSE_variant/MSE_baseline)` on the same windows. These are diagnostic source-dependent windows, not standardized auditory tests; timing inaccuracies and existing source content mean the metric is not pure pre-echo energy.

Component comparisons at 64/96 kb/s on castanets indicate that pre-echo control contributes most of the measured gain: pre-echo-only SNR changes are +0.4999/+0.1926 dB, versus post-only changes of -0.0001/+0.0061 dB. Post-only therefore does not show a consistent objective benefit. All component results, including the small regressions, are retained. Parameters were not retuned to erase these results.

**Listening remains unassessed.** These measurements do not establish an audible preference. Speech remains held out and no final model selection has been made.

## Example masking curve and allocation

`outputs/temporal/temporal_masking_comparison.png` overlays the input spectrum, baseline global curve, and combined temporal curve for castanets frame 406, centered at approximately 8.6400 s. Units are `10*log10(X^2/1024)` relative to digital mean-square 1 per bin, not PSD; the assumed unity-power reference is 96 dB SPL.

The frame was selected for the largest mean log-threshold reduction, independently of output quality gains. Pre-echo control limits 17 bands in it; post-masking raises none. At 96 kb/s, bands 12 and 13 move from 4/5 bits to 6/6, while bands 3 and 4 move from 5 bits to zero. This illustrates redistribution under the unchanged budget: protecting one region costs precision elsewhere, so a lower masking threshold is not a guarantee of better overall sound. Frame data and the complete threshold sequences are retained locally for inspection.

## Limitations

- Fixed long windows remain; threshold control cannot eliminate every pre-echo.
- Frame-domain history is only an approximation to finer temporal hearing effects.
- The fixed byte schedule cannot reuse bits across time; post-masking does not create a reservoir.
- The quiet-threshold reference, conservative boost cap, and initial decay parameters are engineering choices requiring listening evaluation.
- Global SNR can miss audible localized errors, and a favorable pre-onset metric can coexist with harm elsewhere.
