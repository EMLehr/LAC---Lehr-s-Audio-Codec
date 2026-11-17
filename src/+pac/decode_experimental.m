function [y,info]=decode_experimental(inputPath,outputWav)
%DECODE_EXPERIMENTAL Standalone v5 reader; no encoder configuration or PAM.
fid=fopen(inputPath,'r','ieee-le'); assert(fid>=0,'pac:IO','Cannot open input.'); guard=onCleanup(@() fclose(fid));
fseek(fid,0,'eof'); fileBytes=ftell(fid); fseek(fid,0,'bof');
assert(strcmp(char(read(4,'uint8')'),'LAC1') && read(1,'uint16')==5,'pac:Format','Invalid experimental magic/version.');
flags=read(1,'uint16'); fs=read(1,'uint32'); N=read(1,'uint16'); B=read(1,'uint16');
L=read(1,'uint64'); F=read(1,'uint32'); rate=read(1,'uint32'); H=read(1,'uint32');
assert(flags<=127 && fs==48000 && N==1024 && B>=1 && B<=1024 && L>=1 && L<=flintmax && ...
    F==ceil(L/1024)+1 && F<=floor(fileBytes/3),'pac:Format','Invalid experimental dimensions.');
vbr=rate==0; bucket=bitand(flags,32)~=0; variable=bitand(flags,16)~=0;
assert(~(vbr && bucket) && (bitand(flags,72)==0 || bitand(flags,1)~=0),'pac:Format','Inconsistent experimental flags.');
longBands=edges(B,1024); shortB=read(1,'uint16'); shortBands=[];
assert((variable && shortB>=1 && shortB<=128) || (~variable && shortB==0),'pac:Format','Invalid short band count.');
if variable, shortBands=edges(shortB,128); end
capacity=read(1,'uint32');
assert(bucket || capacity==0,'pac:Format','Unexpected reservoir capacity.');
book=[];
if bitand(flags,1)~=0, book=pac.huffman_book(); end
if bitand(flags,8)~=0, book=pac.canonical_book(read(16,'uint8')); end
assert(ftell(fid)==H && H<fileBytes,'pac:Format','Experimental header mismatch.');
if bitand(flags,2)~=0
    assert(any(longBands.edges==513) && (~variable || any(shortBands.edges==65)), ...
        'pac:Format','Missing BWE boundary.');
end
nominal=zeros(1,F);
if ~vbr
    assert(fileBytes==floor(L/48000*rate/8),'pac:Format','Fixed experimental size mismatch.');
    pool=fileBytes-H-2*F; nominal=diff(floor((0:F)*pool/F));
    assert(all(nominal>=1) && capacity<=floor(100*pool/F) && max(nominal)+capacity<=65535, ...
        'pac:Format','Invalid experimental capacity.');
end
X=zeros(1024,F); modes=zeros(1,F); used=zeros(F,1); lengths=used; credit=0; localCount=0;
for f=1:F
    count=read(1,'uint16'); maximum=5000;
    if ~vbr, maximum=nominal(f)+credit; end
    assert(count>=1 && count<=maximum && count<=fileBytes-ftell(fid),'pac:Format','Invalid experimental frame length.');
    [X(:,f),used(f),modes(f),local]=pac.unpack_experimental(uint8(read(count,'uint8')),longBands,shortBands,flags,book,f);
    localCount=localCount+local; lengths(f)=count; minimum=ceil(used(f)/8);
    if vbr
        assert(count==minimum,'pac:Format','Excess experimental VBR padding.');
    elseif bucket
        available=nominal(f)+credit; expected=max(minimum,available-capacity);
        if f==F, expected=available; end
        assert(count==expected,'pac:Format','Invalid experimental credit/padding.'); credit=available-count;
    else
        assert(count==nominal(f),'pac:Format','Invalid fixed experimental frame size.');
    end
end
assert(ftell(fid)==fileBytes,'pac:Format','Unexpected trailing experimental data.');
y=pac.synthesize_switch(X,L,modes); rateMode='cbr'; if vbr, rateMode='vbr'; end
info=struct('sampleRate',fs,'sampleCount',L,'frames',F,'targetKbps',rate/1000, ...
    'actualKbps',fileBytes*8/(L/fs)/1000,'totalBytes',fileBytes,'headerBytes',H, ...
    'paddingBits',sum(lengths)*8-sum(used),'peak',max(abs(y)),'version',5,'flags',flags, ...
    'rateMode',rateMode,'framingBits',16*F,'reservoirEnabled',bucket,'reservoirCapacityBytes',capacity, ...
    'sizeReductionPercent',100*(1-fileBytes/(2*L)),'shortFrames',nnz(modes==2),'windowBooksUsed',localCount);
if nargin>=2 && strlength(string(outputWav))>0
    [~,~,extension]=fileparts(outputWav); assert(strcmpi(extension,'.wav'),'pac:Output','Decoded output must use .wav.');
    pac.write_wav(outputWav,y,fs);
end
    function b=edges(count,last)
        values=read(count+1,'uint16')+1;
        assert(values(1)==1 && values(end)==last+1 && all(diff(values)>0),'pac:Format','Invalid experimental band edges.');
        b=struct('edges',values,'count',diff(values));
    end
    function values=read(count,type)
        [values,n]=fread(fid,count,[type '=>double']); assert(n==count,'pac:Format','Truncated experimental file.');
    end
end
