function report=stage11_verify_allocation()
%STAGE11_VERIFY_ALLOCATION Piecewise ratios, reservoir conservation, compatibility.
root=pac.project_root(); out=fullfile(root,'outputs','validation','allocation');
if ~isfolder(out), mkdir(out); end
cfg=codec_config(); p=cfg.allocation;
assert(pac.saving_ratio(-5,p)==0 && pac.saving_ratio(-6,p)==.25);
assert(pac.saving_ratio(-9,p)==.5 && pac.saving_ratio(-15,p)==1);
p.savedNumerator(3)=3; p.savedDenominator(3)=4;
assert(pac.saving_ratio(-40,p)==.75);
rng(11001,'twister'); bands=pac.bands(); xcoef=randn(1024,1);
[a,~]=pac.pam(xcoef,cfg,bands);
[~,~,~,reference]=pac.allocate_vbr(xcoef,a,bands,false,1024,p.stopDB);
[~,~,~,used,~,pd]=pac.allocate_piecewise(xcoef,a,bands,reference,false,1024,p);
assert(used+sum(pd.reservedBits)+pd.remainingBits==reference);
assert(pd.spentBits(3)>0 && pd.reservedBits(3)>=3*pd.spentBits(3));
for k=1:3
    r=p.savedNumerator(k)/p.savedDenominator(k);
    assert(pd.reservedBits(k)>=pd.spentBits(k)*r/(1-r));
end
p0=p; p0.savedNumerator(:)=0;
[~,~,~,bits,D]=pac.allocate_piecewise(xcoef,a,bands,reference,false,1024,p0);
assert(bits==reference && all(D<=a*10^(p.stopDB/10)));
% Exact all-mode reconstruction, accounting, and causal bucket limits.
fs=48000; n=(0:16383)'; x=.15*randn(size(n))+.2*sin(2*pi*997*n/fs); x(1:7000)=0;
input=fullfile(out,'mixture.mat'); save(input,'x','fs'); X=pac.analyze(x); roundTrips=0; borrowed=0;
for mask=0:63
    cfg=pac.pam_config(mod(mask,16)); cfg.features.huffman=bitand(mask,16)~=0;
    cfg.features.bandwidthExtension=bitand(mask,32)~=0; cfg.allocation=p; cfg.allocation.enabled=true;
    cb=pac.coding_bands(cfg.features.bandwidthExtension); [a,~]=pac.pam(X,cfg,cb);
    extra=40*double(cfg.features.bandwidthExtension); limit=1024;
    if extra~=0, limit=512; end
    for mode={'cbr','vbr'}
        cfg.rateMode=mode{1}; cfg.reservoir.enabled=strcmp(mode{1},'cbr');
        file=fullfile(out,sprintf('mode_%02d_%s.lac',mask,mode{1}));
        st=encode_audio(input,file,cfg); [y,info]=decode_audio(file);
        assert(all(isfinite(y)) && numel(y)==numel(x) && info.paddingBits==st.paddingBits);
        assert(st.totalBytes*8==st.headerBytes*8+st.framingBits+st.frameSideBits+st.coefficientBits+st.paddingBits);
        d=load([file '.diagnostics.mat']); Xq=zeros(size(X));
        if cfg.reservoir.enabled
            assert(st.actualKbps==96 && info.version==4 && d.reservoirAfter(end)==0);
            assert(all(d.reservoirAfter>=0) && all(d.reservoirAfter<=st.reservoirCapacityBytes));
            assert(isequal(d.reservoirBefore,[0;d.reservoirAfter(1:end-1)]));
            assert(all(d.frameBytes'==d.nominal'+d.reservoirBefore-d.reservoirAfter));
            borrowed=borrowed+sum(d.borrowedBytes);
        else
            assert(info.version==3 && st.paddingBits<=7*size(X,2));
        end
        for f=1:size(X,2)
            if cfg.reservoir.enabled
                budget=8*(d.nominal(f)+d.reservoirBefore(f))-extra;
            else
                [~,~,~,budget]=pac.allocate_vbr(X(:,f),a(:,f),cb,cfg.features.huffman,limit,p.stopDB);
            end
            [w,s,q]=pac.allocate_piecewise(X(:,f),a(:,f),cb,budget,cfg.features.huffman,limit,p);
            for b=1:numel(w)
                idx=cb.edges(b):cb.edges(b+1)-1;
                if w(b)>0, Xq(idx,f)=q(idx)*2^((s(b)-128)/4); end
            end
            if extra~=0, Xq(:,f)=pac.bwe_reconstruct(Xq(:,f),pac.bwe_parameters(X(:,f)),f); end
        end
        assert(isequal(y,pac.synthesize(Xq,numel(x)))); roundTrips=roundTrips+1;
    end
