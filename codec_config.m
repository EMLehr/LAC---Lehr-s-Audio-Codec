function cfg = codec_config()
%CODEC_CONFIG All-off baseline; four PAM and two optional coding features.
cfg.sampleRate = 48000;
cfg.hop = 1024;
cfg.windowLength = 2048;
cfg.targetKbps = 96;
cfg.rateMode = 'cbr'; % Fixed total-file bitrate remains the assignment baseline.
cfg.vbr.distortionDB = 0; % VBR allowance multiplier = 10^(dB/10); lower is stricter.
cfg.allocation=struct('enabled',false,'boundariesDB',[-6 -9 -15], ...
    'savedNumerator',[1 1 1],'savedDenominator',[4 2 1],'stopDB',-24);
cfg.reservoir=struct('enabled',false,'capacityFrames',8,'targetDB',0);
cfg.experiments=struct('zeroRun',false,'fileHuffman',false,'smartQuantizer',false, ...
    'perceptualEntropy',false,'variableWindows',false,'stepRadius',3, ...
    'peStrengthDB',3,'attackProtectionDB',6,'attackRatio',8,'huffmanScope','file');
cfg.pam.referenceSPL = 96; % Assumed SPL for digital mean-square power = 1.
cfg.pam.maskingOffsetDB = 29;
cfg.pam.lowerSlope = 30; % dB/Bark, approaching a masker from below.
cfg.pam.upperSlope = -15; % dB/Bark, moving above a masker.
% Adapted level/frequency-dependent slope; see docs/FINAL_PAM_OPTIONS.md.
cfg.pam.spreading = struct('lowerSlope',27,'minUpperMagnitude',8, ...
    'maxUpperMagnitude',40,'minLevelDB',-20,'maxLevelDB',100);
% Tonality is a continuous spectral-flatness estimate within each masker band.
cfg.pam.tonal = struct('noiseFlatnessDB',-6,'toneFlatnessDB',-30, ...
    'noiseOffsetDB',15,'toneOffsetDB',29);
% These settings are used only when features.temporalMasking is true.
cfg.pam.temporal = struct('postMasking',true,'preEchoControl',true, ...
    'postMaxMs',100,'postDecayDBPerSecond',200,'postMaxBoostDB',6, ...
    'riseOneFrameDB',6,'riseTwoFramesDB',12);
cfg.features = struct('tonalMaskers',false,'temporalMasking',false, ...
    'enhancedSpreading',false,'enhancedBandMapping',false, ...
    'huffman',false,'bandwidthExtension',false);
cfg.heldOut = 'speech';
end
