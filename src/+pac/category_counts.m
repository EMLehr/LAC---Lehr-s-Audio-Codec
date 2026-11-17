function counts=category_counts(q,width,g)
counts=zeros(16,1);
for b=find(width(:)'>0)
    v=abs(q(g.edges(b):g.edges(b+1)-1)); c=zeros(size(v));
    nz=v>0; c(nz)=floor(log2(v(nz)))+1;
    counts=counts+accumarray(c+1,1,[16 1]);
end
end
