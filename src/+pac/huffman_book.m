function book = huffman_book()
%HUFFMAN_BOOK Version-2 fixed canonical category codebook (symbols 0:15).
% Integer design weights, not trained on the development or held-out audio.
persistent cached
if ~isempty(cached), book=cached; return; end
weights=[128 64 32 24 16 12 8 6 4 3 2 1 1 1 1 1]';
nodes=num2cell((1:16)'); lengths=zeros(16,1); ids=(1:16)'; next=17;
while numel(weights)>1
    [~,order]=sortrows([weights ids],[1 2]); a=order(1); b=order(2);
    merged=[nodes{a};nodes{b}]; lengths(merged)=lengths(merged)+1;
    keep=true(size(weights)); keep([a b])=false;
    weights=[weights(keep);weights(a)+weights(b)];
    nodes=[nodes(keep);{merged}]; ids=[ids(keep);next]; next=next+1;
end
[~,order]=sortrows([lengths (0:15)'],[1 2]); codes=zeros(16,1);
code=0; previous=lengths(order(1));
for j=1:16
    symbol=order(j); code=code*2^(lengths(symbol)-previous);
    codes(symbol)=code; code=code+1; previous=lengths(symbol);
end
children=zeros(31,2); symbols=-ones(31,1); last=1;
for s=1:16
    node=1;
    for bit=lengths(s):-1:1
        branch=bitget(uint32(codes(s)),bit)+1;
        if children(node,branch)==0
            last=last+1; children(node,branch)=last;
        end
        node=children(node,branch);
    end
    symbols(node)=s-1;
end
book=struct('lengths',lengths,'codes',codes,'children',children,'symbols',symbols);
cached=book;
end
