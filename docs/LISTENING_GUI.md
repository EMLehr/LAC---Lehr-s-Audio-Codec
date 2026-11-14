# MATLAB listening GUI

From the project folder, run:

```matlab
listening_gui
```

The window opens with the prepared harpsichord original in A and the baseline codec at 96 kb/s in B. It uses MATLAB's programmatic UI and `audioplayer`; App Designer, Audio Toolbox, and a web server are not required. Prepared inputs from `stage1_prepare_inputs` must exist. MATLAB's standard Java-enabled desktop environment is required for the cache fingerprint.

## Comparing versions

1. Choose harpsichord, castanets, or the explicitly labelled final-test speech excerpt.
2. Independently configure A and B as Original or Encoded. Each encoded side has its own 64/96/128 kb/s selection and all six feature checkboxes. All boxes off means baseline. Temporal masking additionally offers both components, post-only, pre-echo-only, or bypass.
3. Click **Load / generate comparison**. A selection change pauses playback and disables playback/notes until loaded, preventing a comparison from being labelled with settings that have not been applied.
4. Select **Listen A** or **Listen B**, then **Play**. Pressing the other side while playing resumes that side at the current sample position. This restarts the audio device, so a brief switching gap is possible; it is not a gapless crossfade. Pause retains the position. Stop returns to the region start.
5. Seek with the timeline, enter a region in seconds with **From** and **to**, and enable **Loop** to repeat it. Regions shorter than 20 ms or with reversed endpoints reset to the full clip.
6. Write observations and click **Save listening notes**. The saved record includes both configurations, actual rates and paths, source, region, active side, common playback gain, and a UTC timestamp.

This supports all 64 combinations of the six switches at each of the three rates, plus the temporal component variants. You can compare original versus codec, two different bitrates, or two different feature combinations. Generating every variation in advance is unnecessary. Configurations are labelled; this is an A/B audition interface, not a blinded ABX or formal listening-test protocol.

Speech is not automatically encoded or auditioned. Selecting it only changes the pending selection; clicking Load consumes that final-test excerpt. Choose and freeze the PAM investigation before using speech results to judge it. The GUI does not perform automatic model selection or change codec defaults.

## Levels, alignment, and playback

The original is the exact prepared 48 kHz mono sample sequence. Encoded sides are reconstructed by `decode_audio` from their `.lac` file, with the original length/delay restored. The GUI does not re-encode a decoded WAV. The waveform plot uses block minima/maxima for display; playback uses the full sample arrays.

A single volume setting and headroom factor apply equally to both sides:

```text
gain = 0.98 * (volume / 100) / max(1, peak(A), peak(B))
```

The default volume is 75%, so gain is 0.735 unless a reconstruction exceeds full scale. The displayed shared gain makes any common attenuation visible. This prevents playback clipping while preserving the relative levels of A and B. Changing either configuration can change the common headroom factor; there is no independent loudness normalization. Original and decoded files remain untouched by playback gain. Playback uses 24-bit output through MATLAB's default audio device; select the desired headphones/output in the operating system. Audio-device errors are shown in the status line.

The original's displayed 768 kb/s is the assignment's mono 16-bit PCM reference, not the storage bitrate of a float WAV or MAT file. Encoded sizes/rates are measured from the binary file, including headers and padding.

## Cache and listening records

Generated versions live in `outputs/listening/cache/`. The key is SHA-256 over the prepared samples, complete encoder configuration, and codec source. A changed source, codec, or configuration creates a different entry. GUI-only changes do not invalidate audio. New files are encoded to a temporary path and decoded successfully before entering the cache. Cache hits are still decoded from the `.lac` file. A float WAV and ordinary encoder statistics/diagnostics are retained alongside it.

The GUI owns this cache rather than assuming older stage outputs were produced from the current source/configuration. Existing stage outputs remain unchanged. The first use of a version can take a few seconds; subsequent loads reuse it. Encoding is synchronous and the controls are disabled while loading. There is no background full-matrix batch or cancellation midway through an encode.

Notes are JSON records under `outputs/listening/notes/`. They are local artifacts, excluded from Git along with cached audio. The automated GUI test writes a clearly labelled test note; it is not a human listening observation. Real listening observations must be entered by the listener. Saved notes do not overwrite the objective evaluation reports or claim any perceptual improvement.

## Verification

After preparation and stage 7 development encoding:

```matlab
stage9_verify_listening          % UI gestures, cache, settings, alignment, notes
stage9_verify_listening(true)    % Also exercise muted audio transport
```

Checks cover actual UI gestures, the unchanged baseline binary, exact decoder samples, cache reuse, independent bitrates, all six feature controls, temporal components, switching position, common gain, region validation, saved notes, source changes, and deferred speech loading. The optional audio check runs at zero playback gain and covers playback, pause, side switching, looping, and natural completion. It checks transport behavior, not subjective audio quality. Results and a rendered GUI preview are saved under `outputs/listening/`.

Both the GUI checks and the muted audio transport checks passed in MATLAB R2025b Update 1. Code Analyzer reports zero messages for the new source files. No human listening quality judgments were generated by these checks.

On this Windows installation, a separate MATLAB batch process that initializes audio can crash during process shutdown inside `libportaudio.dll` / ASIO cleanup. The crash also occurs after a standalone `audiodevinfo` query, without this GUI. It is distinct from closing the GUI or decoding files. Run the optional audio check in an existing interactive MATLAB session; the GUI does not modify audio drivers or MATLAB installation settings to work around the native shutdown issue.
