function book=train_book(counts)
%TRAIN_BOOK Deterministic Huffman tree, pseudocount one for unseen categories.
weights=max(1,double(counts(:))); assert(numel(weights)==16,'pac:Config','Expected sixteen counts.');
nodes=num2cell((1:16)'); lengths=zeros(16,1); ids=(1:16)'; next=17;
while numel(weights)>1
    [~,order]=sortrows([weights ids],[1 2]); a=order(1); b=order(2);
    merged=[nodes{a};nodes{b}]; lengths(merged)=lengths(merged)+1;
    keep=true(size(weights)); keep([a b])=false;
    weights=[weights(keep);weights(a)+weights(b)]; nodes=[nodes(keep);{merged}];
    ids=[ids(keep);next]; next=next+1;
end
book=pac.canonical_book(lengths);
end
