function cfg = codec_config()
%CODEC_CONFIG Reproducible baseline; optional algorithms are not implemented yet.
cfg.sampleRate = 48000;
cfg.hop = 1024;
cfg.windowLength = 2048;
cfg.targetKbps = 96;
cfg.pam.referenceSPL = 96; % Assumed SPL for digital mean-square power = 1.
cfg.pam.maskingOffsetDB = 29;
cfg.pam.lowerSlope = 30; % dB/Bark, approaching a masker from below.
cfg.pam.upperSlope = -15; % dB/Bark, moving above a masker.
cfg.features = struct('tonalMaskers',false,'temporalMasking',false, ...
    'enhancedSpreading',false,'enhancedBandMapping',false, ...
    'huffman',false,'bandwidthExtension',false);
cfg.heldOut = 'speech';
end
