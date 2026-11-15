function [mode,distortionDB] = rate_settings(cfg)
%RATE_SETTINGS Old saved configurations remain fixed-rate by default.
mode='cbr'; distortionDB=0;
if isfield(cfg,'rateMode'), mode=char(cfg.rateMode); end
assert(ismember(mode,{'cbr','vbr'}),'pac:Config','rateMode must be cbr or vbr.');
if isfield(cfg,'vbr'), distortionDB=cfg.vbr.distortionDB; end
validateattributes(distortionDB,{'double'},{'scalar','real','finite','>=',-30,'<=',30});
end
