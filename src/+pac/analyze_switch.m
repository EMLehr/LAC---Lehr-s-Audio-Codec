function X=analyze_switch(x,modes)
%ANALYZE_SWITCH Eight 256-sample short transforms replace one long transform.
pac.check_sequence(modes); F=ceil(numel(x)/1024)+1;
assert(numel(modes)==F,'pac:Length','Window sequence length mismatch.');
xp=[zeros(1024,1);x(:);zeros(F*1024-numel(x),1)]; X=zeros(1024,F);
for f=1:F
    [A,w]=pac.switch_basis(modes(f));
    if modes(f)==2
        for u=1:8
            idx=(f-1)*1024+448+(u-1)*128+(1:256);
            X((u-1)*128+(1:128),f)=A'*(xp(idx).*w);
        end
    else
        idx=(f-1)*1024+(1:2048); X(:,f)=A'*(xp(idx).*w);
    end
end
end
