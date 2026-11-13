function stats = encode_audio(inputPath,outputPath,cfg)
%ENCODE_AUDIO Encode prepared mono audio to the custom LAC1 binary format.
if nargin<3, cfg=codec_config(); end
pac.validate_config(cfg);
[~,~,extension]=fileparts(outputPath);
assert(strcmpi(extension,'.lac'),'pac:Output','Encoded output must use the .lac extension.');
assert(cfg.targetKbps*1000==round(cfg.targetKbps*1000),'pac:Config','Bitrate must be integer bits/s.');
[x,fs]=pac.read_input(inputPath);
X=pac.analyze(x); bands=pac.bands();
[allowance,~,pamDetails]=pac.pam(X,cfg,bands);
F=size(X,2); B=numel(bands.count);
[headerBytes,frameBytes]=pac.layout(numel(x),F,B,cfg.targetKbps);
fid=fopen(outputPath,'w','ieee-le');
assert(fid>=0,'pac:IO','Cannot open %s',outputPath);
guard=onCleanup(@() fclose(fid));
fwrite(fid,'LAC1','char'); fwrite(fid,1,'uint16'); fwrite(fid,0,'uint16');
fwrite(fid,fs,'uint32'); fwrite(fid,cfg.hop,'uint16'); fwrite(fid,B,'uint16');
fwrite(fid,numel(x),'uint64'); fwrite(fid,F,'uint32');
fwrite(fid,cfg.targetKbps*1000,'uint32'); fwrite(fid,headerBytes,'uint32');
fwrite(fid,bands.edges-1,'uint16'); % Zero-based, exclusive final edge.
assert(ftell(fid)==headerBytes,'pac:Format','Header size mismatch.');
used=zeros(F,1); side=zeros(F,1); coefficientBits=zeros(F,1);
violations=zeros(F,1); widths=zeros(B,F);
for f=1:F
    [w,s,q,bits,D]=pac.allocate(X(:,f),allowance(:,f),bands,8*frameBytes(f));
    [bytes,actualBits]=pac.pack_frame(w,s,q,bands,frameBytes(f));
    assert(bits==actualBits,'pac:Budget','Allocation and packing disagree.');
    count=fwrite(fid,bytes,'uint8');
    assert(count==frameBytes(f),'pac:IO','Incomplete frame write.');
    used(f)=bits; side(f)=4*B+8*nnz(w); coefficientBits(f)=sum(w.*bands.count);
    violations(f)=sum(D>allowance(:,f)); widths(:,f)=w;
end
totalBytes=ftell(fid);
assert(totalBytes==headerBytes+sum(frameBytes),'pac:Budget','File size mismatch.');
clear guard
stats=struct('input',char(inputPath),'output',char(outputPath),'model',pac.model_name(cfg), ...
    'targetKbps',cfg.targetKbps,'actualKbps',8*totalBytes/(numel(x)/fs)/1000, ...
    'totalBytes',totalBytes,'headerBytes',headerBytes,'frameSideBits',sum(side), ...
    'coefficientBits',sum(coefficientBits),'paddingBits',sum(8*frameBytes)-sum(used), ...
    'compressionRatio',768/(8*totalBytes/(numel(x)/fs)/1000), ...
    'sampleCount',numel(x),'frames',F,'bands',B, ...
    'bandsOverThreshold',sum(violations),'config',cfg);
pac.write_json([char(outputPath) '.json'],stats);
save([char(outputPath) '.diagnostics.mat'],'widths','allowance','violations','frameBytes','pamDetails');
fprintf('Encoded %s: %.3f kb/s, %d bytes\n',outputPath,stats.actualKbps,totalBytes);
end
