function stats = encode_audio(inputPath,outputPath,cfg)
%ENCODE_AUDIO Encode prepared mono audio to the custom LAC1 binary format.
if nargin<3, cfg=codec_config(); end
pac.validate_config(cfg);
assert(cfg.targetKbps*1000==round(cfg.targetKbps*1000),'pac:Config','Bitrate must be integer bits/s.');
[~,experimental]=pac.experiment_settings(cfg);
if experimental, stats=pac.encode_experimental(inputPath,outputPath,cfg); return; end
[rateMode,distortionDB]=pac.rate_settings(cfg); vbr=strcmp(rateMode,'vbr');
[policy,reservoir]=pac.allocation_settings(cfg); bucket=reservoir.enabled;
if policy.enabled, distortionDB=policy.stopDB; elseif bucket, distortionDB=reservoir.targetDB; end
[~,~,extension]=fileparts(outputPath);
assert(strcmpi(extension,'.lac'),'pac:Output','Encoded output must use the .lac extension.');
[x,fs]=pac.read_input(inputPath);
X=pac.analyze(x); bands=pac.coding_bands(cfg.features.bandwidthExtension);
flags=double(cfg.features.huffman)+2*double(cfg.features.bandwidthExtension);
version=1+double(flags~=0); extraFrameBits=40*double(cfg.features.bandwidthExtension);
coreLimit=1024; if cfg.features.bandwidthExtension, coreLimit=512; end
[allowance,~,pamDetails]=pac.pam(X,cfg,bands);
F=size(X,2); B=numel(bands.count);
framingBits=0; storedRate=cfg.targetKbps*1000; nominal=[]; capacityBytes=0; credit=0;
if vbr
    version=3; storedRate=0; headerBytes=36+2*(B+1);
    frameBytes=zeros(1,F); framingBits=16*F;
elseif bucket
    version=4; framingBits=16*F;
    [headerBytes,nominal,capacityBytes]=pac.reservoir_layout(numel(x),F,B,cfg.targetKbps,extraFrameBits,reservoir.capacityFrames);
    frameBytes=zeros(1,F);
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
if bucket, fwrite(fid,capacityBytes,'uint32'); end
assert(ftell(fid)==headerBytes,'pac:Format','Header size mismatch.');
used=zeros(F,1); side=zeros(F,1); coefficientBits=zeros(F,1);
violations=zeros(F,1); widths=zeros(B,F);
extensionParameters=zeros(4,2,F);
entropySavingsBits=0;
coreTargetMisses=zeros(F,1); targetViolations=zeros(F,1);
reservoirBefore=zeros(F,1); reservoirAfter=zeros(F,1); borrowedBytes=zeros(F,1);
policyReserved=zeros(F,3); policySpent=zeros(F,3); policyAboveLimit=zeros(F,1);
for f=1:F
    parameters=zeros(4,2);
    if cfg.features.bandwidthExtension, parameters=pac.bwe_parameters(X(:,f)); end
    if policy.enabled
        if vbr
            [~,~,~,budget,~,coreTargetMisses(f)]=pac.allocate_vbr(X(:,f),allowance(:,f), ...
                bands,cfg.features.huffman,coreLimit,policy.stopDB);
        elseif bucket
            budget=8*(nominal(f)+credit)-extraFrameBits;
        else
            budget=8*frameBytes(f)-extraFrameBits;
        end
        [w,s,q,bits,D,pd]=pac.allocate_piecewise(X(:,f),allowance(:,f),bands, ...
            budget,cfg.features.huffman,coreLimit,policy);
        policyReserved(f,:)=pd.reservedBits; policySpent(f,:)=pd.spentBits;
        policyAboveLimit(f)=pd.bandsAboveLimit;
    elseif bucket
        [w,s,q,bits,D,coreTargetMisses(f)]=pac.allocate_vbr(X(:,f),allowance(:,f), ...
            bands,cfg.features.huffman,coreLimit,reservoir.targetDB);
        budget=8*(nominal(f)+credit)-extraFrameBits;
        if bits>budget
            [w,s,q,bits,D]=pac.allocate(X(:,f),allowance(:,f),bands,budget,cfg.features.huffman,coreLimit);
        end
    elseif vbr
        [w,s,q,bits,D,coreTargetMisses(f)]=pac.allocate_vbr(X(:,f),allowance(:,f), ...
            bands,cfg.features.huffman,coreLimit,distortionDB);
    else
        [w,s,q,bits,D]=pac.allocate(X(:,f),allowance(:,f),bands, ...
            8*frameBytes(f)-extraFrameBits,cfg.features.huffman,coreLimit);
    end
    bits=bits+extraFrameBits;
    if bucket
        reservoirBefore(f)=credit; available=nominal(f)+credit;
        minimum=ceil(bits/8); assert(minimum<=available,'pac:Budget','Reservoir overdraw.');
        borrowedBytes(f)=max(0,minimum-nominal(f));
        credit=min(capacityBytes,available-minimum);
        if f==F, credit=0; end % Remaining capacity becomes explicit final padding.
        frameBytes(f)=available-credit; reservoirAfter(f)=credit;
    elseif vbr
        frameBytes(f)=ceil(bits/8);
    end
    if vbr || bucket
        assert(frameBytes(f)<=65535,'pac:Format','Frame length exceeds uint16.');
        fwrite(fid,frameBytes(f),'uint16');
    end
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
    'piecewiseEnabled',policy.enabled,'policyReservedBits',sum(policyReserved,1), ...
    'policySpentBits',sum(policySpent,1),'policyBandsAboveLimit',sum(policyAboveLimit), ...
    'reservoirEnabled',bucket,'reservoirCapacityBytes',capacityBytes, ...
    'reservoirPeakBytes',max(reservoirAfter),'borrowedBytes',sum(borrowedBytes), ...
    'sampleCount',numel(x),'frames',F,'bands',B, ...
    'bandsOverThreshold',sum(violations),'version',version,'flags',flags, ...
    'entropySavingsBits',entropySavingsBits,'config',cfg);
pac.write_json([char(outputPath) '.json'],stats);
save([char(outputPath) '.diagnostics.mat'],'widths','allowance','violations','frameBytes', ...
    'pamDetails','extensionParameters','coreTargetMisses','targetViolations', ...
    'nominal','reservoirBefore','reservoirAfter','borrowedBytes','policyReserved','policySpent','policyAboveLimit');
fprintf('Encoded %s: %.3f kb/s, %d bytes\n',outputPath,stats.actualKbps,totalBytes);
end
