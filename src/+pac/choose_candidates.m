function [selection,used,D,detail]=choose_candidates(candidates,a,g,budget,targetDB,policy,quality)
%CHOOSE_CANDIDATES Quality selection or finite-budget RD allocation.
B=numel(candidates); selection=ones(B,1); D=zeros(B,1); used=g.mandatory;
reserved=zeros(1,3); spent=reserved; unattainable=0;
target=a*10^(targetDB/10);
if quality
    for b=1:B
        c=candidates{b}; ok=find(c(:,4)<=target(b),1);
        if isempty(ok), ok=size(c,1); unattainable=unattainable+double(g.active(b)); end
        selection(b)=ok;
    end
else
    remaining=budget-g.mandatory;
    assert(remaining>=0,'pac:Budget','Frame cannot hold mandatory experimental fields.');
    while true
        scoreBest=-inf; bandBest=0; rowBest=0; debit=0; reserveBest=0; layerBest=0; deltaBest=0;
        for b=1:B
            c=candidates{b}; i=selection(b); options=i+1:size(c,1);
            if isempty(options), continue; end
            r=0; layer=0;
            if policy.enabled
                if c(i,4)<=a(b)*10^(policy.stopDB/10), continue; end
                [r,layer]=pac.saving_ratio(10*log10(max(c(i,4),realmin)/max(a(b),realmin)),policy);
                if r==1, continue; end
                options=options(1);
            end
            for j=options
                delta=c(j,3)-c(i,3); reserve=ceil(delta*r/(1-r)); charge=delta+reserve;
                if charge>remaining, continue; end
                score=(c(i,4)-c(j,4))/max(a(b),realmin)/max(charge,1);
                if score>scoreBest
                    scoreBest=score; bandBest=b; rowBest=j; debit=charge;
                    reserveBest=reserve; layerBest=layer; deltaBest=delta;
                end
            end
        end
        if bandBest==0, break; end
        selection(bandBest)=rowBest; remaining=remaining-debit;
        if layerBest>0
            reserved(layerBest)=reserved(layerBest)+reserveBest; spent(layerBest)=spent(layerBest)+deltaBest;
        end
    end
end
for b=1:B
    c=candidates{b}; used=used+c(selection(b),3); D(b)=c(selection(b),4);
end
detail=struct('reserved',reserved,'spent',spent,'unattainable',unattainable, ...
    'aboveTarget',nnz(D(g.active)>target(g.active)));
end