end
assert(borrowed>0);
% Capacity zero, startup without credit, and silence overflow/final draining.
cfg=codec_config(); cfg.reservoir.enabled=true;
for capacity=[0 2 8]
    cfg.reservoir.capacityFrames=capacity; x=zeros(16384,1); save(input,'x','fs');
    file=fullfile(out,sprintf('silent_%d.lac',capacity)); st=encode_audio(input,file,cfg);
    [y,info]=decode_audio(file); d=load([file '.diagnostics.mat']);
    assert(all(y==0) && st.actualKbps==96 && info.paddingBits==st.paddingBits);
    assert(d.reservoirBefore(1)==0 && d.reservoirAfter(end)==0);
    if capacity==0, assert(all(d.reservoirAfter==0)); else, assert(st.reservoirPeakBytes>0); end
end
% Reservoir malformed sizes/capacity and padding; unknown policy settings.
raw=pac.file_bytes(file); bad=fullfile(out,'invalid.lac');
mutations={raw(1:end-1),[raw;uint8(0)]};
changed=raw; changed(89:92)=255; mutations{end+1}=changed;
changed=raw; changed(93:94)=255; mutations{end+1}=changed;
changed=raw; changed(end)=1; mutations{end+1}=changed;
for k=1:numel(mutations)
    fid=fopen(bad,'w'); fwrite(fid,mutations{k},'uint8'); fclose(fid);
    mustFail(@() decode_audio(bad),'pac:Format');
end
cfg.rateMode='vbr'; mustFail(@() pac.validate_config(cfg),'pac:Config');
cfg.reservoir.enabled=false; cfg.allocation.savedNumerator(1)=5;
mustFail(@() pac.validate_config(cfg),'pac:Config');
cfg=codec_config(); cfg.allocation.boundariesDB=[-9 -6 -15];
mustFail(@() pac.validate_config(cfg),'pac:Config');
% Prior CBR v1/v2 and VBR v3 content must be unaffected with controls off.
regressions=0;
for mask=[0 15]
    for flags=0:3
        cfg=pac.pam_config(mask); cfg.features.huffman=bitand(flags,1)~=0;
        cfg.features.bandwidthExtension=bitand(flags,2)~=0;
        for mode={'cbr','vbr'}
            cfg.rateMode=mode{1}; model=pac.model_name(cfg);
            if strcmp(mode{1},'cbr')
                group='baseline_pam'; if mask==15, group='all_pam'; end
                original=fullfile(root,'outputs','coding_features',group,['harpsichord_' model '_96k.lac']);
            else
                original=fullfile(root,'outputs','vbr',['harpsichord_' model '_vbr_+0dB.lac']);
            end
            output=fullfile(out,sprintf('regression_%d_%d_%s.lac',mask,flags,mode{1}));
            encode_audio(fullfile(root,'outputs','prepared','harpsichord.mat'),output,cfg);
            assert(isequal(pac.file_bytes(output),pac.file_bytes(original))); regressions=regressions+1;
        end
    end
end
report=struct('exactRoundTrips',roundTrips,'featureCombinations',64,'ratioBoundaries',true, ...
    'partialBottomLayer',true,'allZeroRatios',true,'reservoirBorrowedBytes',borrowed, ...
    'reservoirConservation',true,'malformedStreams',true,'offModeByteRegressions',regressions);
pac.write_json(fullfile(out,'verification.json'),report);
fprintf('PASS: %d piecewise round trips, bucket conservation, ratios and %d byte regressions.\n',roundTrips,regressions);
end

function mustFail(action,id)
try
    action();
catch exception
    assert(strcmp(exception.identifier,id),'Unexpected error: %s',exception.message); return
end
error('pac:Test','Expected %s was not raised.',id);
end
