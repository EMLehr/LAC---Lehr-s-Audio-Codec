function [policy,reservoir]=allocation_settings(cfg)
%ALLOCATION_SETTINGS Defaults preserve older configurations and bitstreams.
base=codec_config(); policy=base.allocation; reservoir=base.reservoir;
if isfield(cfg,'allocation'), policy=cfg.allocation; end
if isfield(cfg,'reservoir'), reservoir=cfg.reservoir; end
assert(islogical(policy.enabled) && isscalar(policy.enabled) && ...
    islogical(reservoir.enabled) && isscalar(reservoir.enabled),'pac:Config','Allocation switches must be logical.');
validateattributes(policy.boundariesDB,{'double'},{'real','finite','size',[1 3],'>=',-60,'<=',30});
assert(all(diff(policy.boundariesDB)<0),'pac:Config','NMR boundaries must strictly decrease.');
validateattributes(policy.savedNumerator,{'double'},{'real','finite','size',[1 3],'integer','>=',0});
validateattributes(policy.savedDenominator,{'double'},{'real','finite','size',[1 3],'integer','>=',1,'<=',1000});
assert(all(policy.savedNumerator<=policy.savedDenominator),'pac:Config','x cannot exceed y in x in y bits saved.');
validateattributes(policy.stopDB,{'double'},{'real','finite','scalar','>=',-60,'<=',policy.boundariesDB(3)});
validateattributes(reservoir.capacityFrames,{'double'},{'real','finite','scalar','integer','>=',0,'<=',100});
validateattributes(reservoir.targetDB,{'double'},{'real','finite','scalar','>=',-60,'<=',30});
[mode,~]=pac.rate_settings(cfg);
assert(~reservoir.enabled || strcmp(mode,'cbr'),'pac:Config','The bit reservoir requires fixed bitrate.');
end
