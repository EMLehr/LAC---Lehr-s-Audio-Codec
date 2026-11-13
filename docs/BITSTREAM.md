# LAC1 binary format, version 1

All multi-byte header integers are unsigned little-endian. Frame bit fields are MSB first, with the first bit in bit 7 of the first byte. There is no Huffman coding, bit reservoir, checksum, or external codebook in version 1.

## Header

| Byte offset | Type | Meaning |
| --- | --- | --- |
| 0 | 4 bytes | ASCII `LAC1` |
| 4 | uint16 | Format version: 1 |
| 6 | uint16 | Feature flags: 0; decoder rejects other values |
| 8 | uint32 | Sample rate: 48000 |
| 12 | uint16 | MDCT coefficient count / hop N: 1024 |
| 14 | uint16 | Number of quantization bands B |
| 16 | uint64 | Original sample count L |
| 24 | uint32 | Frame count F = ceil(L/N) + 1 |
| 28 | uint32 | Target bitrate R, integer bits/second |
| 32 | uint32 | Header size H = 36 + 2(B+1) bytes |
| 36 | B+1 uint16 | Ascending zero-based band edges, first 0, last 1024; final edge exclusive |

Band edges in the file, rather than the PAM implementation, tell the decoder how to interpret each frame. Padding and window conventions are fixed by this version. The decoder does not need any encoder-side PAM parameters.

## Byte schedule

Total file bytes are `T = floor(L / 48000 * R / 8)`. There are `P = T - H` frame bytes. For one-based frame f, its byte count is:

`floor(f * P / F) - floor((f-1) * P / F)`.

Thus each frame gets approximately the same capacity, with at most one byte of difference. The last frame ends exactly at T. The encoder rejects budgets that cannot fit all mandatory band-width fields. This schedule describes fixed file-rate allocation, including padding; it is not an MP3-compatible constant-rate frame structure.

## Frame contents

1. B unsigned 4-bit widths, in band order. Width 0 means every coefficient in the band is zero. Width 1 is reserved and rejected. Widths 2–15 are valid.
2. For every nonzero-width band, in band order:
   - One unsigned 8-bit step code c.
   - One signed two's-complement integer q of the declared width for each coefficient, ascending in frequency.
3. Zero bits until the allocated byte count is reached. Decoder rejects nonzero padding.

Reconstruction is `Xhat = q * 2^((c-128)/4)`. Step sizes range from `2^-32` to `2^31.75`. The encoder uses symmetric signed levels `[-(2^(w-1)-1), +(2^(w-1)-1)]`; the decoder supports the full two's-complement range.

After reconstructing all frames, the decoder applies the version-1 inverse MDCT with sine synthesis window and overlap-add, removes N leading samples, and returns exactly L samples. The encoder prepends N zeros and appends enough zeros for `F+1` hops of padded audio. No gain normalization is applied.

## Integrity and scope

The decoder validates magic, version, flags, dimensions, sample/frame counts, band edges, byte schedule, reserved widths, and zero padding. It rejects truncated files and unexpected trailing bytes. There is no CRC: a payload bit flip that still satisfies structural checks may change the audio without detection. This is a research file format, not a hardened untrusted-input media service.

Future Huffman or bandwidth-extension support must define its on-file semantics and decoder behavior explicitly, using versioning/flags. Existing version-1 files must remain decodable.

Temporal masking, tonal/noise classification, enhanced spreading, and enhanced band-allowance mapping are encoder-only PAM options. All 16 combinations use the same version-1 format and zero decoder feature flags. Their choices affect which coefficient integers and step sizes are stored, not how they are reconstructed. The encoder records the model and configuration in its optional JSON sidecar for experiments; that sidecar is never a decoding dependency.
