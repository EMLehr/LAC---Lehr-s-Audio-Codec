function [allowance,baselineAllowance] = map_allowances(threshold,bands,enhanced)
%MAP_ALLOWANCES Sum (baseline) or n times harmonic mean of bin thresholds.
% The harmonic choice matches the sum for uniform thresholds, and gives more
% weight to vulnerable bins. It is a scalar approximation, not a bin guarantee.
B=numel(bands.count); F=size(threshold,2);
allowance=zeros(B,F); baselineAllowance=zeros(B,F);
for b=1:B
    idx=bands.edges(b):bands.edges(b+1)-1;
    values=threshold(idx,:);
    baselineAllowance(b,:)=sum(values,1);
    if enhanced
        % Scale by the minimum to avoid overflow in 1/threshold.
        smallest=min(values,[],1);
        allowance(b,:)=numel(idx)^2*smallest./sum(smallest./values,1);
    else
        allowance(b,:)=baselineAllowance(b,:);
    end
end
end
