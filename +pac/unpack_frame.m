function [X,width,scaleCode,q,usedBits] = unpack_frame(bytes,bands)
bits=false(8,numel(bytes));
for j=1:8, bits(j,:)=bitget(bytes,9-j); end
bits=bits(:); cursor=1;
B=numel(bands.count);
width=take(B,4);
assert(all(width~=1),'pac:Format','Reserved one-bit quantizer encountered.');
scaleCode=zeros(B,1); q=zeros(1024,1); X=q;
for b=1:B
    w=width(b);
    if w==0, continue; end
    scaleCode(b)=take(1,8);
    idx=bands.edges(b):bands.edges(b+1)-1;
    values=take(numel(idx),w);
    negative=values>=2^(w-1);
    values(negative)=values(negative)-2^w;
    q(idx)=values;
    X(idx)=values*2^((scaleCode(b)-128)/4);
end
usedBits=cursor-1;
assert(~any(bits(cursor:end)),'pac:Format','Nonzero frame padding.');
    function values=take(count,n)
        last=cursor+count*n-1;
        assert(last<=numel(bits),'pac:Format','Truncated frame payload.');
        block=reshape(bits(cursor:last),n,[]);
        values=double(block')*(2.^(n-1:-1:0))';
        cursor=last+1;
    end
end
