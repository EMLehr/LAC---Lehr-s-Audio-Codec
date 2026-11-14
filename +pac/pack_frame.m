function [bytes,usedBits,sideBits,coefficientBits] = pack_frame(width,scaleCode,q,bands,frameBytes,flags,parameters)
%PACK_FRAME MSB-first widths, then per-band step and two's-complement values.
bits=false(frameBytes*8,1); cursor=1;
if nargin<6, flags=0; end
if nargin<7, parameters=zeros(4,2); end
huffman=bitand(flags,1)~=0; bwe=bitand(flags,2)~=0;
sideBits=4*numel(width); coefficientBits=0;
append(width,4);
if bwe
    for g=1:4, append(parameters(g,1),8); append(parameters(g,2),2); end
    sideBits=sideBits+40;
end
for b=1:numel(width)
    w=width(b);
    if w==0, continue; end
    append(scaleCode(b),8);
    sideBits=sideBits+8;
    idx=bands.edges(b):bands.edges(b+1)-1;
    useHuffman=false;
    if huffman
        [~,useHuffman]=pac.entropy_cost(q(idx),w);
        append(useHuffman,1); sideBits=sideBits+1;
    end
    first=cursor;
    if useHuffman
        book=pac.huffman_book();
        for k=idx
            value=q(k); category=0;
            if value~=0, category=floor(log2(abs(value)))+1; end
            append(book.codes(category+1),book.lengths(category+1));
            if category>0
                append(value<0,1); append(abs(value)-2^(category-1),category-1);
            end
        end
    else
        append(mod(q(idx),2^w),w);
    end
    coefficientBits=coefficientBits+cursor-first;
end
usedBits=cursor-1;
bytes=uint8(double(reshape(bits,8,[])')*(2.^(7:-1:0))');
    function append(values,n)
        if n==0, return; end
        values=uint32(values(:));
        block=false(n,numel(values));
        for j=1:n, block(j,:)=bitget(values,n-j+1)'; end
        last=cursor+numel(block)-1;
        assert(last<=numel(bits),'pac:Budget','Frame packing exceeded budget.');
        bits(cursor:last)=block(:); cursor=last+1;
    end
end
