function [bytes,used,side,coefficient]=pack_experimental(w,s,q,g,mode,parameters,book,zeroRun,bwe,localBook)
%PACK_EXPERIMENTAL V5 payload; mode byte, optional local book, band symbols.
bits=false(40000,1); cursor=1; coefficient=0;
append(mode+4*double(localBook),8);
if localBook, append(book.lengths,8); end
append(w,4);
if bwe
    for u=1:g.units
        for k=1:4, append(parameters(k,1,u),8); append(parameters(k,2,u),2); end
    end
end
for b=1:numel(w)
    if w(b)==0, continue; end
    append(s(b),8); idx=g.edges(b):g.edges(b+1)-1; values=q(idx);
    [~,coding]=pac.symbol_cost(values,w(b),book,zeroRun);
    if ~isempty(book) || zeroRun, append(coding,2); end
    first=cursor;
    if coding==0
        append(mod(values,2^w(b)),w(b));
    elseif coding==1
        for k=1:numel(values), symbol(values(k)); end
    else
        k=1; runBits=ceil(log2(numel(values)));
        while k<=numel(values)
            if values(k)==0
                next=k; while next<numel(values) && values(next+1)==0, next=next+1; end
                append(0,1); append(next-k,runBits); k=next+1;
            else
                append(1,1);
                if isempty(book), append(mod(values(k),2^w(b)),w(b)); else, symbol(values(k)); end
                k=k+1;
            end
        end
    end
    coefficient=coefficient+cursor-first;
end
used=cursor-1; side=used-coefficient;
bytes=uint8(double(reshape(bits(1:8*ceil(used/8)),8,[])')*(2.^(7:-1:0))');
    function symbol(v)
        c=0; if v~=0, c=floor(log2(abs(v)))+1; end
        append(book.codes(c+1),book.lengths(c+1));
        if c>0, append(v<0,1); append(abs(v)-2^(c-1),c-1); end
    end
    function append(values,n)
        if n==0, return; end
        values=uint32(values(:)); block=false(n,numel(values));
        for j=1:n, block(j,:)=bitget(values,n-j+1)'; end
        last=cursor+numel(block)-1;
        assert(last<=numel(bits),'pac:Budget','Experimental payload exceeds bounded buffer.');
        bits(cursor:last)=block(:); cursor=last+1;
    end
end
