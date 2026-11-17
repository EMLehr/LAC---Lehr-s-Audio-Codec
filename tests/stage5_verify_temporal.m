function report = stage5_verify_temporal()
%STAGE5_VERIFY_TEMPORAL Synthetic behavior, stream state, and on/off tests.
cfg=codec_config(); cfg.features.temporalMasking=true;
pac.validate_config(cfg);
bands=pac.bands(); B=numel(bands.count);
out=fullfile(pac.project_root(),'outputs','validation');
if ~isfolder(out), mkdir(out); end

% Isolated mask history: a masker must affect the future, not the past.
post=cfg; post.pam.temporal.preEchoControl=false;
raw=ones(B,18); raw(:,4)=100;
quiet=1e-6*ones(B,1);
[m,~,details]=pac.temporal_mask(raw,quiet,post,[]);
assert(isequal(m(:,1:4),raw(:,1:4)),'Post-masking altered past/current masker.');
assert(all(m(:,5)>raw(:,5)),'Post-masking did not persist after the masker.');
assert(all(diff(m(1,5:end))<=0),'Post-masking release should not grow.');
assert(isequal(m(:,9:end),raw(:,9:end)),'Old masker outlived the finite horizon.');
assert(all(m(:)<=max(raw(:),quiet(1))*10^(cfg.pam.temporal.postMaxBoostDB/10)));
assert(abs(details.maxHistoryLagSeconds-4*1024/48000)<1e-12);

% Onset protection: reduce a sudden rise, but adapt to a sustained signal.
pre=cfg; pre.pam.temporal.postMasking=false;
raw=ones(B,10); raw(:,4:end)=100;
mp=pac.temporal_mask(raw,quiet,pre,[]);
assert(all(mp(:,4)<raw(:,4)) && all(mp(:,5)<raw(:,5)));
assert(isequal(mp(:,6:end),raw(:,6:end)),'Pre-echo control failed to recover.');
assert(isequal(pac.temporal_mask(ones(B,10),quiet,cfg,[]),ones(B,10)));

% Real PAM: silence remains unchanged; explicit state matches whole-sequence use.
rng(831,'twister');
X=randn(1024,20).*[0 0 0 .1 1 1 .2 .02 .01 .01 zeros(1,10)];
[a,T,~,state]=pac.pam(X,cfg,bands);
[a1,T1,~,s1]=pac.pam(X(:,1:7),cfg,bands);
[a2,T2,~,s2]=pac.pam(X(:,8:end),cfg,bands,s1);
assert(max(abs(a-[a1 a2]),[],'all')<1e-12);
assert(max(abs(T-[T1 T2]),[],'all')<1e-12);
assert(max(abs(state.history-s2.history),[],'all')<1e-12);
baseline=codec_config();
[ab,Tb]=pac.pam(zeros(1024,10),baseline,bands);
[at,Tt]=pac.pam(zeros(1024,10),cfg,bands);
assert(isequal(ab,at) && isequal(Tb,Tt));
assert(all(isfinite(T),'all') && all(T>0,'all'));
% Prior calls must not leak into the next file.
[aAgain,TAgain]=pac.pam(X,cfg,bands);
assert(isequal(a,aAgain) && isequal(T,TAgain));
% Prefix causality and feature/subcomponent bypass equivalence.
[ap,Tp]=pac.pam(X(:,1:8),cfg,bands);
assert(max(abs(a(:,1:8)-ap),[],'all')<1e-12);
assert(max(abs(T(:,1:8)-Tp),[],'all')<1e-12);
bypass=cfg; bypass.pam.temporal.postMasking=false; bypass.pam.temporal.preEchoControl=false;
[a0,T0]=pac.pam(X,baseline,bands); [ax,Tx]=pac.pam(X,bypass,bands);
assert(isequal(a0,ax) && isequal(T0,Tx));
% An irrelevant temporal configuration cannot change the disabled path.
disabled=baseline; disabled.pam.temporal.postMaxBoostDB=45;
[ad,Td]=pac.pam(X,disabled,bands,state);
assert(isequal(a0,ad) && isequal(T0,Td));

% An abrupt, decaying synthetic burst exercises actual allocation and storage.
fs=48000; x=zeros(24000,1);
idx=(1:4800)'; x(6000+idx)=0.5*sin(2*pi*997*idx/fs).*exp(-idx/1800);
input=fullfile(out,'temporal_burst.mat'); save(input,'x','fs');
files=cell(2,3); changes=false(1,3);
for k=1:3
    rates=[64 96 128]; rate=rates(k);
    baseline.targetKbps=rate; cfg.targetKbps=rate;
    files{1,k}=fullfile(out,sprintf('burst_baseline_%d.lac',rate));
    files{2,k}=fullfile(out,sprintf('burst_temporal_%d.lac',rate));
    s0=encode_audio(input,files{1,k},baseline);
    st=encode_audio(input,files{2,k},cfg);
    [y,info]=decode_audio(files{2,k});
    assert(numel(y)==numel(x) && all(isfinite(y)));
    assert(s0.totalBytes==st.totalBytes && s0.actualKbps==st.actualKbps);
    assert(info.actualKbps==rate && strcmp(st.model,'temporal'));
    changes(k)=~isequal(pac.file_bytes(files{1,k}),pac.file_bytes(files{2,k}));
    % The unchanged decoder must recover precisely the chosen quantized data.
    X=pac.analyze(x); allowances=pac.pam(X,cfg,bands);
    [~,frameBytes]=pac.layout(numel(x),size(X,2),B,rate);
    Xq=zeros(size(X));
    for f=1:size(X,2)
        [w,c,q]=pac.allocate(X(:,f),allowances(:,f),bands,frameBytes(f)*8);
        for b=1:B
            if w(b)==0, continue; end
            bins=bands.edges(b):bands.edges(b+1)-1;
            Xq(bins,f)=q(bins)*2^((c(b)-128)/4);
        end
    end
    assert(isequal(y,pac.synthesize(Xq,numel(x))));
end
assert(any(changes),'Temporal option did not affect burst allocation.');
report=struct('postDecayAndExpiry',true,'onsetProtectionAndRecovery',true, ...
    'silence',true,'stateChunking',true,'resetBetweenFiles',true,'causality',true, ...
    'bypassEquivalence',true,'burstBitstreamChanged',changes, ...
    'equalActualRates',true,'exactDecoderReconstruction',true);
pac.write_json(fullfile(out,'temporal.json'),report);
fprintf('PASS: temporal behavior, state, causality, bypass, and three matched-rate round trips.\n');
end
