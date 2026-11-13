function validate_config(cfg)
base = codec_config();
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
    assert(~value || strcmp(names{k},'temporalMasking'),'pac:NotImplemented', ...
        'Optional feature %s is not implemented. Use false for baseline.',names{k});
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
