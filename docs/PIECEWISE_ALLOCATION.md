# Piecewise bit saving and a fixed-rate bit bucket

These are optional allocation experiments. They leave the PAM, scalar quantizer candidates, transform dimensions, and reconstruction rules unchanged. Both default off. Keep them off for the assignment's controlled PAM comparisons unless the same allocation settings are explicitly fixed across both PAMs.

## Controls and units

In `listening_gui`, choose an encoded side and open **Piecewise saving / bit bucket...**. Each side has independent settings. Apply, then Load the comparison.

The control quantity is noise-to-mask ratio (NMR):

```text
NMR = 10*log10(D / A)
D = sum of squared coefficient quantization errors within a directly coded band
A = that band's allowance from the selected PAM
```

Lower NMR means less error relative to the allowance. This is the same allowance scaling used by ordinary VBR: +9 dB permits about eight times A, and +12 dB about sixteen times A. It is not waveform SNR, a calibrated loudness level, or an assurance of transparency.

Default piecewise controls are:

| Current band NMR | Saving control |
| --- | --- |
| Greater than -6 dB | No deliberate saving |
| At/below -6 and above -9 dB | **1 in 4 bits saved** |
| At/below -9 and above -15 dB | **1 in 2 bits saved** |
| At/below -15 dB | **1 in 1 bits saved** |

All three boundaries and all three ratios are editable. For example, change the lowest ratio to **3 in 4 bits saved** to keep refining after -15 dB. **0 in 1 bits saved** reserves nothing; **1 in 1 bits saved** blocks further paid upgrades in that layer. Boundary equality belongs to the lower-error layer. Boundaries must strictly decrease; numerator x must be an integer from zero through denominator y, and y must be an integer from 1 through 1000.

The **final refinement limit** defaults to -24 dB and must be at/below the lowest boundary. Once a band reaches it, no further upgrade is purchased. Discrete quantization steps can overshoot boundaries or the final limit. This is a stopping limit, not a guarantee that the available budget or saving policy will reach it.

The independent bucket toggle works in fixed-rate mode. Capacity defaults to eight nominal frames, with a supported range of zero through 100. When piecewise saving is off, its **saving target** defaults to 0 dB NMR: choose the cheapest quantizer meeting that allowance and save the remainder. If available capacity cannot reach the target, use the original budget-constrained allocator. With piecewise enabled, its three-layer policy replaces the single bucket target.

## How ratios apply to indivisible upgrades

The allocator begins with omitted bands and evaluates the existing width/step candidates, including exact Huffman costs when enabled. It follows each band's cost/distortion frontier, considering the next cheapest candidate that lowers distortion. A cost-neutral or cheaper improvement may be taken without a saving charge. It never buys more precision in a band already at the final limit.

For a positive incremental cost d and saving ratio r=x/y:

```text
reserved = ceil(d*r/(1-r))
virtual cost = d + reserved
```

Thus a ten-bit upgrade at **1 in 2 bits saved** reserves ten bits and requires twenty available bits. **1 in 4 bits saved** reserves at least one bit for every three spent. Whole-bit rounding can reserve less than one extra bit beyond the ideal value per upgrade. The numerator describes the saved share of the combined spent-plus-reserved capacity, not the saved/spent ratio. At r=1, paid upgrades are prohibited.

Among affordable upgrades, choose the greatest reduction of allowance-normalized distortion per virtual bit. Use the band's NMR before the upgrade to select its layer. A whole-band upgrade can cross a boundary; ratios are not enforced on individual coefficient bits or retrospectively split across a crossing. This granularity is a limitation of the existing quantizer. The allocator stops when no affordable permitted improvement remains.

Saving applies to incremental quantizer representation costs, including step/selector metadata affected by an upgrade. Mandatory headers, framing, width fields, and BWE parameters cannot be saved. Per-layer reserved/spent counters are allocation diagnostics, not exact whole-file compression percentages. Unused capacity and byte alignment also affect actual size.

## Fixed-rate behavior

Without the bucket, the original frame budget remains fixed and all unused capacity becomes zero padding. Piecewise saving by itself therefore changes reconstruction but does not shrink a fixed-rate file.

With the bucket, a frame can spend its nominal capacity plus previously saved bytes. The balance starts at zero, cannot go negative, and cannot exceed its configured capacity. No future bits are borrowed. Unused whole bytes carry forward; capacity overflow and the final balance become explicit zero padding. Consequently, total file size remains exactly the duration-derived fixed-rate size. Bucket capacity is `floor(capacityFrames * mean(nominalPayloadBytes))`; eight hops correspond to about 171 ms, but capacity is measured in bytes, not a fixed lookahead or playback delay.

Bucket mode adds four header bytes and two length bytes per frame, all paid from the same total file budget. These costs can offset benefits. The decoder reads variable-sized payloads sequentially; there are no MP3-style back-pointers. See [BITSTREAM.md](BITSTREAM.md) for version 4.

## Variable-rate behavior

VBR has no conserved average-rate budget to put in a bucket. Piecewise VBR first calculates the ordinary VBR bit cost of reaching the final refinement limit using the same candidates. That finite cost, including mandatory width fields, becomes the frame's **virtual refinement budget**. Piecewise allocation debits both spent and reserved bits from it. Only the chosen actual representation is written, with ordinary version-3 minimal byte alignment. Reserved capacity does not become padding.

