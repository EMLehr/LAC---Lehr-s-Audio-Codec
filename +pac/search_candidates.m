function candidates=search_candidates(x,g,book,e)
%SEARCH_CANDIDATES Preserve the old step and expand search only when enabled.
candidates=cell(numel(g.count),1);
offsets=0;
if e.smartQuantizer, offsets=[0 -1:-1:-e.stepRadius 1:e.stepRadius]; end
for b=1:numel(g.count)
    v=x(g.edges(b):g.edges(b+1)-1); rows=[0 0 0 sum(v.^2)];
    if g.active(b) && any(v)
        for w=2:15
            limit=2^(w-1)-1;
            base=max(0,ceil(4*log2(max(max(abs(v))/limit,2^-32)))+128);
            assert(base<=255,'pac:Range','Coefficient exceeds quantizer range.');
            steps=unique(min(255,max(0,base+offsets)),'stable');
            for c=steps
                step=2^((c-128)/4); q=max(-limit,min(limit,round(v/step)));
                cost=8+pac.symbol_cost(q,w,book,e.zeroRun);
                rows(end+1,:)=[w c cost sum((v-q*step).^2)]; %#ok<AGROW>
            end
        end
    end
    % Keep the lowest distortion at each cost, then the strict RD frontier.
    rows=sortrows(rows,[3 4 1 2]); keep=false(size(rows,1),1); best=inf;
    for k=1:size(rows,1)
        if rows(k,4)<best, keep(k)=true; best=rows(k,4); end
    end
    candidates{b}=rows(keep,:);
end
end
