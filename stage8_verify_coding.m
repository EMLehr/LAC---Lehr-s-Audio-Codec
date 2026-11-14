function report = stage8_verify_coding()
%STAGE8_VERIFY_CODING Huffman exactness, BWE parameters, format, combinations.
root=fileparts(mfilename('fullpath')); out=fullfile(root,'outputs','validation');
if ~isfolder(out), mkdir(out); end
rng(8001,'twister'); bands=pac.bands(); B=numel(bands.count);
book=pac.huffman_book();
assert(abs(sum(2.^(-book.lengths))-1)<1e-14);
% Known codebook fixture guards format stability, not merely self-consistency.
assert(isequal(book.lengths',[1 3 3 4 4 5 5 6 6 7 8 8 8 8 8 8]));
assert(isequal(book.codes',[0 4 5 12 13 28 29 60 61 124 250:255]));
saved=0; huffmanCases=0; rawCases=0;
for width=2:15
    for sparse=[false true]
        w=width*ones(B,1); s=randi([0 255],B,1);
        q=randi([-2^(width-1),2^(width-1)-1],1024,1);
        if sparse, q(1:950)=0; end
        q(end-1)=-2^(width-1); q(end)=2^(width-1)-1;
        expected=4*B;
        for b=1:B
            idx=bands.edges(b):bands.edges(b+1)-1;
            [cost,h]=pac.entropy_cost(q(idx),width);
            expected=expected+9+cost; huffmanCases=huffmanCases+h; rawCases=rawCases+~h;
        end
        [bytes,bits,side,payload]=pac.pack_frame(w,s,q,bands,ceil(expected/8)+1,1);
        [~,wr,sr,qr,readBits]=pac.unpack_frame(bytes,bands,1);
        assert(isequal(w,wr) && isequal(s,sr) && isequal(q,qr));
        assert(bits==readBits && bits==expected && bits==side+payload);
        if sparse, saved=saved+4*B+8*B+1024*width-bits; end
        bytes(end)=1; mustFail(@() pac.unpack_frame(bytes,bands,1),'pac:Format');
    end
end
assert(saved>0 && huffmanCases>0 && rawCases>0);
% Golden two-coefficient stream: width=4, step=128, Huffman, q=[0;-1].
tiny=struct('edges',[1;3],'count',2); q=zeros(1024,1); q(2)=-1;
[bytes,bits]=pac.pack_frame(4,128,q,tiny,3,1);
assert(bits==18 && isequal(bytes,uint8([72;10;64])));
% Force a truncated Huffman prefix, and a category outside the stored width.
mustFail(@() pac.unpack_frame(uint8([72;10]),tiny,1),'pac:Format');
mustFail(@() pac.unpack_frame(uint8([40;15;240]),tiny,1),'pac:Format');
% Mirroring, envelope fidelity, deterministic fallback, silence and no RNG leak.
source=zeros(1024,1); source(1:512)=randn(512,1);
source(513:1024)=.02*randn(512,1); params=pac.bwe_parameters(source);
state=rng; reconstructed=pac.bwe_reconstruct(source,params,7); assert(isequal(state,rng));
assert(isequal(source(1:512),reconstructed(1:512)));
assert(isequal(reconstructed,pac.bwe_reconstruct(source,params,7)));
for g=1:4
    idx=512+(g-1)*128+(1:128);
    errorDB=20*log10(norm(reconstructed(idx))/norm(source(idx)));
    assert(abs(errorDB)<=.5000001);
end
params(:,2)=0; mirrored=pac.bwe_reconstruct(source,params,7);
assert(abs(dot(mirrored(513:640)/norm(mirrored(513:640)), ...
    source(512:-1:385)/norm(source(512:-1:385)))-1)<1e-12);
fallback=pac.bwe_reconstruct(zeros(1024,1),params,7);
assert(all(isfinite(fallback)) && any(fallback(513:end)));
assert(all(pac.bwe_reconstruct(source,zeros(4,2),7)==[source(1:512);zeros(512,1)]));
% All 64 six-switch combinations, with exact encoder-side reconstruction.
fs=48000; n=(0:12287)'; x=.25*sin(2*pi*997*n/fs)+.01*randn(size(n));
x(1:2000)=0; x(7000)=.8; x(end)=-.7;
input=fullfile(out,'coding_mixture.mat'); save(input,'x','fs'); X=pac.analyze(x);
roundTrips=0;
for pamMask=0:15
    for flags=0:3
        % All combinations at 96; the extremes also cover 64 and 128.
        rates=96; if ismember(pamMask,[0 15]), rates=[64 96 128]; end
        for rate=rates
            cfg=pac.pam_config(pamMask,rate);
            cfg.features.huffman=bitand(flags,1)~=0;
            cfg.features.bandwidthExtension=bitand(flags,2)~=0;
            file=fullfile(out,sprintf('coding_%02d_%d_%d.lac',pamMask,flags,rate));
            stats=encode_audio(input,file,cfg); [y,info]=decode_audio(file);
            assert(info.flags==flags && info.version==1+(flags>0));
            assert(info.actualKbps==rate && numel(y)==numel(x) && all(isfinite(y)));
            assert(stats.paddingBits==info.paddingBits);
            assert(8*stats.totalBytes==8*stats.headerBytes+stats.frameSideBits+ ...
                stats.coefficientBits+stats.paddingBits);
            cb=pac.coding_bands(cfg.features.bandwidthExtension); ext=40*double(cfg.features.bandwidthExtension);
            limit=1024; if ext~=0, limit=512; end
            [a,~]=pac.pam(X,cfg,cb);
            [~,frameBytes]=pac.layout(numel(x),size(X,2),numel(cb.count),rate,ext);
            Xq=zeros(size(X));
            for f=1:size(X,2)
                [w,s,q]=pac.allocate(X(:,f),a(:,f),cb,8*frameBytes(f)-ext,cfg.features.huffman,limit);
                for b=1:numel(cb.count)
                    idx=cb.edges(b):cb.edges(b+1)-1;
                    if w(b), Xq(idx,f)=q(idx)*2^((s(b)-128)/4); end
                end
                if ext~=0
                    assert(all(w(cb.edges(1:end-1)>512)==0));
                    Xq(:,f)=pac.bwe_reconstruct(Xq(:,f),pac.bwe_parameters(X(:,f)),f);
                end
            end
            assert(isequal(y,pac.synthesize(Xq,numel(x)))); roundTrips=roundTrips+1;
        end
    end
end
% Silent full files for every non-PAM mode.
x=zeros(12288,1); save(input,'x','fs');
for flags=1:3
    cfg=codec_config(); cfg.features.huffman=bitand(flags,1)~=0;
    cfg.features.bandwidthExtension=bitand(flags,2)~=0;
    file=fullfile(out,sprintf('coding_silent_%d.lac',flags)); encode_audio(input,file,cfg);
    assert(all(decode_audio(file)==0));
end
% Arbitrary lengths and high-only content exercise BWE's empty-core fallback.
x=.1*sin(2*pi*18000*(0:12344)'/fs); save(input,'x','fs');
for flags=1:3
    cfg=codec_config(); cfg.features.huffman=bitand(flags,1)~=0;
    cfg.features.bandwidthExtension=bitand(flags,2)~=0;
    file=fullfile(out,sprintf('coding_high_only_%d.lac',flags)); stats=encode_audio(input,file,cfg);
    [y,info]=decode_audio(file);
    assert(numel(y)==numel(x) && all(isfinite(y)) && any(y));
    assert(stats.totalBytes==floor(numel(x)/fs*96000/8) && info.paddingBits==stats.paddingBits);
end
% Version/flags, truncation, and missing core boundary are rejected.
raw=pac.file_bytes(file); bad=fullfile(out,'coding_invalid.lac');
write_bad(raw(1:end-1)); mustFail(@() decode_audio(bad),'pac:Format');
changed=raw; changed(7)=4; write_bad(changed); mustFail(@() decode_audio(bad),'pac:Format');
changed=raw; changed(5)=1; write_bad(changed); mustFail(@() decode_audio(bad),'pac:Format');
cb=pac.coding_bands(true); location=find(cb.edges==513);
changed=raw; changed(37+2*(location-1))=1; write_bad(changed);
mustFail(@() decode_audio(bad),'pac:Format');
report=struct('huffmanSymbolWidths',14,'huffmanBandCases',huffmanCases, ...
    'rawFallbackBandCases',rawCases,'sparseFixtureSavedBits',saved, ...
    'bweEnvelopeMaxErrorDB',.5,'allSwitchCombinations',64,'exactRoundTrips',roundTrips, ...
    'silence',true,'malformedFiles',true,'goldenHuffmanBytes',true);
pac.write_json(fullfile(out,'coding_features.json'),report);
fprintf('PASS: Huffman, BWE, 64 combinations, %d exact round trips and format guards.\n',roundTrips);
    function write_bad(bytes)
        fid=fopen(bad,'w'); guard=onCleanup(@() fclose(fid));
        fwrite(fid,bytes,'uint8');
    end
end

function mustFail(action,id)
try
    action();
catch exception
    assert(strcmp(exception.identifier,id),'Unexpected error: %s',exception.message);
    return
end
error('pac:Test','Expected %s was not raised.',id);
end
