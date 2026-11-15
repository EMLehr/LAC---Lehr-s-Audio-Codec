function [fraction,layer]=saving_ratio(nmrDB,policy)
%SAVING_RATIO Boundaries belong to the lower-error layer, including equality.
layer=find(nmrDB<=policy.boundariesDB,1,'last');
fraction=0;
if isempty(layer), layer=0; else
    fraction=policy.savedNumerator(layer)/policy.savedDenominator(layer);
end
end
