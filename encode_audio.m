function stats = encode_audio(inputPath,outputPath,cfg)
%ENCODE_AUDIO Encode prepared mono audio to the custom LAC1 binary format.
if nargin<3, cfg=codec_config(); end
pac.validate_config(cfg);
[rateMode,distortionDB]=pac.rate_settings(cfg); vbr=strcmp(rateMode,'vbr');
[~,~,extension]=fileparts(outputPath);
assert(strcmpi(extension,'.lac'),'pac:Output','Encoded output must use the .lac extension.');
assert(cfg.targetKbps*1000==round(cfg.targetKbps*1000),'pac:Config','Bitrate must be integer bits/s.');
[x,fs]=pac.read_input(inputPath);
X=pac.analyze(x); bands=pac.coding_bands(cfg.features.bandwidthExtension);
flags=double(cfg.features.huffman)+2*double(cfg.features.bandwidthExtension);
version=1+double(flags~=0); extraFrameBits=40*double(cfg.features.bandwidthExtension);
coreLimit=1024; if cfg.features.bandwidthExtension, coreLimit=512; end
[allowance,~,pamDetails]=pac.pam(X,cfg,bands);
F=size(X,2); B=numel(bands.count);
framingBits=0; storedRate=cfg.targetKbps*1000;
if vbr
    version=3; storedRate=0; headerBytes=36+2*(B+1);
    frameBytes=zeros(1,F); framingBits=16*F;
else
    [headerBytes,frameBytes]=pac.layout(numel(x),F,B,cfg.targetKbps,extraFrameBits);
end
fid=fopen(outputPath,'w','ieee-le');
assert(fid>=0,'pac:IO','Cannot open %s',outputPath);
guard=onCleanup(@() fclose(fid));
fwrite(fid,'LAC1','char'); fwrite(fid,version,'uint16'); fwrite(fid,flags,'uint16');
fwrite(fid,fs,'uint32'); fwrite(fid,cfg.hop,'uint16'); fwrite(fid,B,'uint16');
fwrite(fid,numel(x),'uint64'); fwrite(fid,F,'uint32');
fwrite(fid,storedRate,'uint32'); fwrite(fid,headerBytes,'uint32');
fwrite(fid,bands.edges-1,'uint16'); % Zero-based, exclusive final edge.
assert(ftell(fid)==headerBytes,'pac:Format','Header size mismatch.');
used=zeros(F,1); side=zeros(F,1); coefficientBits=zeros(F,1);
violations=zeros(F,1); widths=zeros(B,F);
extensionParameters=zeros(4,2,F);
entropySavingsBits=0;
coreTargetMisses=zeros(F,1); targetViolations=zeros(F,1);
for f=1:F
    parameters=zeros(4,2);
    if cfg.features.bandwidthExtension, parameters=pac.bwe_parameters(X(:,f)); end
    if vbr
        [w,s,q,bits,D,coreTargetMisses(f)]=pac.allocate_vbr(X(:,f),allowance(:,f), ...
            bands,cfg.features.huffman,coreLimit,distortionDB);
        frameBytes(f)=ceil((bits+extraFrameBits)/8);
        assert(frameBytes(f)<=65535,'pac:Format','VBR frame length exceeds uint16.');
        fwrite(fid,frameBytes(f),'uint16');
    else
        [w,s,q,bits,D]=pac.allocate(X(:,f),allowance(:,f),bands, ...
            8*frameBytes(f)-extraFrameBits,cfg.features.huffman,coreLimit);
    end
    bits=bits+extraFrameBits;
    [bytes,actualBits,side(f),coefficientBits(f)]=pac.pack_frame(w,s,q,bands,frameBytes(f),flags,parameters);
    assert(bits==actualBits,'pac:Budget','Allocation and packing disagree.');
    count=fwrite(fid,bytes,'uint8');
    assert(count==frameBytes(f),'pac:IO','Incomplete frame write.');
    used(f)=bits; extensionParameters(:,:,f)=parameters;
    if cfg.features.huffman
        entropySavingsBits=entropySavingsBits+4*B+extraFrameBits+ ...
            8*nnz(w)+sum(w.*bands.count)-bits;
    end
    if cfg.features.bandwidthExtension
        reconstructed=zeros(1024,1);
        for b=1:B
            idx=bands.edges(b):bands.edges(b+1)-1;
            if w(b)>0, reconstructed(idx)=q(idx)*2^((s(b)-128)/4); end
        end
        reconstructed=pac.bwe_reconstruct(reconstructed,parameters,f);
        for b=1:B
            idx=bands.edges(b):bands.edges(b+1)-1;
            D(b)=sum((X(idx,f)-reconstructed(idx)).^2);
        end
    end
    violations(f)=sum(D>allowance(:,f)); widths(:,f)=w;
    targetViolations(f)=sum(D>allowance(:,f)*10^(distortionDB/10));
end
totalBytes=ftell(fid);
assert(totalBytes==headerBytes+sum(frameBytes)+framingBits/8,'pac:Budget','File size mismatch.');
clear guard
stats=struct('input',char(inputPath),'output',char(outputPath),'model',pac.model_name(cfg), ...
    'targetKbps',storedRate/1000,'actualKbps',8*totalBytes/(numel(x)/fs)/1000, ...
    'totalBytes',totalBytes,'headerBytes',headerBytes,'frameSideBits',sum(side), ...
    'coefficientBits',sum(coefficientBits),'paddingBits',sum(8*frameBytes)-sum(used), ...
    'compressionRatio',768/(8*totalBytes/(numel(x)/fs)/1000), ...
    'sizeReductionPercent',100*(1-totalBytes/(2*numel(x))), ...
    'rateMode',rateMode,'vbrDistortionDB',distortionDB,'framingBits',framingBits, ...
    'coreTargetMisses',sum(coreTargetMisses),'bandsOverScaledTarget',sum(targetViolations), ...
    'sampleCount',numel(x),'frames',F,'bands',B, ...
    'bandsOverThreshold',sum(violations),'version',version,'flags',flags, ...
    'entropySavingsBits',entropySavingsBits,'config',cfg);
pac.write_json([char(outputPath) '.json'],stats);
save([char(outputPath) '.diagnostics.mat'],'widths','allowance','violations','frameBytes', ...
    'pamDetails','extensionParameters','coreTargetMisses','targetViolations');
fprintf('Encoded %s: %.3f kb/s, %d bytes\n',outputPath,stats.actualKbps,totalBytes);
end
