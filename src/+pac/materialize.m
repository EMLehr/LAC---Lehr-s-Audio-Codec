function [w,s,q]=materialize(x,g,candidates,selection)
B=numel(candidates); w=zeros(B,1); s=w; q=zeros(1024,1);
for b=1:B
    row=candidates{b}(selection(b),:); w(b)=row(1); s(b)=row(2);
    if w(b)==0, continue; end
    idx=g.edges(b):g.edges(b+1)-1; step=2^((s(b)-128)/4); limit=2^(w(b)-1)-1;
    q(idx)=max(-limit,min(limit,round(x(idx)/step)));
end
end
