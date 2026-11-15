function [y,info] = decode_audio(inputPath,outputWav)
%DECODE_AUDIO Standalone decoder; does not read original audio or run the PAM.
fid=fopen(inputPath,'r','ieee-le');
assert(fid>=0,'pac:IO','Cannot open %s',inputPath);
guard=onCleanup(@() fclose(fid));
fseek(fid,0,'eof'); fileBytes=ftell(fid); fseek(fid,0,'bof');
assert(fileBytes>=36,'pac:Format','Truncated header.');
assert(strcmp(char(fread(fid,4,'*uint8')'),'LAC1'),'pac:Format','Invalid magic.');
version=read(1,'uint16'); flags=read(1,'uint16'); fs=read(1,'uint32');
if version==5
    clear guard
    if nargin<2, outputWav=''; end
    [y,info]=pac.decode_experimental(inputPath,outputWav); return
end
N=read(1,'uint16'); B=read(1,'uint16'); L=read(1,'uint64');
F=read(1,'uint32'); rate=read(1,'uint32'); storedHeader=read(1,'uint32');
assert((version==1 && flags==0) || (version==2 && flags>=1 && flags<=3) || ...
    (ismember(version,[3 4]) && flags>=0 && flags<=3), ...
    'pac:Format','Unsupported version or optional features.');
extraFrameBits=40*double(bitand(flags,2)~=0);
assert(fs==48000 && N==1024 && B>=1 && B<=1024,'pac:Format','Invalid dimensions.');
vbr=version==3; bucket=version==4; framed=vbr || bucket;
framingBits=16*F*double(framed); capacityBytes=0; credit=0; nominal=[];
assert(L>=1 && L<=flintmax && F==ceil(L/N)+1 && ...
    ((vbr && rate==0) || (~vbr && rate>0)),'pac:Format','Invalid length or rate.');
edges=read(B+1,'uint16')+1;
assert(edges(1)==1 && edges(end)==N+1 && all(diff(edges)>0), ...
    'pac:Format','Invalid band boundaries.');
if bucket, capacityBytes=read(1,'uint32'); end
assert(storedHeader==36+2*(B+1)+4*double(bucket) && ...
    F<=floor(max(0,fileBytes-storedHeader)/(ceil((4*B+extraFrameBits)/8)+2*double(framed))), ...
    'pac:Format','Frame count cannot fit in file.');
bands=struct('edges',edges,'count',diff(edges));
if bucket
    assert(fileBytes==floor(L/48000*rate/8),'pac:Format','Reservoir file size does not match rate.');
    [headerBytes,nominal]=pac.reservoir_layout(L,F,B,rate/1000,extraFrameBits,0);
    frameBytes=zeros(1,F);
    assert(fileBytes==floor(L/48000*rate/8) && capacityBytes<=floor(100*mean(nominal)) && ...
        max(nominal)+capacityBytes<=65535,'pac:Format','Invalid reservoir capacity or file size.');
elseif vbr
    headerBytes=storedHeader; frameBytes=zeros(1,F);
else
    [headerBytes,frameBytes]=pac.layout(L,F,B,rate/1000,extraFrameBits);
    assert(storedHeader==headerBytes && fileBytes==headerBytes+sum(frameBytes), ...
        'pac:Format','Truncated file or unexpected trailing data.');
end
assert(ftell(fid)==headerBytes,'pac:Format','Incorrect header size.');
X=zeros(N,F); used=zeros(F,1);
for f=1:F
    if framed
        frameBytes(f)=read(1,'uint16');
        maximum=ceil((13*B+15*N+extraFrameBits)/8);
        if bucket, maximum=nominal(f)+credit; end
        assert(frameBytes(f)>=ceil((4*B+extraFrameBits)/8) && ...
            frameBytes(f)<=maximum && ...
            frameBytes(f)<=fileBytes-ftell(fid),'pac:Format','Invalid VBR frame length.');
    end
    bytes=uint8(read(frameBytes(f),'uint8'));
    [X(:,f),~,~,~,used(f)]=pac.unpack_frame(bytes,bands,flags,f);
    if vbr
        assert(frameBytes(f)==ceil(used(f)/8),'pac:Format','Excess VBR frame padding.');
    elseif bucket
        available=nominal(f)+credit;
        expected=max(ceil(used(f)/8),available-capacityBytes);
        if f==F, expected=available; end
        assert(frameBytes(f)==expected,'pac:Format','Invalid reservoir padding or credit balance.');
        credit=available-frameBytes(f);
    end
end
assert(ftell(fid)==fileBytes,'pac:Format','Unexpected trailing data.');
y=pac.synthesize(X,L);
info=struct('sampleRate',fs,'sampleCount',L,'frames',F, ...
    'targetKbps',rate/1000,'actualKbps',fileBytes*8/(L/fs)/1000, ...
    'totalBytes',fileBytes,'headerBytes',headerBytes, ...
    'paddingBits',sum(frameBytes)*8-sum(used),'peak',max(abs(y)), ...
    'version',version,'flags',flags);
info.rateMode='cbr'; if vbr, info.rateMode='vbr'; end
info.framingBits=framingBits;
info.reservoirEnabled=bucket; info.reservoirCapacityBytes=capacityBytes;
info.sizeReductionPercent=100*(1-fileBytes/(2*L));
if nargin>=2 && strlength(string(outputWav))>0
    [~,~,extension]=fileparts(outputWav);
    assert(strcmpi(extension,'.wav'),'pac:Output','Decoded output must use the .wav extension.');
    pac.write_wav(outputWav,y,fs);
end
    function values=read(count,type)
        [values,n]=fread(fid,count,[type '=>double']);
        assert(n==count,'pac:Format','Unexpected end of file.');
    end
end
