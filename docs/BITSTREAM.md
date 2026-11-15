# LAC1 binary format, versions 1 through 4

All multi-byte header integers are unsigned little-endian. Frame bit fields are MSB first, with the first bit in bit 7 of the first byte. There is no Huffman coding, bit reservoir, checksum, or external codebook in version 1.

## Shared header

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | 4 bytes | ASCII `LAC1` |
| 4 | uint16 | Format version: 1, 2, 3, or 4 |
| 6 | uint16 | Version 1: zero. Versions 2/3/4: 1 = Huffman, 2 = bandwidth extension, 3 = both; versions 3/4 also accept zero |
| 8 | uint32 | Sample rate: 48000 |
| 12 | uint16 | MDCT coefficient count / hop N: 1024 |
| 14 | uint16 | Number of quantization bands B |
| 16 | uint64 | Original sample count L |
| 24 | uint32 | Frame count F = ceil(L/N) + 1 |
| 28 | uint32 | Versions 1/2/4: target bitrate R, integer bits/second. Version 3: zero (quality-target VBR) |
| 32 | uint32 | Header size H = 36 + 2(B+1) bytes, plus 4 bytes in version 4 |
| 36 | B+1 uint16 | Ascending zero-based band edges, first 0, last 1024; final edge exclusive |
| 36+2(B+1) | uint32, version 4 only | Reservoir capacity C in bytes |

Band edges in the file, rather than the PAM implementation, tell the decoder how to interpret each frame. Padding and window conventions are fixed by this version. The decoder does not need any encoder-side PAM parameters.

## Versions 1/2 byte schedule

Total file bytes are `T = floor(L / 48000 * R / 8)`. There are `P = T - H` frame bytes. For one-based frame f, its byte count is:

`floor(f * P / F) - floor((f-1) * P / F)`.

Thus each frame gets approximately the same capacity, with at most one byte of difference. The last frame ends exactly at T. The encoder rejects budgets that cannot fit all mandatory band-width fields. This schedule describes fixed file-rate allocation, including padding; it is not an MP3-compatible constant-rate frame structure.

## Version-1 frame contents

1. B unsigned 4-bit widths, in band order. Width 0 means every coefficient in the band is zero. Width 1 is reserved and rejected. Widths 2–15 are valid.
2. For every nonzero-width band, in band order:
   - One unsigned 8-bit step code c.
   - One signed two's-complement integer q of the declared width for each coefficient, ascending in frequency.
3. Zero bits until the allocated byte count is reached. Decoder rejects nonzero padding.

Reconstruction is `Xhat = q * 2^((c-128)/4)`. Step sizes range from `2^-32` to `2^31.75`. The encoder uses symmetric signed levels `[-(2^(w-1)-1), +(2^(w-1)-1)]`; the decoder supports the full two's-complement range.

After reconstructing all frames, the decoder applies the version-1 inverse MDCT with sine synthesis window and overlap-add, removes N leading samples, and returns exactly L samples. The encoder prepends N zeros and appends enough zeros for `F+1` hops of padded audio. No gain normalization is applied.

## Integrity and scope

The decoder validates magic, version, flags, dimensions, sample/frame counts, band edges, byte schedule, reserved widths, and zero padding. It rejects truncated files and unexpected trailing bytes. There is no CRC: a payload bit flip that still satisfies structural checks may change the audio without detection. This is a research file format, not a hardened untrusted-input media service.

The current decoder supports all four versions. Version 1 requires zero flags; version 2 requires flags 1, 2, or 3; versions 3/4 accept flags 0 through 3. Other combinations are rejected. With the new allocation options disabled, fixed-rate mode with both coding options off still writes version 1, byte-identical to earlier PAM-only encodes. Earlier decoders reject newer versions explicitly.

Temporal masking, tonal/noise classification, enhanced spreading, and enhanced band-allowance mapping are encoder-only PAM options. All 16 combinations use the same version-1 format and zero decoder feature flags. Their choices affect which coefficient integers and step sizes are stored, not how they are reconstructed. The encoder records the model and configuration in its optional JSON sidecar for experiments; that sidecar is never a decoding dependency.

## Version-2 frame contents

The magic, header layout, byte schedule, quantizer, MDCT, and sample trimming are unchanged. The current encoder uses 25 bands without BWE (88-byte header) and splits at coefficient boundary 512 for BWE (26 bands, 90-byte header). All boundaries remain stored in the header.

1. B four-bit widths, as in version 1.
2. If flag value 2 is present: four BWE groups, each with an unsigned eight-bit envelope followed by an unsigned two-bit noise code. This is 40 bits per frame, including silent frames.
3. For each nonzero-width band: eight-bit step code, then (if flag value 1 is present) one selector bit, then coefficients. Selector 0 means version-1 signed direct packing. Selector 1 means Huffman packing below. Without the Huffman flag, the selector is absent and direct packing is used.
4. Zero padding to the scheduled frame boundary.

Bands above the BWE boundary must have width zero. A boundary at zero-based coefficient 512 is mandatory when BWE is enabled. Width zero in these bands omits direct coefficients; BWE subsequently fills them. The minimum per-frame budget is `4*B + 40` bits with BWE, otherwise `4*B`. Active-band metadata and all coefficient bits are included in allocation costs.

### Fixed canonical Huffman book

Each coefficient encodes a category c: zero has category 0; otherwise `c = floor(log2(abs(q))) + 1`. The fixed category codewords are below. These are normative for version 2; no learned or external dictionary is needed.

| Category | Codeword |
| ---: | --- |
| 0 | 0 |
| 1 | 100 |
| 2 | 101 |
| 3 | 1100 |
| 4 | 1101 |
| 5 | 11100 |
| 6 | 11101 |
| 7 | 111100 |
| 8 | 111101 |
| 9 | 1111100 |
| 10 | 11111010 |
| 11 | 11111011 |
| 12 | 11111100 |
| 13 | 11111101 |
| 14 | 11111110 |
| 15 | 11111111 |

