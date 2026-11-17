function [X,used,mode,localBook]=unpack_experimental(bytes,longBands,shortBands,flags,book,frame)
bits=false(8,numel(bytes));
for j=1:8, bits(j,:)=bitget(bytes,9-j); end
bits=bits(:); cursor=1; code=take(1,8); mode=mod(code,4); localBook=bitand(code,4)~=0;
assert(code<=7 && (mode==0 || bitand(flags,16)~=0),'pac:Format','Invalid experimental window flags.');
if localBook
    assert(bitand(flags,64)~=0 && ~isempty(book),'pac:Format','Unexpected local Huffman book.');
    book=pac.canonical_book(take(16,8));
end
bwe=bitand(flags,2)~=0; zeroRun=bitand(flags,4)~=0;
g=pac.frame_geometry(mode,bwe,longBands,shortBands); w=take(numel(g.count),4);
assert(all(w~=1) && all(w(~g.active)==0),'pac:Format','Invalid experimental band widths.');
parameters=zeros(4,2,g.units);
if bwe
    for u=1:g.units
        for k=1:4
            parameters(k,:,u)=[take(1,8) take(1,2)];
            assert(parameters(k,1,u)>0 || parameters(k,2,u)==0,'pac:Format','Invalid silent BWE group.');
        end
    end
end
X=zeros(1024,1);
for b=1:numel(w)
    if w(b)==0, continue; end
    step=2^((take(1,8)-128)/4); coding=0;
    if ~isempty(book) || zeroRun, coding=take(1,2); end
    assert(coding<=2 && (coding~=1 || ~isempty(book)) && (coding~=2 || zeroRun),'pac:Format','Invalid symbol mode.');
    count=g.count(b); values=zeros(count,1);
    if coding==0
        values=signed(count,w(b));
    elseif coding==1
        for k=1:count, values(k)=symbol(w(b)); end
    else
        k=1; runBits=ceil(log2(count));
        while k<=count
            if take(1,1)==0
                run=take(1,runBits)+1;
                assert(k+run-1<=count,'pac:Format','Zero run crosses band boundary.'); k=k+run;
            else
                if isempty(book), values(k)=signed(1,w(b)); else, values(k)=symbol(w(b)); end
                assert(values(k)~=0,'pac:Format','Noncanonical zero-run token.'); k=k+1;
            end
        end
    end
    X(g.edges(b):g.edges(b+1)-1)=values*step;
end
used=cursor-1; assert(~any(bits(cursor:end)),'pac:Format','Nonzero frame padding.');
if bwe
    for u=1:g.units
        idx=(u-1)*g.N+(1:g.N); X(idx)=pac.bwe_reconstruct(X(idx),parameters(:,:,u),(frame-1)*8+u);
    end
end
    function v=symbol(width)
        node=1;
        while book.symbols(node)<0
            node=book.children(node,take(1,1)+1);
            assert(node>0,'pac:Format','Invalid Huffman prefix.');
        end
        c=book.symbols(node); assert(c<=width,'pac:Format','Category exceeds width.'); v=0;
        if c>0
            sign=take(1,1); v=(1-2*sign)*(2^(c-1)+take(1,c-1));
            assert(v>=-2^(width-1) && v<2^(width-1),'pac:Format','Symbol exceeds signed range.');
        end
    end
    function v=signed(count,width)
        v=take(count,width); neg=v>=2^(width-1); v(neg)=v(neg)-2^width;
    end
    function v=take(count,n)
        if n==0, v=zeros(count,1); return; end
        last=cursor+count*n-1; assert(last<=numel(bits),'pac:Format','Truncated experimental payload.');
        block=reshape(bits(cursor:last),n,[]); v=double(block')*(2.^(n-1:-1:0))'; cursor=last+1;
    end
end
