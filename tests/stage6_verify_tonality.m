function report = stage6_verify_tonality()
%STAGE6_VERIFY_TONALITY Flatness behavior, masker weighting, and combinations.
cfg=codec_config(); cfg.features.tonalMaskers=true;
pac.validate_config(cfg); bands=pac.bands(); B=numel(bands.count);
% Equal-energy flat and concentrated spectra must receive different treatment.
flat=ones(1024,1); peaked=zeros(1024,1);
for b=1:B, peaked(bands.edges(b))=sqrt(bands.count(b)); end
[af,of]=pac.tonality(flat,bands,cfg.pam.tonal);
[ap,op]=pac.tonality(peaked,bands,cfg.pam.tonal);
assert(all(af==0) && all(ap==1));
assert(all(op>of),'Tonal maskers must receive the more conservative offset.');
[~,~,df]=pac.pam(flat,cfg,bands); [~,~,dp]=pac.pam(peaked,cfg,bands);
assert(all(df.rawMasked>dp.rawMasked),'Equal-energy noise-like maskers should mask more.');
% Sign and overall amplitude cannot change this power-based classification.
[as,os]=pac.tonality(-1e-8*peaked,bands,cfg.pam.tonal);
assert(isequal(ap,as) && isequal(op,os));
% A real windowed sinusoid should be more tonal than white noise near its peak.
rng(602,'twister'); fs=48000; n=(0:12287)';
tone=pac.analyze(0.5*sin(2*pi*997*n/fs));
noise=pac.analyze(0.2*randn(size(n)));
band=find(bands.frequency(bands.edges(1:end-1))<=997,1,'last');
[at,~,~]=pac.tonality(tone(:,3:end-2),bands,cfg.pam.tonal);
[an,~,~]=pac.tonality(noise(:,3:end-2),bands,cfg.pam.tonal);
assert(mean(at(band,:))>mean(an(band,:))+0.15,'Tone/noise separation failed.');
% Source weighting must propagate through spreading, not follow target tonality.
X=zeros(1024,2); sourceBand=12;
idx=bands.edges(sourceBand):bands.edges(sourceBand+1)-1;
X(idx,1)=1; X(idx(1),2)=sqrt(numel(idx));
[~,~,d]=pac.pam(X,cfg,bands);
ratio=d.rawMasked(:,1)./d.rawMasked(:,2);
assert(max(ratio)-min(ratio)<1e-10 && all(ratio>1));
% Silence remains the same with any combination of the two switches.
base=codec_config(); [a0,T0]=pac.pam(zeros(1024,8),base,bands);
for temporal=[false true]
    cfg.features.temporalMasking=temporal;
    [a,T,detail]=pac.pam(zeros(1024,8),cfg,bands);
    assert(isequal(a0,a) && isequal(T0,T) && all(detail.tonal.alpha==0,'all'));
end
% Combined processing is stable across chunks and resets between streams.
X=[noise,tone,zeros(1024,8)];
[a,T,~,s]=pac.pam(X,cfg,bands);
[a1,T1,~,s1]=pac.pam(X(:,1:9),cfg,bands);
[a2,T2,~,s2]=pac.pam(X(:,10:end),cfg,bands,s1);
assert(max(abs(a-[a1 a2]),[],'all')<1e-12 && max(abs(T-[T1 T2]),[],'all')<1e-12);
assert(max(abs(s.history-s2.history),[],'all')<1e-12);
[ar,Tr]=pac.pam(X,cfg,bands); assert(isequal(a,ar) && isequal(T,Tr));
% All-off ignores tonal parameters; equal offsets can reproduce baseline PAM.
off=base; off.pam.tonal.noiseOffsetDB=0;
[ab,Tb]=pac.pam(X,base,bands); [ao,To]=pac.pam(X,off,bands);
assert(isequal(ab,ao) && isequal(Tb,To));
equal=base; equal.features.tonalMaskers=true;
equal.pam.tonal.noiseOffsetDB=29;
[ae,Te]=pac.pam(X,equal,bands);
assert(max(abs(ae-ab),[],'all')<1e-12 && max(abs(Te-Tb),[],'all')<1e-12);

% Both new mode combinations round-trip through the existing binary decoder.
out=fullfile(pac.project_root(),'outputs','validation');
if ~isfolder(out), mkdir(out); end
x=0.4*sin(2*pi*997*n/fs)+0.03*randn(size(n)); x(1:3000)=0;
input=fullfile(out,'tonality_mixture.mat'); save(input,'x','fs');
changed=false(2,3);
for k=1:3
    rates=[64 96 128]; base.targetKbps=rates(k);
    path0=fullfile(out,sprintf('tone_base_%d.lac',rates(k)));
    st0=encode_audio(input,path0,base);
    for j=1:2
        cfg=base; cfg.features.tonalMaskers=true; cfg.features.temporalMasking=j==2;
        path=fullfile(out,sprintf('tone_mode%d_%d.lac',j,rates(k)));
        st=encode_audio(input,path,cfg); [y,info]=decode_audio(path);
        assert(st.totalBytes==st0.totalBytes && st.actualKbps==st0.actualKbps);
        assert(numel(y)==numel(x) && all(isfinite(y)) && info.paddingBits==st.paddingBits);
        if j==1, assert(strcmp(st.model,'tonal')); else, assert(strcmp(st.model,'tonal_temporal')); end
        changed(j,k)=~isequal(pac.file_bytes(path),pac.file_bytes(path0));
        X=pac.analyze(x); allowance=pac.pam(X,cfg,bands); Xq=zeros(size(X));
        [~,bytes]=pac.layout(numel(x),size(X,2),B,rates(k));
        for f=1:size(X,2)
            [w,c,q]=pac.allocate(X(:,f),allowance(:,f),bands,8*bytes(f));
            for b=1:B
                if w(b)==0, continue; end
                idx=bands.edges(b):bands.edges(b+1)-1;
                Xq(idx,f)=q(idx)*2^((c(b)-128)/4);
            end
        end
        assert(isequal(y,pac.synthesize(Xq,numel(x))));
    end
end
assert(all(any(changed,2)));
report=struct('equalEnergySeparation',true,'scaleAndSignInvariant',true, ...
    'toneAlpha',mean(at(band,:)),'noiseAlpha',mean(an(band,:)), ...
    'sourceMaskerSpreading',true,'silentAllCombinations',true, ...
    'combinedStateAndReset',true,'disabledEquivalence',true, ...
    'matchedRateRoundTrips',6,'bitstreamChanged',changed);
pac.write_json(fullfile(out,'tonality.json'),report);
fprintf('PASS: tonality behavior, source weighting, state, bypass, and 6 matched-rate round trips.\n');
end
