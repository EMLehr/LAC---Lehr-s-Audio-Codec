# LAC — Lehr's Audio Codec

A MATLAB perceptual audio codec for exploring psychoacoustic models, compression, and audio quality. The baseline processes **48 kHz mono audio** with a **2048-sample MDCT window and 1024-sample hop**. It produces custom `.lac` files and decodes them to WAV; it is not a standard AAC/MP3 encoder.

## Use it

Requires MATLAB (tested with R2025b). Preparing source audio also requires Signal Processing Toolbox; encoding and decoding do not require Audio Toolbox.

Set MATLAB's current folder to this project and run:

```matlab
listening_gui
```

Choose an excerpt, configure A/B as original or encoded audio, and click **Load / generate comparison**. Play or switch sides at the same position. The GUI includes feature toggles, CBR/VBR controls, looping, actual bitrate, compression percentage, and saved listening notes. Missing versions are generated and cached.

For your own audio, click **Open audio file...**, select a file, then **Load / generate comparison**. The full file is converted to 48 kHz mono for both sides, preserving levels and leaving the source untouched. Longer files take longer to encode; WAV or FLAC avoids prior lossy compression.

**First-time setup:** place the three SQAM WAVs in the project root, then run `lac_setup; stage1_prepare_inputs`. See [input preparation](docs/WORKFLOWS.md#prepare-the-audio) for filenames and downloads. Open a fresh GUI window after updating the code.

For command-line encoding and decoding:

```matlab
lac_setup                       % Set up paths for this MATLAB session
cfg = codec_config();           % Fixed 96 kb/s; every improvement off
cfg.features.tonalMaskers = true;
encode_audio('outputs/prepared/harpsichord.mat', 'outputs/example.lac', cfg);
decode_audio('outputs/example.lac', 'outputs/example.wav');
```

The decoder needs only the `.lac` file and this project's code. Input must already be 48 kHz mono. Generated files stay in `outputs/` and are excluded from Git.

## Improvements

All improvements default **off** and are independently selectable. Their effects interact; enabling everything is not necessarily better.

| Option | What it does | PAM-only assignment? |
| --- | --- | --- |
| Tonal vs noise maskers | Uses different masking strengths for tonal and noise-like content. | **Yes** |
| Temporal masking | Models post-masking and limits abrupt masking increases to protect against pre-echo; separate sub-controls. | **Yes** |
| Adaptive spreading | Adjusts masking spread with frequency and level. | **Yes** |
| Enhanced band mapping | Protects sensitive frequencies when converting masking curves into band allowances. | **Yes** |
| Fixed Huffman | Stores quantized symbols with a shared codebook when cheaper than direct packing. | No |
| Zero-run coding | Compactly stores consecutive zero coefficients. | No |
| Per-file / per-window Huffman | Tests learned books, including their overhead, with fallback when they do not save space. | No |
| Smarter quantizer | Tries more step sizes at each bit width to find better error/bit-cost choices. | No |
| Perceptual entropy (PE) | Guides precision and transient detection with fixed or variable windows. | No |
| Variable MDCT windows | Uses short transforms around attacks to limit pre-echo; changes the required transform dimensions. | **No — experimental** |
| Bandwidth extension | Reconstructs content above 12 kHz using lower-frequency content and shaping parameters. | No |
| Variable bitrate (VBR) | Targets PAM-relative distortion instead of a fixed file bitrate. | No |
| Piecewise bit saving | Reserves adjustable fractions of refinement bits across three noise-to-mask ratio ranges. | No |
| Bit bucket | Carries unused fixed-rate capacity forward to later frames. | No |

For the **required PAM-only comparison**, use CBR at **64, 96, and 128 kb/s**, the default fixed MDCT dimensions, and only the four options marked **Yes**. Keep the original quantizer/allocator and all other improvements off. [Exact assignment settings](docs/ASSIGNMENT.md).

In VBR, lower distortion settings demand more precision; +9/+12 dB allow more error for smaller files. Piecewise controls use **“x in y bits saved”** relative to masking allowances. In CBR, savings can buy precision or fill the bucket, but total file size remains fixed. Listening matters: better numerical measurements alone do not establish better perceived quality.

## Further information

Code lives in `src/`, runnable workflows in `stages/`, verification scripts in `tests/`, and detailed algorithms/results in `docs/`. The root contains the GUI launcher and session setup function.

[Documentation index](docs/README.md) · [Reproduction commands](docs/WORKFLOWS.md) · [Listening controls](docs/LISTENING_GUI.md)
