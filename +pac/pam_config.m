function cfg = pam_config(mask,rate)
%PAM_CONFIG Enumerate the four independent PAM switches, mask 0 through 15.
validateattributes(mask,{'double'},{'scalar','integer','>=',0,'<=',15});
if nargin<2, rate=96; end
cfg=codec_config(); cfg.targetKbps=rate;
cfg.features.tonalMaskers=logical(bitget(uint8(mask),1));
cfg.features.temporalMasking=logical(bitget(uint8(mask),2));
cfg.features.enhancedSpreading=logical(bitget(uint8(mask),3));
cfg.features.enhancedBandMapping=logical(bitget(uint8(mask),4));
end
