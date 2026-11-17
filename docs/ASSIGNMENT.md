# Assignment settings

## Settings for the PAM-only investigation

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

