function [X,width,scaleCode,q,usedBits,parameters] = unpack_frame(bytes,bands,flags,frame)
if nargin<3, flags=0; end
if nargin<4, frame=1; end
huffman=bitand(flags,1)~=0; bwe=bitand(flags,2)~=0;
bits=false(8,numel(bytes));
for j=1:8, bits(j,:)=bitget(bytes,9-j); end
bits=bits(:); cursor=1;
B=numel(bands.count);
width=take(B,4);
assert(all(width~=1),'pac:Format','Reserved one-bit quantizer encountered.');
parameters=zeros(4,2);
if bwe
    assert(any(bands.edges==513) && all(width(bands.edges(1:end-1)>512)==0), ...
        'pac:Format','Invalid bandwidth-extension core.');
    for g=1:4
        parameters(g,:)=[take(1,8) take(1,2)];
        assert(parameters(g,1)>0 || parameters(g,2)==0, ...
            'pac:Format','Silent BWE envelope must have zero noise code.');
    end
end
scaleCode=zeros(B,1); q=zeros(1024,1); X=q;
for b=1:B
    w=width(b);
    if w==0, continue; end
    scaleCode(b)=take(1,8);
    idx=bands.edges(b):bands.edges(b+1)-1;
    useHuffman=false;
    if huffman, useHuffman=take(1,1)~=0; end
    if useHuffman
        book=pac.huffman_book(); values=zeros(numel(idx),1);
        for k=1:numel(idx)
            node=1;
            while book.symbols(node)<0
                node=book.children(node,take(1,1)+1);
                assert(node>0,'pac:Format','Invalid Huffman prefix.');
            end
            category=book.symbols(node);
            assert(category<=w,'pac:Format','Huffman category exceeds width.');
            if category>0
                sign=take(1,1); magnitude=2^(category-1)+take(1,category-1);
                values(k)=(1-2*sign)*magnitude;
                assert(values(k)>=-2^(w-1) && values(k)<2^(w-1), ...
                    'pac:Format','Huffman value exceeds signed range.');
            end
        end
    else
        values=take(numel(idx),w);
        negative=values>=2^(w-1);
        values(negative)=values(negative)-2^w;
    end
    q(idx)=values;
    X(idx)=values*2^((scaleCode(b)-128)/4);
end
usedBits=cursor-1;
assert(~any(bits(cursor:end)),'pac:Format','Nonzero frame padding.');
if bwe, X=pac.bwe_reconstruct(X,parameters,frame); end
    function values=take(count,n)
        if n==0, values=zeros(count,1); return; end
        last=cursor+count*n-1;
        assert(last<=numel(bits),'pac:Format','Truncated frame payload.');
        block=reshape(bits(cursor:last),n,[]);
        values=double(block')*(2.^(n-1:-1:0))';
        cursor=last+1;
    end
end
