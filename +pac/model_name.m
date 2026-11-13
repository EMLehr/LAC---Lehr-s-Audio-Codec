function name = model_name(cfg)
%MODEL_NAME Human-readable encoder-side label; not a decoder dependency.
name='baseline';
if cfg.features.temporalMasking
    t=cfg.pam.temporal;
    if t.postMasking && t.preEchoControl
        name='temporal';
    elseif t.postMasking
        name='temporal_post_only';
    elseif t.preEchoControl
        name='temporal_preecho_only';
    else
        name='temporal_bypass';
    end
end
if cfg.features.tonalMaskers
    if strcmp(name,'baseline'), name='tonal'; else, name=['tonal_' name]; end
end
end
