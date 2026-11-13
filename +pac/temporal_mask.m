function [masked,state,details] = temporal_mask(raw,quietBand,cfg,state)
%TEMPORAL_MASK Causal post-masking and pre-echo threshold control.
% History contains RAW simultaneous masking, never the feedback-adjusted result.
% No future frames, short windows, bit borrowing, or decoder state are used.
t=cfg.pam.temporal;
dt=cfg.hop/cfg.sampleRate;
lagCount=floor((t.postMaxMs/1000)/dt+1e-12);
keep=max(2,lagCount);
if nargin<4 || isempty(state)
    state=struct('history',zeros(size(raw,1),0));
end
validateattributes(raw,{'double'},{'real','finite','2d','nonnegative'});
validateattributes(quietBand,{'double'},{'column','finite','positive','numel',size(raw,1)});
assert(isstruct(state) && isfield(state,'history') && ...
    size(state.history,1)==size(raw,1) && size(state.history,2)<=keep && ...
    all(isfinite(state.history(:))) && all(state.history(:)>=0), ...
    'pac:State','Invalid temporal state. Reset state when starting a new file/configuration.');
masked=zeros(size(raw)); post=zeros(size(raw)); caps=inf(size(raw));
residual=zeros(size(raw));
for f=1:size(raw,2)
    current=raw(:,f);
    history=state.history;
    if t.postMasking && lagCount>0 && ~isempty(history)
        count=min(lagCount,size(history,2));
        decay=10.^(-t.postDecayDBPerSecond*dt*(1:count)/10);
        residual(:,f)=max(history(:,1:count).*decay,[],2);
        current=min(max(current,residual(:,f)), ...
            max(raw(:,f),quietBand)*10^(t.postMaxBoostDB/10));
    end
    post(:,f)=current;
    if t.preEchoControl && ~isempty(history)
        cap=max(history(:,1),quietBand)*10^(t.riseOneFrameDB/10);
        if size(history,2)>=2
            cap=min(cap,max(history(:,2),quietBand)*10^(t.riseTwoFramesDB/10));
        end
        caps(:,f)=cap;
        current=min(current,cap);
    end
    masked(:,f)=current;
    state.history=[raw(:,f),history(:,1:min(keep-1,size(history,2)))];
end
details=struct('postResidual',residual,'postMasked',post,'preEchoCap',caps, ...
    'postRaised',post>raw,'preEchoLimited',masked<post, ...
    'maxHistoryLagSeconds',lagCount*dt);
end
