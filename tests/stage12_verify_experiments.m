function report=stage12_verify_experiments()
%STAGE12_VERIFY_EXPERIMENTS Reconstruction, exact symbols, all new switches.
root=pac.project_root(); out=fullfile(root,'outputs','validation','experiments');
if ~isfolder(out), mkdir(out); end
rng(12001,'twister'); worst=0; transformCases=0;
for L=[1 17 1024 1025 4096 9001]
    F=ceil(L/1024)+1; schedules={zeros(1,F)};
    if F>=3
        schedules{end+1}=[1 2*ones(1,F-2) 3]; %#ok<AGROW>
        m=zeros(1,F); m(1:3)=[1 2 3]; schedules{end+1}=m; %#ok<AGROW>
    end
    signals={zeros(L,1),randn(L,1),sin(2*pi*997*(0:L-1)'/48000)};
    for pos=unique([1 min(L,449) min(L,1024) min(L,1473) L])
        impulse=zeros(L,1); impulse(pos)=1; signals{end+1}=impulse; %#ok<AGROW>
    end
    for schedule=schedules
        for signal=signals
            x=signal{1}; X=pac.analyze_switch(x,schedule{1}); y=pac.synthesize_switch(X,L,schedule{1});
            err=max(abs(x-y)); assert(err<1e-10); worst=max(worst,err); transformCases=transformCases+1;
        end
    end
end
mustFail(@() pac.check_sequence([0 2 0]),'pac:Format');
mustFail(@() pac.canonical_book(ones(16,1)),'pac:Format');
% Exact signed extrema, zeros, sparse runs, fixed and learned books.
long=pac.coding_bands(false); short=pac.coding_bands(false,128); symbolCases=0;
for mode=[0 2]
    g=pac.frame_geometry(mode,false,long,short); w=8*ones(numel(g.count),1); s=128*ones(size(w));
    q=randi([-128 127],1024,1); q(1:900)=0; q(end-1:end)=[-128;127];
    books={[],pac.huffman_book(),pac.train_book(pac.category_counts(q,w,g))};
    for h=1:3
        for zr=[false true]
            flags=16+double(h>1)+4*double(zr)+64*double(h>1);
            [bytes,bits]=pac.pack_experimental(w,s,q,g,mode,zeros(4,2,g.units),books{h},zr,false,h==3);
            [decoded,readBits]=pac.unpack_experimental(bytes,long,short,flags,books{h},1);
            assert(isequal(q,decoded) && bits==readBits); symbolCases=symbolCases+1;
        end
    end
end
% Local book comparison uses identical symbols, with its full 16-byte header.
g=pac.frame_geometry(0,false,long,short); w=15*ones(numel(g.count),1); q=3*ones(1024,1); q(end)=16000;
s=128*ones(size(w)); fixed=pac.huffman_book(); learned=pac.train_book(pac.category_counts(q,w,g));
a=pac.pack_experimental(w,s,q,g,0,zeros(4,2),fixed,false,false,false);
b=pac.pack_experimental(w,s,q,g,0,zeros(4,2),learned,false,false,true);
assert(numel(b)<numel(a));
% Expanded candidate set cannot require more bits at the same feasible target.
cfg=codec_config(); e=cfg.experiments; xcoef=randn(1024,1); a=pac.pam(xcoef,cfg,long);
c0=pac.search_candidates(xcoef,g,fixed,e); e.smartQuantizer=true;
c1=pac.search_candidates(xcoef,g,fixed,e);
[~,bits0,~,d0]=pac.choose_candidates(c0,a,g,inf,0,cfg.allocation,true);
[~,bits1,~,d1]=pac.choose_candidates(c1,a,g,inf,0,cfg.allocation,true);
assert(d0.unattainable==0 && d1.unattainable==0 && bits1<=bits0);
% All 32 new switch combinations with four coding-tool combinations, both rates.
fs=48000; x=zeros(4096,1); x(1700:2800)=.2*randn(1101,1); input=fullfile(out,'input.mat'); save(input,'x','fs');
options={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'};
roundTrips=0; shortFrames=0; localBooks=0;
for mask=0:31
    for coding=0:3
        cfg=pac.pam_config(mod(mask+coding*7,16));
        cfg.features.huffman=bitand(coding,1)~=0; cfg.features.bandwidthExtension=bitand(coding,2)~=0;
        for k=1:5, cfg.experiments.(options{k})=bitget(mask,k)~=0; end
        cfg.experiments.huffmanScope='window';
        for rate={'cbr','vbr'}
            cfg.rateMode=rate{1}; cfg.reservoir.enabled=strcmp(rate{1},'cbr');
            cfg.allocation.enabled=mod(mask,3)==0; cfg.allocation.savedNumerator(3)=3; cfg.allocation.savedDenominator(3)=4;
            path=fullfile(out,sprintf('case_%02d_%d_%s.lac',mask,coding,rate{1}));
            st=encode_audio(input,path,cfg); [y,info]=decode_audio(path);
            assert(numel(y)==numel(x) && all(isfinite(y)) && info.totalBytes==st.totalBytes);
            assert(st.totalBytes*8==st.headerBytes*8+st.framingBits+st.frameSideBits+st.coefficientBits+st.paddingBits);
            if strcmp(rate{1},'cbr'), assert(st.actualKbps==96); end
            if mask>0
                d=load([path '.diagnostics.mat']);
                assert(isequal(y,pac.synthesize_switch(d.plan.Xq,numel(x),d.modes)));
                assert(st.totalBytes<=st.fixedBookReferenceBytes);
                if ~strcmp(rate{1},'vbr'), assert(st.usefulBytes<=st.fixedBookReferenceUsefulBytes); end
                shortFrames=shortFrames+st.shortFrames; localBooks=localBooks+st.windowBooksUsed;
                assert(all(d.plan.after>=0 & d.plan.after<=st.reservoirCapacityBytes));
                assert(d.plan.after(end)==0);
            end
            roundTrips=roundTrips+1;
        end
    end
end
assert(shortFrames>0);
% Tiny/silent VBR and impossible fixed budgets; no accidental nonfinite PE.
cfg=codec_config(); cfg.rateMode='vbr';
for k=1:5, cfg.experiments.(options{k})=true; end
for L=[1 127 1025]
    x=zeros(L,1); save(input,'x','fs'); path=fullfile(out,sprintf('silent_%d.lac',L));
    st=encode_audio(input,path,cfg); y=decode_audio(path); assert(all(y==0) && numel(y)==L && ~st.fileBookUsed);
end
cfg.rateMode='cbr'; x=0; save(input,'x','fs');
mustFail(@() encode_audio(input,fullfile(out,'too_short.lac'),cfg),'pac:Budget');
% Invalid bitstream framing, header, modes, trailing data and padding.
raw=pac.file_bytes(path); bad=fullfile(out,'invalid.lac'); variants={raw(1:end-1),[raw;uint8(0)]};
changed=raw; changed(end)=255; variants{end+1}=changed;
changed=raw; changed(7:8)=255; variants{end+1}=changed;
H=st.headerBytes; changed=raw; changed(H+3)=255; variants{end+1}=changed;
for k=1:numel(variants)
    fid=fopen(bad,'w'); fwrite(fid,variants{k},'uint8'); fclose(fid); mustFail(@() decode_audio(bad),'pac:Format');
end
report=struct('transformCases',transformCases,'maxTransformError',worst,'symbolCases',symbolCases, ...
    'roundTrips',roundTrips,'shortFrames',shortFrames,'localBooksInMatrix',localBooks, ...
    'smartCandidateDominance',true,'bookOverheadGuard',true,'malformedInputs',true);
pac.write_json(fullfile(out,'verification.json'),report);
fprintf('PASS: %d transform cases, %d symbol cases, %d codec combinations.\n',transformCases,symbolCases,roundTrips);
end

function mustFail(action,id)
try
    action();
catch exception
    assert(strcmp(exception.identifier,id),'Unexpected error %s: %s',exception.identifier,exception.message); return
end
error('pac:Test','Expected %s.',id);
end
