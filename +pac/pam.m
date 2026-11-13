function [allowance,threshold,details,state] = pam(X,cfg,bands,state)
%PAM MDCT-domain masking with optional temporal history, in squared MDCT units.
% Call on a complete chronological sequence, or pass fourth output into next call.
% Omitting state starts an independent stream; the all-off path is unchanged.
if nargin<4, state=[]; end
N = cfg.hop;
B = numel(bands.count);
E = zeros(B,size(X,2));
ath = zeros(N,1);
fk = bands.frequency/1000;
athDB = 3.64*fk.^(-0.8)-6.5*exp(-0.6*(fk-3.3).^2)+0.001*fk.^4;
athDB = min(80,max(-20,athDB)); % Explicit practical guard, not calibration.
for b = 1:B
    idx = bands.edges(b):bands.edges(b+1)-1;
    E(b,:) = sum(X(idx,:).^2,1);
    % Treat ATH as an auditory-band power allowance, distribute over bins.
    ath(idx) = N*10.^((athDB(idx)-cfg.pam.referenceSPL)/10)/bands.count(b);
end
distance = bands.centers-bands.centers'; % target row minus masker column
spreadDB = cfg.pam.lowerSlope*min(distance,0)+cfg.pam.upperSlope*max(distance,0);
masked = 10.^(spreadDB/10)*E*10^(-cfg.pam.maskingOffsetDB/10);
rawMasked = masked;
temporal = [];
if cfg.features.temporalMasking
    quietBand=zeros(B,1);
    for b=1:B
        quietBand(b)=sum(ath(bands.edges(b):bands.edges(b+1)-1));
    end
    [masked,state,temporal]=pac.temporal_mask(masked,quietBand,cfg,state);
else
    state=[];
end
threshold = zeros(size(X));
allowance = zeros(size(E));
for b = 1:B
    idx = bands.edges(b):bands.edges(b+1)-1;
    threshold(idx,:) = max(ath(idx),masked(b,:)/bands.count(b));
    allowance(b,:) = sum(threshold(idx,:),1);
end
details = struct('bandEnergy',E,'ath',ath,'spreadingDB',spreadDB, ...
    'rawMasked',rawMasked,'masked',masked,'temporal',temporal);
end
