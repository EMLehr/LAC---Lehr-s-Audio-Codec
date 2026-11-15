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
if cfg.features.enhancedSpreading
    if strcmp(name,'baseline'), name='spreading'; else, name=[name '_spreading']; end
end
if cfg.features.enhancedBandMapping
    if strcmp(name,'baseline'), name='mapping'; else, name=[name '_mapping']; end
end
if cfg.features.huffman
    if strcmp(name,'baseline'), name='huffman'; else, name=[name '_huffman']; end
end
if cfg.features.bandwidthExtension
    if strcmp(name,'baseline'), name='bwe'; else, name=[name '_bwe']; end
end
[e,~]=pac.experiment_settings(cfg);
for option={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'}
    if e.(option{1}), name=[name '_' option{1}]; end %#ok<AGROW>
end
if e.fileHuffman && strcmp(e.huffmanScope,'window'), name=[name '_windowBooks']; end
end
