function validate_config(cfg)
base = codec_config();
pac.rate_settings(cfg);
pac.allocation_settings(cfg);
pac.experiment_settings(cfg);
assert(cfg.sampleRate == 48000 && cfg.hop == 1024 && ...
    cfg.windowLength == 2048,'pac:Config','Required transform dimensions changed.');
assert(isscalar(cfg.targetKbps) && isfinite(cfg.targetKbps) && ...
    cfg.targetKbps > 0,'pac:Config','Target bitrate must be positive.');
assert(isequal(sort(fieldnames(cfg.features)),sort(fieldnames(base.features))), ...
    'pac:Config','Unknown or missing feature fields.');
names = fieldnames(cfg.features);
for k = 1:numel(names)
    value = cfg.features.(names{k});
    assert(islogical(value) && isscalar(value),'pac:Config','Feature flags must be logical scalars.');
end
if cfg.features.enhancedSpreading
    t=cfg.pam.spreading;
    validateattributes(t.lowerSlope,{'double'},{'scalar','finite','positive','<=',120});
    validateattributes(t.minUpperMagnitude,{'double'},{'scalar','finite','positive'});
    validateattributes(t.maxUpperMagnitude,{'double'}, ...
        {'scalar','finite','>=',t.minUpperMagnitude,'<=',120});
    validateattributes(t.minLevelDB,{'double'},{'scalar','finite'});
    validateattributes(t.maxLevelDB,{'double'},{'scalar','finite','>',t.minLevelDB});
end
if cfg.features.tonalMaskers
    t=cfg.pam.tonal;
    validateattributes(t.noiseFlatnessDB,{'double'},{'scalar','finite','<=',0});
    validateattributes(t.toneFlatnessDB,{'double'},{'scalar','finite','<',t.noiseFlatnessDB});
    validateattributes(t.noiseOffsetDB,{'double'},{'scalar','finite','>=',0,'<=',120});
    validateattributes(t.toneOffsetDB,{'double'},{'scalar','finite','>=',t.noiseOffsetDB,'<=',120});
end
if cfg.features.temporalMasking
    t=cfg.pam.temporal;
    assert(islogical(t.postMasking) && isscalar(t.postMasking) && ...
        islogical(t.preEchoControl) && isscalar(t.preEchoControl), ...
        'pac:Config','Temporal sub-switches must be logical scalars.');
    validateattributes(t.postMaxMs,{'double'},{'scalar','finite','>=',0,'<=',1000});
    validateattributes(t.postDecayDBPerSecond,{'double'},{'scalar','finite','positive'});
    validateattributes(t.postMaxBoostDB,{'double'},{'scalar','finite','>=',0,'<=',60});
    validateattributes(t.riseOneFrameDB,{'double'},{'scalar','finite','>=',0,'<=',60});
    validateattributes(t.riseTwoFramesDB,{'double'},{'scalar','finite','>=',0,'<=',120});
end
assert(isfinite(cfg.pam.referenceSPL) && isfinite(cfg.pam.maskingOffsetDB) && ...
    cfg.pam.lowerSlope > 0 && cfg.pam.upperSlope < 0, ...
    'pac:Config','Invalid PAM parameters.');
end
