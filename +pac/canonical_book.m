function book=canonical_book(lengths)
%CANONICAL_BOOK Validated complete binary tree for the sixteen categories.
lengths=double(lengths(:));
assert(numel(lengths)==16 && all(lengths>=1 & lengths<=15 & lengths==fix(lengths)) && ...
    sum(2.^(15-lengths))==2^15,'pac:Format','Invalid canonical Huffman lengths.');
[~,order]=sortrows([lengths (0:15)'],[1 2]); codes=zeros(16,1);
code=0; previous=lengths(order(1));
for j=1:16
    s=order(j); code=code*2^(lengths(s)-previous);
    codes(s)=code; code=code+1; previous=lengths(s);
end
children=zeros(31,2); symbols=-ones(31,1); last=1;
for s=1:16
    node=1;
    for bit=lengths(s):-1:1
        branch=bitget(uint32(codes(s)),bit)+1;
        if children(node,branch)==0, last=last+1; children(node,branch)=last; end
        node=children(node,branch);
    end
    symbols(node)=s-1;
end
book=struct('lengths',lengths,'codes',codes,'children',children,'symbols',symbols);
end