This rule ensures that a partial lowest-layer ratio has a finite budget; otherwise continuing indefinitely would eventually spend the nominal savings. The ordinary VBR preset is ignored while piecewise allocation is enabled. It is disabled in the GUI to make this explicit. The final limit, three boundaries, and ratios jointly determine achieved quality and bitrate. Even with savings, a strict -24 dB reference budget can produce a larger file than ordinary 0 dB VBR. Compare against the same reference configuration, not an unrelated quality preset.

`coreTargetMisses` records failures of the reference target within the available quantizer candidates. `policyBandsAboveLimit` separately records actual directly coded bands above the final limit after piecewise allocation; such misses are expected when savings deliberately stop refinement. `bandsOverScaledTarget` includes reconstructed BWE bands too. BWE high-band reconstruction is outside these directly coded allocation guarantees.

## MATLAB configuration

```matlab
cfg = codec_config();
cfg.targetKbps = 96;
cfg.allocation.enabled = true;
cfg.allocation.boundariesDB = [-6 -9 -15];
cfg.allocation.savedNumerator = [1 1 3];
cfg.allocation.savedDenominator = [4 2 4];
cfg.allocation.stopDB = -24;
cfg.reservoir.enabled = true;
cfg.reservoir.capacityFrames = 8;
encode_audio('outputs/prepared/harpsichord.mat', ...
    'outputs/example_bucket.lac', cfg);

% Same three-layer policy in VBR; reserved bits reduce stored size.
cfg.rateMode = 'vbr';
cfg.reservoir.enabled = false;
encode_audio('outputs/prepared/harpsichord.mat', ...
    'outputs/example_piecewise_vbr.lac', cfg);
```

For bucket-only allocation, set `cfg.allocation.enabled=false` and `cfg.reservoir.targetDB` to the desired NMR. Old configurations with neither new structure retain the original behavior. Explicitly requesting a bucket in VBR is rejected by the API; the GUI disables it in that mode while retaining the side's fixed-rate settings.

## Reproduction and validation

After prepared inputs, baseline outputs, and the earlier coding/VBR regression fixtures exist, run separate processes:

```text
matlab -batch "stage11_verify_allocation;"
matlab -batch "stage11_allocation('encode');"
matlab -batch "stage11_allocation('decode');"
matlab -batch "stage11_allocation('evaluate');"
matlab -batch "stage11_verify_gui;"
```

The comparison stage creates 34 files: two development clips, all three fixed rates with baseline/bucket/piecewise/both, plus five VBR conditions per clip (ordinary -24 dB, piecewise with full or partial bottom-layer saving, ordinary +9 and +12 dB). Speech remains held out. WAVs preserve level and alignment. Actual size counts every header, prefix, payload, and padding byte against the 768 kb/s PCM reference.

Structural checks passed for 128 exact round trips spanning all 64 feature combinations in bucket-plus-piecewise CBR and piecewise VBR. Checks cover layer boundaries, partial bottom ratios, zero-saving ratios, capacity/credit conservation, actual borrowing, overflow/final padding, malformed files, and invalid settings. Sixteen earlier CBR/VBR files remain byte-identical with the new options off. GUI checks cover both new presets, editable ratios, invalid input, independent sides, mode restrictions, cache configurations, and saved notes.

Measurements and bucket balance plots are written under `outputs/allocation/`. Listening observations remain uncollected; objective improvements or regressions must not be presented as proof of perceptual benefit.

## Measured development results

All 34 files decoded in a fresh MATLAB process. The six regenerated baseline files at 64/96/128 kb/s also match the earlier baseline bytes. All project MATLAB files pass Code Analyzer, and the existing stage 9 and stage 10 GUI checks still pass.

At 96 kb/s, every file is 120,000 bytes (87.50% smaller than the PCM reference). With the baseline PAM and coding tools off:

| Allocation | Harpsichord waveform SNR | Castanets waveform SNR |
| --- | ---: | ---: |
| Original fixed-frame allocator | 10.919 dB | 12.776 dB |
| Bucket only, 0 dB saving target | 10.801 dB | 12.964 dB |
| Piecewise only | 10.738 dB | 12.779 dB |
| Piecewise plus bucket | 10.912 dB | 12.928 dB |

The bucket alone slightly improves this castanets measurement and slightly harms harpsichord. Combined allocation reduces measured pre-onset error for both clips at 96 kb/s, but waveform SNR does not consistently improve. The policy reserves capacity even when some other bands remain coarse; it is not a global optimum. Bucket-only allocation can also choose to stop before spending all available capacity once its target is met.

VBR results with the same baseline PAM are:

| Allocation | Harpsichord kb/s | Harpsichord SNR | Castanets kb/s | Castanets SNR |
| --- | ---: | ---: | ---: | ---: |
| Ordinary VBR, -24 dB reference | 191.691 | 17.101 dB | 211.902 | 20.080 dB |
| Piecewise, bottom 1 in 1 saved | 153.170 | 12.471 dB | 168.878 | 17.510 dB |
| Piecewise, bottom 3 in 4 saved | 152.293 | 13.860 dB | 169.709 | 17.476 dB |
| Ordinary VBR, +9 dB | 67.936 | 11.095 dB | 86.288 | 14.508 dB |
| Ordinary VBR, +12 dB | 60.070 | 10.708 dB | 77.037 | 13.283 dB |

The partial bottom layer changes which upgrades win the finite shared budget, so changing a saving ratio need not monotonically change total size or waveform SNR. In this harpsichord example, allowing some bottom-layer upgrades yields a slightly smaller file than fully stopping in that layer. These are unmatched-rate measurements, not equal-quality comparisons. The +12 dB files reduce PCM size by 92.18% for harpsichord and 89.97% for castanets; whether their audible quality is acceptable remains a listening decision.
