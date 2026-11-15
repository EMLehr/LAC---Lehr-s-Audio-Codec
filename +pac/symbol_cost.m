function [cost,mode]=symbol_cost(q,w,book,zeroRun)
%SYMBOL_COST Exact v5 cost, including two-bit selector when tools are enabled.
q=q(:); n=numel(q); options=[n*w inf inf];
if ~isempty(book)
    v=abs(q); c=zeros(size(v)); nz=v>0; c(nz)=floor(log2(v(nz)))+1;
    individual=book.lengths(c+1)+c; options(2)=sum(individual);
else
    individual=repmat(w,n,1);
end
if zeroRun
    zero=q==0; runs=nnz(zero & [true;~zero(1:end-1)]);
    options(3)=runs*(1+ceil(log2(n)))+sum(1+individual(~zero));
end
[cost,which]=min(options); mode=which-1;
if ~isempty(book) || zeroRun, cost=cost+2; end
end
