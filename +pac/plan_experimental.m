function plan=plan_experimental(X,frames,modes,L,cfg,book,customBook)
%PLAN_EXPERIMENTAL Complete byte-accounted allocation, before writing a file.
e=pac.experiment_settings(cfg); [policy,reservoir]=pac.allocation_settings(cfg);
[rateMode,target]=pac.rate_settings(cfg); vbr=strcmp(rateMode,'vbr');
if policy.enabled, target=policy.stopDB; elseif reservoir.enabled, target=reservoir.targetDB; end
bwe=cfg.features.bandwidthExtension; F=size(X,2);
longBands=pac.coding_bands(bwe); shortBands=pac.coding_bands(bwe,128);
shortB=0; if e.variableWindows, shortB=numel(shortBands.count); end
H=42+2*(numel(longBands.count)+1)+16*double(customBook);
if shortB>0, H=H+2*(shortB+1); end
nominal=zeros(1,F); capacity=0;
if ~vbr
    pool=floor(L/48000*cfg.targetKbps*1000/8)-H-2*F;
    assert(pool>=0,'pac:Budget','Header exceeds target size.');
    nominal=diff(floor((0:F)*pool/F));
    minimum=cellfun(@(p) ceil(p.geometry.mandatory/8),frames);
    assert(all(nominal>=minimum),'pac:Budget','Target cannot fit experimental frame metadata.');
    if reservoir.enabled, capacity=floor(reservoir.capacityFrames*pool/F); end
    assert(max(nominal)+capacity<=65535,'pac:Budget','Frame capacity exceeds uint16.');
end
payload=cell(1,F); selections=cell(1,F); counts=zeros(16,1); credit=0; Xq=zeros(size(X));
used=zeros(F,1); side=used; coefficient=used; lengths=used; before=used; after=used;
borrowed=used; localBooks=false(F,1); localSavings=used; misses=used; violations=used;
reserved=zeros(F,3); spent=reserved; error=zeros(F,1);
for f=1:F
    p=frames{f}; g=p.geometry; a=p.allowance;
    c=pac.search_candidates(X(:,f),g,book,e);
    [s,qualityBits,~,detail]=pac.choose_candidates(c,a,g,inf,target,policy,true);
    misses(f)=detail.unattainable;
    if policy.enabled
        budget=qualityBits;
        if ~vbr, budget=8*(nominal(f)+credit); end
        [s,~,~,detail]=pac.choose_candidates(c,a,g,budget,target,policy,false);
    elseif ~vbr && (~reservoir.enabled || qualityBits>8*(nominal(f)+credit))
        [s,~,~,detail]=pac.choose_candidates(c,a,g,8*(nominal(f)+credit),target,policy,false);
    end
    reserved(f,:)=detail.reserved; spent(f,:)=detail.spent;
    [w,scale,q]=pac.materialize(X(:,f),g,c,s);
    counts=counts+pac.category_counts(q,w,g);
    [bytes,used(f),side(f),coefficient(f)]=pac.pack_experimental(w,scale,q,g,modes(f),p.parameters,book,e.zeroRun,bwe,false);
    if e.fileHuffman && strcmp(e.huffmanScope,'window')
        local=pac.train_book(pac.category_counts(q,w,g));
        [alternative,bits,si,co]=pac.pack_experimental(w,scale,q,g,modes(f),p.parameters,local,e.zeroRun,bwe,true);
        % Compare COMPLETE whole-byte payloads, including sixteen book bytes.
        if numel(alternative)<numel(bytes)
            localSavings(f)=numel(bytes)-numel(alternative); localBooks(f)=true;
            bytes=alternative; used(f)=bits; side(f)=si; coefficient(f)=co;
        end
    end
    for b=1:numel(w)
        if w(b)>0
            idx=g.edges(b):g.edges(b+1)-1; Xq(idx,f)=q(idx)*2^((scale(b)-128)/4);
        end
    end
    if bwe
        for u=1:g.units
            idx=(u-1)*g.N+(1:g.N); Xq(idx,f)=pac.bwe_reconstruct(Xq(idx,f),p.parameters(:,:,u),(f-1)*8+u);
        end
    end
    D=zeros(numel(w),1);
    for b=1:numel(w)
        idx=g.edges(b):g.edges(b+1)-1; D(b)=sum((X(idx,f)-Xq(idx,f)).^2);
    end
    violations(f)=nnz(D>a*10^(target/10)); error(f)=sum(D./max(a,realmin));
    minimum=numel(bytes); before(f)=credit;
    if ~vbr
        available=nominal(f)+credit;
        assert(minimum<=available,'pac:Budget','Experimental allocation overdraw.');
        borrowed(f)=max(0,minimum-nominal(f));
        if reservoir.enabled, credit=min(capacity,available-minimum); else, credit=0; end
        if f==F, credit=0; end
        lengths(f)=available-credit; bytes(end+1:lengths(f),1)=0;
    else
        lengths(f)=minimum;
    end
    assert(lengths(f)<=65535,'pac:Budget','Experimental frame too large.');
    after(f)=credit; payload{f}=bytes; selections{f}=struct('width',w,'scale',scale,'q',q);
end
plan=struct('headerBytes',H,'frameBytes',lengths,'payload',{payload},'used',used, ...
    'side',side,'coefficient',coefficient,'nominal',nominal,'capacityBytes',capacity, ...
    'before',before,'after',after,'borrowed',borrowed,'counts',counts,'book',book, ...
    'customBook',customBook,'localBooks',localBooks,'localSavingsBytes',localSavings, ...
    'coreTargetMisses',misses,'violations',violations,'reserved',reserved,'spent',spent, ...
    'targetDB',target,'Xq',Xq,'selections',{selections},'normalizedError',sum(error));
plan.totalBytes=H+2*F+sum(lengths);
plan.usefulBytes=H+2*F+sum(ceil(used/8));
end
