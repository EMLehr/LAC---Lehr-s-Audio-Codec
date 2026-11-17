function y=synthesize_switch(X,L,modes)
%SYNTHESIZE_SWITCH Transition-aware TDAC and original length restoration.
pac.check_sequence(modes); F=size(X,2);
assert(size(X,1)==1024 && F==ceil(L/1024)+1 && numel(modes)==F,'pac:Format','Invalid switched transform size.');
y=zeros((F+1)*1024,1);
for f=1:F
    [A,w]=pac.switch_basis(modes(f));
    if modes(f)==2
        for u=1:8
            idx=(f-1)*1024+448+(u-1)*128+(1:256);
            y(idx)=y(idx)+(A*X((u-1)*128+(1:128),f)).*w;
        end
    else
        idx=(f-1)*1024+(1:2048); y(idx)=y(idx)+(A*X(:,f)).*w;
    end
end
y=y(1024+(1:L));
end
