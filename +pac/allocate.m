function [width,scaleCode,q,usedBits,distortion] = allocate(x,allowance,bands,budget,huffman,coreLimit)
%ALLOCATE Greedy distortion-reduction-per-bit across all larger precisions.
% Every active band stores an 8-bit logarithmic step and signed coefficients.
B = numel(bands.count);
if nargin<5, huffman=false; end
if nargin<6, coreLimit=1024; end
assert(budget >= 4*B,'pac:Budget','Frame budget cannot hold band widths.');
cost = inf(B,16); D = inf(B,16); codes = zeros(B,16);
cost(:,1)=0;
for b = 1:B
    idx = bands.edges(b):bands.edges(b+1)-1;
    v = x(idx);
    D(b,1)=sum(v.^2);
    if idx(1)>coreLimit, continue; end
    peak = max(abs(v));
    for w = 2:15
        qmax = 2^(w-1)-1;
        c = max(0,ceil(4*log2(max(peak/qmax,2^-32)))+128);
        assert(c <= 255,'pac:Range','Coefficient exceeds quantizer range.');
        step = 2^((c-128)/4);
        values = max(-qmax,min(qmax,round(v/step)));
        cost(b,w+1) = 8+numel(v)*w;
        if huffman, cost(b,w+1)=9+pac.entropy_cost(values,w); end
        D(b,w+1)=sum((v-values*step).^2);
        codes(b,w+1)=c;
    end
end
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
