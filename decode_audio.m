function [y,info] = decode_audio(inputPath,outputWav)
%DECODE_AUDIO Standalone decoder; does not read original audio or run the PAM.
fid=fopen(inputPath,'r','ieee-le');
assert(fid>=0,'pac:IO','Cannot open %s',inputPath);
guard=onCleanup(@() fclose(fid));
fseek(fid,0,'eof'); fileBytes=ftell(fid); fseek(fid,0,'bof');
assert(fileBytes>=36,'pac:Format','Truncated header.');
assert(strcmp(char(fread(fid,4,'*uint8')'),'LAC1'),'pac:Format','Invalid magic.');
version=read(1,'uint16'); flags=read(1,'uint16'); fs=read(1,'uint32');
N=read(1,'uint16'); B=read(1,'uint16'); L=read(1,'uint64');
F=read(1,'uint32'); rate=read(1,'uint32'); storedHeader=read(1,'uint32');
assert(version==1 && flags==0,'pac:Format','Unsupported version or optional features.');
assert(fs==48000 && N==1024 && B>=1 && B<=1024,'pac:Format','Invalid dimensions.');
assert(L>=1 && L<=flintmax && F==ceil(L/N)+1 && rate>0,'pac:Format','Invalid length or rate.');
edges=read(B+1,'uint16')+1;
assert(edges(1)==1 && edges(end)==N+1 && all(diff(edges)>0), ...
    'pac:Format','Invalid band boundaries.');
assert(storedHeader==36+2*(B+1) && ...
    F<=floor(max(0,fileBytes-storedHeader)/ceil(4*B/8)), ...
    'pac:Format','Frame count cannot fit in file.');
bands=struct('edges',edges,'count',diff(edges));
[headerBytes,frameBytes]=pac.layout(L,F,B,rate/1000);
assert(storedHeader==headerBytes && ftell(fid)==headerBytes && ...
    fileBytes==headerBytes+sum(frameBytes),'pac:Format','Truncated file or unexpected trailing data.');
X=zeros(N,F); used=zeros(F,1);
for f=1:F
    bytes=uint8(read(frameBytes(f),'uint8'));
    [X(:,f),~,~,~,used(f)]=pac.unpack_frame(bytes,bands);
end
y=pac.synthesize(X,L);
info=struct('sampleRate',fs,'sampleCount',L,'frames',F, ...
    'targetKbps',rate/1000,'actualKbps',fileBytes*8/(L/fs)/1000, ...
    'totalBytes',fileBytes,'headerBytes',headerBytes, ...
    'paddingBits',sum(frameBytes)*8-sum(used),'peak',max(abs(y)));
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
