function [width,scaleCode,q,usedBits,distortion] = allocate(x,allowance,bands,budget,huffman,coreLimit)
%ALLOCATE Greedy distortion-reduction-per-bit across all larger precisions.
% Every active band stores an 8-bit logarithmic step and signed coefficients.
B = numel(bands.count);
if nargin<5, huffman=false; end
if nargin<6, coreLimit=1024; end
assert(budget >= 4*B,'pac:Budget','Frame budget cannot hold band widths.');
[cost,D,codes]=pac.quantizer_candidates(x,bands,huffman,coreLimit);
width=zeros(B,1);
remaining=budget-4*B;
while true
    current=sub2ind(size(D),(1:B)',width+1);
    extra=cost-cost(current);
    gain=(D(current)-D)./max(allowance,realmin);
    score=gain./extra;
    valid=(0:15)>width & extra<=remaining & extra>0 & gain>0;
    if huffman
        % Variable-length costs need not increase with precision. Accept
        % free/cost-saving distortion reductions before positive-cost buys.
        free=gain>0 & extra<=0 & isfinite(extra);
        if any(free,'all')
            score=gain; valid=free;
        else
            valid=extra<=remaining & extra>0 & gain>0;
        end
    end
    score(~valid)=-inf;
    [best,linear]=max(score(:));
    if ~isfinite(best), break; end
    [b,column]=ind2sub(size(score),linear);
    remaining=remaining-extra(b,column);
    width(b)=column-1;
end
current=sub2ind(size(D),(1:B)',width+1);
scaleCode=codes(current);
distortion=D(current);
usedBits=budget-remaining;
q=zeros(1024,1);
for b=1:B
    if width(b)==0, continue; end
    idx=bands.edges(b):bands.edges(b+1)-1;
    step=2^((scaleCode(b)-128)/4);
    limit=2^(width(b)-1)-1;
    q(idx)=max(-limit,min(limit,round(x(idx)/step)));
end
end
