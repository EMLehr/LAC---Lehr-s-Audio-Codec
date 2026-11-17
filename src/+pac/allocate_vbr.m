function [width,scaleCode,q,usedBits,distortion,misses] = allocate_vbr(x,allowance,bands,huffman,coreLimit,distortionDB)
%ALLOCATE_VBR Least-cost candidate meeting each directly coded band's target.
[cost,D,codes]=pac.quantizer_candidates(x,bands,huffman,coreLimit);
B=numel(bands.count); width=zeros(B,1); misses=0;
target=allowance*10^(distortionDB/10);
for b=1:B
    if bands.edges(b)>coreLimit, continue; end
    feasible=find(D(b,:)<=target(b) & isfinite(cost(b,:)));
    if isempty(feasible)
        misses=misses+1; feasible=find(D(b,:)==min(D(b,:)));
    end
    [~,best]=min(cost(b,feasible)); width(b)=feasible(best)-1;
end
current=sub2ind(size(D),(1:B)',width+1);
scaleCode=codes(current); distortion=D(current); usedBits=4*B+sum(cost(current));
q=zeros(1024,1);
for b=1:B
    if width(b)==0, continue; end
    idx=bands.edges(b):bands.edges(b+1)-1;
    step=2^((scaleCode(b)-128)/4); limit=2^(width(b)-1)-1;
    q(idx)=max(-limit,min(limit,round(x(idx)/step)));
end
end
