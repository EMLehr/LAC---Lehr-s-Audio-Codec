function [cost,D,codes] = quantizer_candidates(x,bands,huffman,coreLimit)
%QUANTIZER_CANDIDATES Shared CBR/VBR quantizers and exact representation costs.
B=numel(bands.count);
cost=inf(B,16); D=inf(B,16); codes=zeros(B,16); cost(:,1)=0;
for b=1:B
    idx=bands.edges(b):bands.edges(b+1)-1; v=x(idx);
    D(b,1)=sum(v.^2);
    if idx(1)>coreLimit, continue; end
    peak=max(abs(v));
    for w=2:15
        qmax=2^(w-1)-1;
        c=max(0,ceil(4*log2(max(peak/qmax,2^-32)))+128);
        assert(c<=255,'pac:Range','Coefficient exceeds quantizer range.');
        step=2^((c-128)/4); values=max(-qmax,min(qmax,round(v/step)));
        cost(b,w+1)=8+numel(v)*w;
        if huffman, cost(b,w+1)=9+pac.entropy_cost(values,w); end
        D(b,w+1)=sum((v-values*step).^2); codes(b,w+1)=c;
    end
end
end
