function [modes,d]=transient_plan(x,X,allowance,bands,e)
%TRANSIENT_PLAN Energy attacks plus optional PE rise, without a learned model.
F=size(X,2); E=zeros(size(allowance));
for b=1:numel(bands.count), E(b,:)=sum(X(bands.edges(b):bands.edges(b+1)-1,:).^2,1); end
pe=.5*bands.count.*max(0,log2(max(E,realmin)./max(allowance,realmin)));
density=sum(pe,1)/1024;
xp=[zeros(1024,1);x(:);zeros(F*1024-numel(x),1)];
energy=mean(reshape(xp,128,[]).^2,1); ratio=zeros(size(energy));
for k=2:numel(energy)
    ratio(k)=energy(k)/max([1e-10 energy(max(1,k-2):k-1)]);
end
attack=zeros(1,F); wanted=false(1,F);
for k=2:numel(energy)
    pos=(k-1)*128+1; f=min(F,max(1,floor((pos-449)/1024)+1));
    threshold=e.attackRatio;
    if e.perceptualEntropy && density(f)>max(.5,1.25*density(max(1,f-1)))
        threshold=max(2,threshold/2);
    end
    if ratio(k)<threshold || energy(k)<1e-9, continue; end
    wanted(f)=true;
    % Protect every long frame overlapping the detected attack, including start.
    for j=max(1,f-1):min(F,f+1)
        if pos>=(j-1)*1024+1 && pos<=(j+1)*1024
            attack(j)=max(attack(j),min(1,log2(ratio(k))/log2(e.attackRatio)));
        end
    end
end
modes=zeros(1,F);
if e.variableWindows && F>=3
    wanted([1 F])=false;
    for f=2:F-1
        if wanted(f-1) && wanted(f+1), wanted(f)=true; end
    end
    modes(wanted)=2;
    for f=find(wanted)
        if ~wanted(f-1), modes(f-1)=1; end
        if ~wanted(f+1), modes(f+1)=3; end
    end
end
pac.check_sequence(modes);
d=struct('perceptualEntropy',pe,'peBitsPerCoefficient',density,'attack',attack,'energyRatio',ratio);
end
