function report = stage7_verify_pam()
%STAGE7_VERIFY_PAM Spreading, harmonic mapping, and all 16 PAM combinations.
cfg=pac.pam_config(4); pac.validate_config(cfg); bands=pac.bands(); B=numel(bands.count);
% Increasing masker level broadens upward spread but not downward spread.
E=repmat([1e-5 1],B,1);
[~,S,d]=pac.spread_maskers(E,E,bands,cfg);
assert(all(d.upperSlope(:,2)>=d.upperSlope(:,1)));
assert(any(d.upperSlope(:,2)>d.upperSlope(:,1)));
assert(all(d.upperSlope(:)<0) && all(S(:)<=0));
for f=1:2, assert(all(diag(S(:,:,f))==0)); end
lower=triu(true(B),1); upper=tril(true(B),-1);
first=S(:,:,1); second=S(:,:,2);
assert(isequal(first(lower),second(lower)) && all(second(upper)>=first(upper)));
assert(d.upperSlope(1,1)<d.upperSlope(end,1),'Frequency dependence missing.');
[silent,Szero]=pac.spread_maskers(zeros(B,4),zeros(B,4),bands,cfg);
assert(all(silent==0,'all') && all(isfinite(Szero),'all'));
% Known example: [1 1 9 9], sum=20, n*harmonicMean=7.2.
testBands=struct('edges',[1;5],'count',4);
[h,s]=pac.map_allowances([1;1;9;9],testBands,true);
assert(abs(h-7.2)<1e-12 && s==20);
[h,s]=pac.map_allowances(3*ones(4,2),testBands,true);
assert(isequal(h,s));
rng(7001,'twister'); T=10.^(-20+40*rand(1024,5));
[h,s]=pac.map_allowances(T,bands,true);
assert(all(h<=s.*(1+1e-12),'all'));
for b=1:B
    idx=bands.edges(b):bands.edges(b+1)-1;
    assert(all(h(b,:)>=numel(idx)*min(T(idx,:),[],1)*(1-1e-12)));
end
% Mapping changes only band allowances, never the global masking curves.
X=randn(1024,15).*logspace(-4,0,15);
base=codec_config(); [a0,T0]=pac.pam(X,base,bands);
mapping=pac.pam_config(8); [am,Tm]=pac.pam(X,mapping,bands);
assert(isequal(T0,Tm) && any(am<a0,'all'));
base.pam.spreading.lowerSlope=10;
[aoff,Toff]=pac.pam(X,base,bands);
assert(isequal(a0,aoff) && isequal(T0,Toff));

fs=48000; n=(0:12287)'; x=.35*sin(2*pi*997*n/fs)+.025*randn(size(n));
x(1:2500)=0; x(7000:7200)=x(7000:7200)+.2;
out=fullfile(pac.project_root(),'outputs','validation');
if ~isfolder(out), mkdir(out); end
input=fullfile(out,'all_pam_mixture.mat'); save(input,'x','fs');
X=pac.analyze(x); exact=0;
for mask=0:15
    cfg=pac.pam_config(mask); pac.validate_config(cfg);
    [a,T,~,state]=pac.pam(X,cfg,bands);
    assert(all(isfinite(a),'all') && all(a>0,'all') && all(T>0,'all'));
    [a1,T1,~,s1]=pac.pam(X(:,1:5),cfg,bands);
    [a2,T2,~,s2]=pac.pam(X(:,6:end),cfg,bands,s1);
    assert(max(abs(a-[a1 a2]),[],'all')<1e-10);
    assert(max(abs(T-[T1 T2]),[],'all')<1e-10);
    if cfg.features.temporalMasking
        assert(max(abs(state.history-s2.history),[],'all')<1e-10);
    end
    [az,Tz]=pac.pam(zeros(1024,6),cfg,bands);
    assert(all(isfinite(az),'all') && all(az>0,'all') && all(Tz>0,'all'));
    for rate=[64 96 128]
        cfg.targetKbps=rate;
        path=fullfile(out,sprintf('pam_%02d_%d.lac',mask,rate));
        st=encode_audio(input,path,cfg); [y,info]=decode_audio(path);
        assert(info.actualKbps==rate && numel(y)==numel(x) && all(isfinite(y)));
        assert(st.paddingBits==info.paddingBits && strcmp(st.model,pac.model_name(cfg)));
        [~,bytes]=pac.layout(numel(x),size(X,2),B,rate); Xq=zeros(size(X));
        for f=1:size(X,2)
            [w,c,q]=pac.allocate(X(:,f),a(:,f),bands,8*bytes(f));
            for b=1:B
                if w(b)==0, continue; end
                idx=bands.edges(b):bands.edges(b+1)-1;
                Xq(idx,f)=q(idx)*2^((c(b)-128)/4);
            end
        end
        assert(isequal(y,pac.synthesize(Xq,numel(x)))); exact=exact+1;
    end
end
report=struct('spreadingLevelAndFrequency',true,'spreadingSilence',true, ...
    'mappingKnownExample',7.2,'mappingBoundsAndUniformEquivalence',true, ...
    'mappingPreservesGlobalCurve',true,'disabledSpreadingEquivalence',true, ...
    'combinations',16,'exactRoundTrips',exact,'stateChunking',true);
pac.write_json(fullfile(out,'final_pam.json'),report);
fprintf('PASS: spreading, mapping, all 16 PAM combinations and %d exact round trips.\n',exact);
end
