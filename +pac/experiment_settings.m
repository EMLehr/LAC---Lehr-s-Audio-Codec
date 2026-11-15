function [e,enabled]=experiment_settings(cfg)
%EXPERIMENT_SETTINGS Defaults also accept saved pre-experiment configurations.
base=codec_config(); e=base.experiments;
if isfield(cfg,'experiments'), e=cfg.experiments; end
names={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'};
enabled=false;
for k=1:numel(names)
    v=e.(names{k}); assert(islogical(v) && isscalar(v),'pac:Config','Experiment switches must be logical.');
    enabled=enabled || v;
end
validateattributes(e.stepRadius,{'double'},{'scalar','integer','>=',1,'<=',8});
validateattributes(e.peStrengthDB,{'double'},{'scalar','real','finite','>=',0,'<=',12});
validateattributes(e.attackProtectionDB,{'double'},{'scalar','real','finite','>=',0,'<=',24});
validateattributes(e.attackRatio,{'double'},{'scalar','real','finite','>=',2,'<=',100});
assert(ismember(e.huffmanScope,{'file','window'}),'pac:Config','Huffman scope must be file or window.');
end
