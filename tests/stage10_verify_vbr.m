function report=stage10_verify_vbr()
%STAGE10_VERIFY_VBR Quality allocation, variable framing, backward compatibility.
root=pac.project_root(); out=fullfile(root,'outputs','validation','vbr');
if ~isfolder(out), mkdir(out); end
rng(10001,'twister'); fs=48000; n=(0:12344)';
x=.12*randn(size(n))+.2*sin(2*pi*997*n/fs); x(1:3500)=0; x(end)=-.8;
input=fullfile(out,'mixture.mat'); save(input,'x','fs'); X=pac.analyze(x);
roundTrips=0;
for mask=0:63
    cfg=pac.pam_config(mod(mask,16)); cfg.rateMode='vbr';
    cfg.features.huffman=bitand(mask,16)~=0; cfg.features.bandwidthExtension=bitand(mask,32)~=0;
    bands=pac.coding_bands(cfg.features.bandwidthExtension); [a,~]=pac.pam(X,cfg,bands);
    extra=40*double(cfg.features.bandwidthExtension); limit=1024;
    if cfg.features.bandwidthExtension, limit=512; end
    sizes=zeros(1,3);
    for k=1:3
        cfg.vbr.distortionDB=6*(k-2);
        file=fullfile(out,sprintf('mode_%02d_q%d.lac',mask,k));
        st=encode_audio(input,file,cfg); [y,info]=decode_audio(file);
        assert(info.version==3 && info.targetKbps==0 && strcmp(info.rateMode,'vbr'));
        assert(numel(y)==numel(x) && all(isfinite(y)) && info.paddingBits==st.paddingBits);
        assert(st.totalBytes*8==st.headerBytes*8+st.framingBits+ ...
            st.frameSideBits+st.coefficientBits+st.paddingBits);
        assert(st.paddingBits<=7*size(X,2) && st.framingBits==16*size(X,2));
        assert(abs(st.sizeReductionPercent-100*(1-st.totalBytes/(2*numel(x))))<1e-12);
        Xq=zeros(size(X)); misses=0;
        for f=1:size(X,2)
            [w,s,q,bits,D,m]=pac.allocate_vbr(X(:,f),a(:,f),bands, ...
                cfg.features.huffman,limit,cfg.vbr.distortionDB);
            misses=misses+m;
            [cost,candidateD]=pac.quantizer_candidates(X(:,f),bands,cfg.features.huffman,limit);
            for b=1:numel(w)
                idx=bands.edges(b):bands.edges(b+1)-1;
                if idx(1)<=limit
                    feasible=candidateD(b,:)<=a(b,f)*10^(cfg.vbr.distortionDB/10);
                    if any(feasible)
                        assert(cost(b,w(b)+1)==min(cost(b,feasible)));
                        assert(D(b)<=a(b,f)*10^(cfg.vbr.distortionDB/10));
                    end
                end
                if w(b)>0, Xq(idx,f)=q(idx)*2^((s(b)-128)/4); end
            end
            params=zeros(4,2);
            if cfg.features.bandwidthExtension
                params=pac.bwe_parameters(X(:,f)); Xq(:,f)=pac.bwe_reconstruct(Xq(:,f),params,f);
            end
            [~,packedBits]=pac.pack_frame(w,s,q,bands,ceil((bits+extra)/8),info.flags,params);
            assert(packedBits==bits+extra);
        end
        assert(isequal(y,pac.synthesize(Xq,numel(x))) && misses==st.coreTargetMisses);
        sizes(k)=st.totalBytes; roundTrips=roundTrips+1;
    end
    assert(all(diff(sizes)<=0),'Looser quality target increased file size.');
end
% Silence, arbitrary tiny lengths, and explicitly unattainable targets.
cfg=codec_config(); cfg.rateMode='vbr';
for L=[1 1023 1024 1025]
    x=zeros(L,1); save(input,'x','fs');
    file=fullfile(out,sprintf('silence_%d.lac',L)); st=encode_audio(input,file,cfg);
    [y,info]=decode_audio(file); assert(numel(y)==L && all(y==0));
    assert(st.totalBytes==88+(ceil(L/1024)+1)*15 && info.paddingBits<8*info.frames);
end
bands=pac.bands();
[~,~,~,~,~,misses]=pac.allocate_vbr(randn(1024,1),realmin*ones(25,1),bands,false,1024,-30);
assert(misses>0);
raw=pac.file_bytes(file); header=88; bad=fullfile(out,'invalid.lac');
mutations={raw(1:end-1),[raw;uint8(0)]};
changed=raw; changed(header+1:header+2)=0; mutations{end+1}=changed;
changed=raw; changed(header+1:header+2)=255; mutations{end+1}=changed;
changed=raw; changed(29)=1; mutations{end+1}=changed;
changed=raw; changed(7)=4; mutations{end+1}=changed;
for k=1:numel(mutations)
    fid=fopen(bad,'w'); fwrite(fid,mutations{k},'uint8'); fclose(fid);
    mustFail(@() decode_audio(bad),'pac:Format');
end
% Extra zero bytes inside a frame are not permitted in VBR.
changed=[raw(1:header+15);uint8(0);raw(header+16:end)]; changed(header+1)=14;
fid=fopen(bad,'w'); fwrite(fid,changed,'uint8'); fclose(fid);
mustFail(@() decode_audio(bad),'pac:Format');
% Existing CBR v1 and v2 bytes must remain unchanged, for both PAM groups.
regressions=0;
for mask=[0 15]
    group='baseline_pam'; if mask==15, group='all_pam'; end
    for flags=0:3
        for source={'harpsichord','castanets'}
            cfg=pac.pam_config(mask,96); cfg.features.huffman=bitand(flags,1)~=0;
            cfg.features.bandwidthExtension=bitand(flags,2)~=0;
            name=sprintf('%s_%s_96k.lac',source{1},pac.model_name(cfg));
            original=fullfile(root,'outputs','coding_features',group,name);
            output=fullfile(out,name);
            encode_audio(fullfile(root,'outputs','prepared',[source{1} '.mat']),output,cfg);
            assert(isequal(pac.file_bytes(original),pac.file_bytes(output)));
            regressions=regressions+1;
        end
    end
end
report=struct('combinations',64,'exactRoundTrips',roundTrips,'monotonicQualitySizes',true, ...
    'minimalCandidateCosts',true,'tinySilentLengths',4,'unattainableTargetsReported',true, ...
    'malformedFramesRejected',true,'cbrByteRegressions',regressions);
pac.write_json(fullfile(out,'verification.json'),report);
fprintf('PASS: %d VBR round trips, 64 combinations, framing guards, and %d CBR byte regressions.\n',roundTrips,regressions);
end

function mustFail(action,id)
try
    action();
catch exception
    assert(strcmp(exception.identifier,id),'Unexpected error: %s',exception.message); return
end
error('pac:Test','Expected %s was not raised.',id);
end
