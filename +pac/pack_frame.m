function [bytes,usedBits] = pack_frame(width,scaleCode,q,bands,frameBytes)
%PACK_FRAME MSB-first widths, then per-band step and two's-complement values.
bits=false(frameBytes*8,1); cursor=1;
append(width,4);
for b=1:numel(width)
    w=width(b);
    if w==0, continue; end
    append(scaleCode(b),8);
    idx=bands.edges(b):bands.edges(b+1)-1;
    append(mod(q(idx),2^w),w);
end
usedBits=cursor-1;
bytes=uint8(double(reshape(bits,8,[])')*(2.^(7:-1:0))');
    function append(values,n)
        values=uint32(values(:));
        block=false(n,numel(values));
        for j=1:n, block(j,:)=bitget(values,n-j+1)'; end
        last=cursor+numel(block)-1;
        assert(last<=numel(bits),'pac:Budget','Frame packing exceeded budget.');
        bits(cursor:last)=block(:); cursor=last+1;
    end
end
