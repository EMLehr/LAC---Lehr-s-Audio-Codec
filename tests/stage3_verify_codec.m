function report = stage3_verify_codec()
%STAGE3_VERIFY_CODEC Synthetic bitstream, allocation, and rate-control tests.
root=pac.project_root();
out=fullfile(root,'outputs','validation');
if ~isfolder(out), mkdir(out); end
rng(2718,'twister');
bands=pac.bands(); B=numel(bands.count);
cfg=codec_config();
% Exact signed-symbol and scale recovery for every supported width.
for widthValue=[0 2:15]
    w=repmat(widthValue,B,1); s=randi([0 255],B,1); q=zeros(1024,1);
    if widthValue>0
        q=randi([-2^(widthValue-1),2^(widthValue-1)-1],1024,1);
        q(1)=-2^(widthValue-1); q(end)=2^(widthValue-1)-1;
    else
        s(:)=0;
    end
    required=4*B+8*nnz(w)+sum(w.*bands.count);
    [bytes,bits]=pac.pack_frame(w,s,q,bands,ceil(required/8));
    [~,wr,sr,qr,readBits]=pac.unpack_frame(bytes,bands);
    assert(isequal(w,wr) && isequal(s,sr) && isequal(q,qr) && bits==readBits);
end
% PAM is finite on silence, has a quiet threshold, and spreads masking.
[a,T]=pac.pam(zeros(1024,1),cfg,bands);
assert(all(isfinite(T)) && all(T>0) && all(a>0));
tone=zeros(1024,1); tone(80)=10;
[~,Tm]=pac.pam(tone,cfg,bands);
assert(nnz(Tm>T)>1 && Tm(80)>T(80));
% Full file and reconstructed sample checks at all required rates.
rows=struct([]); rowIndex=0;
for signal=1:3
    L=12345;
    switch signal
        case 1, x=zeros(L,1);
        case 2, x=0.6*sin(2*pi*997*(0:L-1)'/48000);
        case 3, x=0.1*randn(L,1); x(1)=0.9; x(end)=-0.9;
    end
    fs=48000; input=fullfile(out,'synthetic.mat'); save(input,'x','fs');
    for rate=[64 96 128]
        cfg.targetKbps=rate;
        file=fullfile(out,sprintf('synthetic_%d_%d.lac',signal,rate));
        st=encode_audio(input,file,cfg);
        [y,info]=decode_audio(file,[file '.wav']);
        assert(numel(y)==L && all(isfinite(y)));
        assert(st.totalBytes==floor(L/fs*rate*1000/8));
        assert(abs(st.actualKbps-rate)<8/(L/fs)/1000);
        assert(st.paddingBits==info.paddingBits);
        assert(8*st.totalBytes==8*st.headerBytes+st.frameSideBits+st.coefficientBits+st.paddingBits);
        % Compare the decoder against encoder-side quantized coefficients.
        X=pac.analyze(x); [allowance,~,~]=pac.pam(X,cfg,bands);
        [~,frameBytes]=pac.layout(L,size(X,2),B,rate);
        Xq=zeros(size(X));
        for f=1:size(X,2)
            [w,s,q]=pac.allocate(X(:,f),allowance(:,f),bands,8*frameBytes(f));
            for b=1:B
                if w(b)==0, continue; end
                idx=bands.edges(b):bands.edges(b+1)-1;
                Xq(idx,f)=q(idx)*2^((s(b)-128)/4);
            end
        end
        expected=pac.synthesize(Xq,L);
        assert(isequal(y,expected),'Decoded coefficients disagree with encoder.');
        [wav,fsWav]=audioread([file '.wav']);
        assert(fsWav==fs && isequal(wav,double(single(y))),'Float WAV is not sample-faithful.');
        if signal==1, assert(all(y==0)); end
        if signal==2, assert(10*log10(sum(x.^2)/sum((x-y).^2))>20); end
        rowIndex=rowIndex+1;
        row=struct('signal',signal,'rate',rate,'actualKbps',st.actualKbps, ...
            'maxDecoderDifference',max(abs(y-expected)));
        if rowIndex==1, rows=row; else, rows(rowIndex)=row; end
    end
end
% Every approved feature is implemented and accepts a logical true flag.
base=codec_config(); names=fieldnames(base.features);
for k=1:numel(names)
    cfg=codec_config(); cfg.features.(names{k})=true;
    pac.validate_config(cfg);
end
% Too-short inputs are supported by transform, but cannot fit fixed-rate headers.
mustFail(@() pac.layout(1,2,B,64),'pac:Budget');
% A cut-off file and unknown flags must be rejected.
fid=fopen(file,'r'); raw=fread(fid,inf,'*uint8'); fclose(fid);
bad=fullfile(out,'invalid.lac');
fid=fopen(bad,'w'); fwrite(fid,raw(1:end-1),'uint8'); fclose(fid);
mustFail(@() decode_audio(bad),'pac:Format');
raw(7)=1;
fid=fopen(bad,'w'); fwrite(fid,raw,'uint8'); fclose(fid);
mustFail(@() decode_audio(bad),'pac:Format');
report=struct('symbolWidthCases',15,'roundTrips',rows, ...
    'silentPAM',true,'spreading',true,'acceptsImplementedFeatures',true, ...
    'rejectsTruncationAndUnknownFlags',true);
pac.write_json(fullfile(out,'codec.json'),report);
fprintf('PASS: 15 symbol widths, 9 file round trips, budgets, WAV fidelity, and format guards.\n');
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