For c > 0, append one sign bit (1 = negative), then c-1 bits for `abs(q)-2^(c-1)`, MSB first. Category 0 has no suffix. Thus a nonzero coefficient costs codeword length plus c bits. Exactly the band's coefficient count is decoded; no terminator is used. The category cannot exceed stored width w, and the resulting value must fit `[-2^(w-1), 2^(w-1)-1]`. Invalid ranges and truncated payloads are rejected.

The encoder selects Huffman only when its coefficient bits are strictly fewer than direct packing; ties choose direct. The one-bit selector is counted in both alternatives. The fixed book was constructed using Huffman's merging algorithm with integer weights `[128 64 32 24 16 12 8 6 4 3 2 1 1 1 1 1]`, ties broken by ascending creation ID, followed by canonical assignment sorted by length then category. It was not trained on test audio. The codewords above, rather than floating-point probability calculations, define decoding.

### Bandwidth-extension reconstruction

Version 2 fixes the core to coefficients 1:512 (MATLAB indexing), below 12 kHz. Coefficients 513:1024 are four groups of 128 coefficients: nominal frequency ranges 12-15, 15-18, 18-21, and 21-24 kHz. The eight-bit envelope e defines target coefficient RMS: zero means silence; otherwise `RMS = 10^((e-160)/20)`. The two-bit code r defines noise fraction `r/3`. Silent envelopes require r = 0.

After dequantizing the core, reverse coefficients 512:1 into a 512-element template. Split it into four consecutive groups. For each non-silent high group g:

1. Normalize its template to unit Euclidean norm when nonzero.
2. Generate 128 deterministic noise values. With one-based frame f and group g, initialize `seed = mod(f*65537 + g*257,2147483646)+1`. Repeatedly update `seed = mod(48271*seed,2147483647)` and emit `2*seed/2147483647-1`. Normalize the noise vector to unit norm. Products fit exactly in double's integer range.
3. Use `mix = r/3`, or 1 if the template is zero. Form `shape = sqrt(1-mix)*template + sqrt(mix)*noise`. If its norm is below `1e-12`, use the noise vector instead.
4. Normalize shape to unit norm and multiply by `sqrt(128)*RMS` to obtain reconstructed high coefficients. A silent envelope writes all zeros.

Perform the usual inverse MDCT, overlap-add, and original-length trimming after this reconstruction. No original spectrum, encoder RNG state, PAM configuration, or metadata sidecar is consulted.

## Version 3: quality-target variable bitrate

The magic, header fields, band edges, quantizer, optional coding tools, and transform conventions are unchanged. Version 3 sets the rate field at offset 28 to **zero**. There is no target total size or deterministic fixed-rate byte schedule.

Each of the F frames consists of an unsigned little-endian uint16 payload length, immediately followed by that many payload bytes. The two-byte prefix does not count itself. Payload syntax is the same as version 2 (or version 1 when flags are zero). The encoder writes exactly `ceil(usedBits/8)` payload bytes; only 0-7 trailing zero alignment bits are allowed. Whole-byte padding is rejected. Coefficients above a BWE boundary are reconstructed using the same one-based frame index as before.

For B stored bands, N = 1024, and E = 40 when BWE is enabled or zero otherwise, the supported payload length must be between `ceil((4*B+E)/8)` and `ceil((13*B+15*N+E)/8)` bytes. These bounds cover all encoder candidates, including active-band step/selector overhead and maximum direct width. The decoder checks lengths before reading and requires EOF immediately after the Fth frame. Missing prefixes, truncated payloads, excess padding, nonzero rate, invalid flags, and trailing data are rejected.

Complete file bytes are `headerBytes + 2*F + sum(payloadBytes)`. Actual bitrate uses the original sample duration, not padded transform duration. The encoder's quality setting is optional experimental metadata in the JSON sidecar; it is not needed to decode the chosen integers and steps. The decoder never runs the PAM or needs to know the target that selected them.

## Version 4: fixed file rate with a capped reservoir

Version 4 sets a positive target bitrate R and appends a uint32 reservoir capacity C after the band edges. Header size is `H=40+2*(B+1)` (92 bytes without BWE, 94 with BWE). Frame payload syntax and optional coding flags are unchanged. Each frame has a uint16 payload-length prefix as in version 3, but version 4 permits canonical whole-byte zero padding to preserve the fixed total rate.

Let `T=floor(L/48000*R/8)` and `P=T-H-2*F`. Frame f has nominal payload capacity `n(f)=floor(f*P/F)-floor((f-1)*P/F)`. Every n(f) must fit the mandatory band-width/BWE fields. C must be at most `floor(100*P/F)`, and `max(n)+C` must fit uint16. The byte balance starts at zero.

For each frame, available bytes are `a=n(f)+balance`. Read a prefixed payload length l between the mandatory minimum and a. Decode its ordinary payload, require all trailing padding bits zero, and let `m=ceil(usedBits/8)`. The canonical stored length is:

```text
l = max(m, a-C)       for frames before the last
l = a                for the last frame
balance = a-l
```

Thus spare bytes carry forward up to C; overflow becomes padding, and the final frame empties the bucket with padding. Enforce this exact length rule, total file size T, and EOF after F frames. These checks establish causal credit conservation without requiring the encoder's PAM, NMR targets, saving ratios, sidecar, or original audio. The encoder may spend previously saved capacity but never borrow from future frames. Earlier versions are unchanged. Piecewise allocation alone requires no new syntax: without a bucket it uses versions 1/2 in fixed-rate mode or version 3 in VBR.
