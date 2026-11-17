function [masked,spreadDB,details] = spread_maskers(E,weightedEnergy,bands,cfg)
%SPREAD_MASKERS Source-level/frequency-dependent upward masking spread.
% Slope formula adapted from ITU-R BS.1387 section 2.1.7, not a full PEAQ model.
B=size(E,1); F=size(E,2); settings=cfg.pam.spreading;
fc=zeros(B,1);
for b=1:B
    fc(b)=mean(bands.frequency(bands.edges(b):bands.edges(b+1)-1));
end
levelDB=cfg.pam.referenceSPL+10*log10(max(E/cfg.hop,realmin));
levelDB=min(settings.maxLevelDB,max(settings.minLevelDB,levelDB));
upperMagnitude=24+230./fc-0.2*levelDB;
upperMagnitude=min(settings.maxUpperMagnitude,max(settings.minUpperMagnitude,upperMagnitude));
distance=bands.centers-bands.centers';
spreadDB=zeros(B,B,F); masked=zeros(B,F);
for f=1:F
    spreadDB(:,:,f)=settings.lowerSlope*min(distance,0)- ...
        max(distance,0).*upperMagnitude(:,f)';
    masked(:,f)=10.^(spreadDB(:,:,f)/10)*weightedEnergy(:,f);
end
details=struct('sourceFrequencyHz',fc,'sourceLevelDB',levelDB, ...
    'upperSlope',-upperMagnitude,'lowerSlope',settings.lowerSlope);
end
