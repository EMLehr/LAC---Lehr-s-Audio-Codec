function [alpha,offsetDB,flatnessDB] = tonality(X,bands,settings)
%TONALITY Continuous tonal/noise estimate from within-band spectral flatness.
% Geometric / arithmetic power mean, measured in the log domain. Zero-energy
% bands have alpha=0 and contribute no masker energy. No time smoothing.
B=numel(bands.count); F=size(X,2);
alpha=zeros(B,F); flatnessDB=zeros(B,F);
for b=1:B
    idx=bands.edges(b):bands.edges(b+1)-1;
    power=X(idx,:).^2;
    average=mean(power,1);
    active=average>0;
    if ~any(active), continue; end
    normalized=power(:,active)./average(active);
    % Relative floor avoids log(0) without creating a signal-level dependence.
    flatnessDB(b,active)=min(0,10*mean(log10(max(normalized,1e-12)),1));
    alpha(b,active)=min(1,max(0,(settings.noiseFlatnessDB-flatnessDB(b,active))/ ...
        (settings.noiseFlatnessDB-settings.toneFlatnessDB)));
end
offsetDB=settings.noiseOffsetDB+alpha*(settings.toneOffsetDB-settings.noiseOffsetDB);
end
