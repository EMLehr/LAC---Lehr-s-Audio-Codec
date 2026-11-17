function [preMask,postMask,onsets] = onset_windows(x,fs)
%ONSET_WINDOWS Fixed source-only detector, independent of codec outputs.
% 1 ms block power > -60 dB, >=12 dB rise over preceding 10 ms,
% 100 ms refractory period. Score 20 ms before and after each detected onset.
H=round(fs/1000); F=floor(numel(x)/H);
power=mean(reshape(x(1:F*H),H,F).^2,1)';
previous=filter(ones(10,1)/10,1,[0;power(1:end-1)]);
candidates=find(power>1e-6 & power>=max(previous,1e-10)*10^(12/10));
preMask=false(size(x)); postMask=preMask; onsets=zeros(0,1);
last=-inf; span=round(0.020*fs);
for k=1:numel(candidates)
    sample=(candidates(k)-1)*H+1;
    if sample-last<0.100*fs || sample<=span || sample+span-1>numel(x), continue; end
    onsets(end+1,1)=sample; %#ok<AGROW>
    preMask(sample-span:sample-1)=true;
    postMask(sample:sample+span-1)=true;
    last=sample;
end
end
