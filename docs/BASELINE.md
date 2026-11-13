# Baseline mathematics and design choices

This is a documented educational adaptation. It is not a full MPEG reference PAM or a full FastEnc implementation. The user requires optional features to be absent from the baseline.

## Transform and normalization

Let N = 1024, n = 0,...,2N-1, and k = 0,...,N-1. The analysis/synthesis sine window is:

`w[n] = sin(pi*(n+1/2)/(2N))`.

The stored transform matrix is:

`A[n,k] = sqrt(2/N) * cos(pi/N * (n+1/2+N/2) * (k+1/2))`.

Analysis is `X = A' * (w .* frame)`. Synthesis is `w .* (A * X)`, added at N-sample intervals. The window satisfies `w[n]^2 + w[n+N]^2 = 1`. Leading/trailing padding permits time-domain alias cancellation at the original signal boundaries.

Across all correctly padded frames, `sum(X(:).^2)` matches original signal energy. Per frame, `sum(X.^2)/N` is an approximate local mean-square measure, not an exact phase-independent power measurement. Individual MDCT coefficients can vary with phase. A separate FFT-based PAM could avoid some of this limitation, but the baseline deliberately uses an MDCT-domain estimate.

Bin centers are `(k+1/2)*fs/(2N)`. Plots show `10*log10(X[k]^2/N)`, in dB relative to digital mean-square power 1 **per bin**, not dB/Hz or measured SPL. Thresholds use the same normalization.

## Auditory bands

With f in Hz:

`z(f) = 13*atan(0.00076*f) + 3.5*atan((f/7500)^2)`.

Group contiguous bins with equal `floor(z)`. Each band's center is the mean Bark value of its bins. These fixed one-Bark groups are used for both analysis and quantization. Their zero-based edges are also stored in each encoded file.

## Threshold in quiet

With u = f/1000:

`ATH_dB(f) = 3.64*u^(-0.8) - 6.5*exp(-0.6*(u-3.3)^2) + 0.001*u^4`.

This commonly used analytic approximation is described in [Painter and Spanias, section II-A](https://www.ee.columbia.edu/~dpwe/e6820/papers/PaintS00-pcpcod.pdf). The implementation clamps it to [-20,80] dB as a practical numerical/model guard at the frequency extremes; that clamp is our explicit design choice.

Assume digital mean-square power 1 corresponds to 96 dB SPL. A full-scale sine has mean-square power 0.5 and would therefore correspond to approximately 93 dB SPL under this assumption. This is a model reference, **not a measurement of the user's playback equipment**.

For bin k in a band with n_b coefficients:

`Tquiet[k] = N * 10^((ATH_dB(f_k)-96)/10) / n_b`.

Treating the threshold as auditory-band power and distributing it among bins is an explicit approximation. Correct units and declared normalization do not establish physiological accuracy; this mapping remains a baseline modeling limitation.

## Signal-dependent masking and spreading

Band energy is `E[b] = sum(X[k]^2)` for coefficients in band b. For target band b and masker band m, let `d = z_b-z_m`:

`S[b,m] = 10^((30*min(d,0) - 15*max(d,0))/10)`.

The target band's signal-dependent allowance is:

`M[b] = 10^(-29/10) * sum_m(S[b,m] * E[m])`.

A 29 dB masking offset and fixed +30/−15 dB/Bark slopes are motivated by the simplified model discussed in [Herre and Dick, section 2.3](https://www.mdpi.com/2076-3417/9/14/2854). We use those ingredients without that implementation's pre-echo control or other processing. Spreading contributions are summed in linear energy; columns of S are not normalized as probability distributions.

For each bin in band b:

`T[k] = max(Tquiet[k], M[b]/n_b)`.

This forms the global masking curve. The band distortion allowance is `A[b] = sum_k(T[k])` within that band. The higher of quiet and signal-dependent thresholds is used; they are not added in dB. There is no tonality classification, frame history, temporal masking, adaptive spreading, or enhanced mapping.

## Quantization and allocation

Each band can be omitted (zero bits per coefficient) or use a uniform midtread quantizer with w = 2,...,15 bits. For each candidate:

- `qmax = 2^(w-1)-1`.
- Choose the smallest stored step `delta = 2^((c-128)/4)` large enough that `qmax*delta` covers the band's maximum magnitude, with c restricted to [0,255].
- `q = clip(round(X/delta), -qmax, qmax)`.
- Reconstruct `Xhat = q*delta` and measure actual band squared error `D[b,w]`.
- Incremental storage cost is `8 + n_b*w` bits for an active band, plus a mandatory 4-bit width for every band.

Starting with all bands omitted, repeatedly choose the feasible band/precision upgrade with the largest reduction in `D[b,w]/A[b]` per extra bit. All larger widths are considered, including jumps over inefficient candidates. Stop when no positive improvement fits the remaining frame capacity.

This greedy discrete allocation is deterministic but is not guaranteed globally optimal. At constrained rates it may exceed masking allowances. The encoder records the number of band/frame violations rather than claiming all noise is masked. The allocator and quantizer remain shared and fixed for future controlled PAM comparisons.

Remaining capacity is zero padding. Silence can therefore contain mostly padding while still meeting the declared fixed bitrate. Report useful coefficient bits, metadata bits, and padding separately. No bit reservoir transfers unused capacity between frames.

## Evaluation conventions

- Actual rate = `8 * complete_file_bytes / original_duration_seconds / 1000` kb/s.
- Compression ratio = `768 / actual_kbps`.
- Global SNR = `10*log10(sum(x.^2)/sum((x-y).^2))` using aligned samples with unchanged gain.
- Segmental SNR uses nonoverlapping 1024-sample segments, discards segments with mean-square input <= 1e-8, clamps segment scores to [-10,35] dB, and averages them. These are declared reporting choices, not standardized perceptual ratings.
- Decoded WAVs contain IEEE float32 samples. Measurement differences from the internal double decoder are limited to this sample rounding; WAV fidelity is explicitly tested.
- Listening remains necessary. Do not treat SNR, a lower objective error, or a masking estimate alone as proof of inaudibility or perceptual improvement.
