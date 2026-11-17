function [width,scaleCode,q,usedBits,distortion,details]=allocate_piecewise(x,allowance,bands,budget,huffman,coreLimit,policy)
%ALLOCATE_PIECEWISE Reserve part of each atomic precision upgrade's bit cost.
% budget includes mandatory band widths, but excludes BWE parameters/framing.
[cost,D,codes]=pac.quantizer_candidates(x,bands,huffman,coreLimit);
B=numel(bands.count); width=zeros(B,1); remaining=budget-4*B;
assert(remaining>=0,'pac:Budget','No room for band widths.');
target=allowance*10^(policy.stopDB/10); held=zeros(1,3); spent=zeros(1,3);
while true
    best=-inf; chosenBand=0; chosenColumn=0; chosenReserve=0; chosenDelta=0; chosenLayer=0;
    for b=1:B
        if bands.edges(b)>coreLimit, continue; end
        current=width(b)+1; currentD=D(b,current); currentCost=cost(b,current);
        if currentD<=target(b), continue; end
        candidates=find(D(b,:)<currentD & isfinite(cost(b,:)));
        if isempty(candidates), continue; end
        % Move along the cost/distortion frontier. Never jump past several
        % precision steps to avoid the saving layers they would encounter.
        free=candidates(cost(b,candidates)<=currentCost);
        if ~isempty(free)
            [~,j]=min(D(b,free)); column=free(j);
        else
            cheapest=min(cost(b,candidates)); candidates=candidates(cost(b,candidates)==cheapest);
            [~,j]=min(D(b,candidates)); column=candidates(j);
        end
        delta=cost(b,column)-currentCost; reserve=0; layer=0;
        if delta>0
            nmr=10*log10(max(currentD,realmin)/max(allowance(b),realmin));
            [ratio,layer]=pac.saving_ratio(nmr,policy);
            if ratio==1, continue; end
            reserve=ceil(delta*ratio/(1-ratio));
        end
        charge=delta+reserve;
        if charge>remaining, continue; end
        gain=(currentD-D(b,column))/max(allowance(b),realmin);
        score=gain/max(charge,1);
        if score>best
            best=score; chosenBand=b; chosenColumn=column;
            chosenReserve=reserve; chosenDelta=delta; chosenLayer=layer;
        end
    end
    if chosenBand==0, break; end
    width(chosenBand)=chosenColumn-1;
    remaining=remaining-chosenDelta-chosenReserve;
    if chosenLayer>0
        held(chosenLayer)=held(chosenLayer)+chosenReserve;
        spent(chosenLayer)=spent(chosenLayer)+max(0,chosenDelta);
    end
end
current=sub2ind(size(D),(1:B)',width+1); distortion=D(current); scaleCode=codes(current);
usedBits=4*B+sum(cost(current)); q=zeros(1024,1);
for b=1:B
    if width(b)==0, continue; end
    idx=bands.edges(b):bands.edges(b+1)-1; step=2^((scaleCode(b)-128)/4);
    limit=2^(width(b)-1)-1; q(idx)=max(-limit,min(limit,round(x(idx)/step)));
end
details=struct('reservedBits',held,'spentBits',spent,'remainingBits',remaining, ...
    'budgetBits',budget,'bandsAboveLimit',sum(distortion(bands.edges(1:end-1)<=coreLimit)> ...
    target(bands.edges(1:end-1)<=coreLimit)));
assert(usedBits+sum(held)<=budget,'pac:Budget','Piecewise allocation exceeded virtual budget.');
end
