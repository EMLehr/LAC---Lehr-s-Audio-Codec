function parameters = bwe_parameters(X)
%BWE_PARAMETERS Four high-band RMS envelopes and two-bit noise fractions.
parameters=zeros(4,2);
for g=1:4
    idx=512+(g-1)*128+(1:128); power=X(idx).^2; rmsValue=sqrt(mean(power));
    if rmsValue==0, continue; end
    c=round(20*log10(rmsValue))+160;
    assert(c<=255,'pac:Range','BWE envelope exceeds representable range.');
    if c<=0, continue; end
    parameters(g,1)=c;
    flatness=exp(mean(log(max(power,mean(power)*1e-12))))/mean(power);
    parameters(g,2)=min(3,max(0,round(3*flatness)));
end
end
