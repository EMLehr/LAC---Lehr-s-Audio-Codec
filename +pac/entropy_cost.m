function [bits,useHuffman] = entropy_cost(q,width)
%ENTROPY_COST Exact coefficient cost, excluding step and one-bit selector.
category=zeros(size(q)); nonzero=q~=0;
category(nonzero)=floor(log2(abs(q(nonzero))))+1;
book=pac.huffman_book();
huff=sum(book.lengths(category+1)+category);
raw=numel(q)*width; useHuffman=huff<raw; bits=min(huff,raw);
end
