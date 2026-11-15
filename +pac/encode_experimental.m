function stats=encode_experimental(inputPath,outputPath,cfg)
%ENCODE_EXPERIMENTAL V5 experiments, preserving the original v1-v4 path.
[~,~,extension]=fileparts(outputPath);
assert(strcmpi(extension,'.lac'),'pac:Output','Encoded output must use .lac.');
[x,fs]=pac.read_input(inputPath); e=pac.experiment_settings(cfg);
[mode,~]=pac.rate_settings(cfg); vbr=strcmp(mode,'vbr');
[~,reservoir]=pac.allocation_settings(cfg);
[X,frames,modes,detector,longBands,shortBands]=pac.prepare_experimental(x,cfg);
book=[]; if cfg.features.huffman || e.fileHuffman, book=pac.huffman_book(); end
plan=pac.plan_experimental(X,frames,modes,numel(x),cfg,book,false);
referenceBytes=plan.totalBytes; referenceUseful=plan.usefulBytes;
if e.fileHuffman
    learned=pac.train_book(plan.counts);
    try
        alternative=pac.plan_experimental(X,frames,modes,numel(x),cfg,learned,true);
        % CBR file sizes tie by definition; compare coding cost before padding.
        if (vbr && alternative.totalBytes<plan.totalBytes) || ...
                (~vbr && alternative.totalBytes<=plan.totalBytes && alternative.usefulBytes<plan.usefulBytes)
            plan=alternative;
        end
    catch exception
        if ~strcmp(exception.identifier,'pac:Budget'), rethrow(exception); end
    end
end
flags=double(~isempty(book))+2*double(cfg.features.bandwidthExtension)+ ...
    4*double(e.zeroRun)+8*double(plan.customBook)+16*double(e.variableWindows)+ ...
    32*double(reservoir.enabled)+64*double(e.fileHuffman && strcmp(e.huffmanScope,'window'));
F=size(X,2); storedRate=cfg.targetKbps*1000; if vbr, storedRate=0; end
fid=fopen(outputPath,'w','ieee-le'); assert(fid>=0,'pac:IO','Cannot open output.'); guard=onCleanup(@() fclose(fid));
fwrite(fid,'LAC1','char'); fwrite(fid,5,'uint16'); fwrite(fid,flags,'uint16');
fwrite(fid,48000,'uint32'); fwrite(fid,1024,'uint16'); fwrite(fid,numel(longBands.count),'uint16');
fwrite(fid,numel(x),'uint64'); fwrite(fid,F,'uint32'); fwrite(fid,storedRate,'uint32');
fwrite(fid,plan.headerBytes,'uint32'); fwrite(fid,longBands.edges-1,'uint16');
shortB=0; if e.variableWindows, shortB=numel(shortBands.count); end
fwrite(fid,shortB,'uint16');
if shortB>0, fwrite(fid,shortBands.edges-1,'uint16'); end
fwrite(fid,plan.capacityBytes,'uint32');
if plan.customBook, fwrite(fid,plan.book.lengths,'uint8'); end
assert(ftell(fid)==plan.headerBytes,'pac:Format','Experimental header mismatch.');
for f=1:F
    fwrite(fid,plan.frameBytes(f),'uint16'); count=fwrite(fid,plan.payload{f},'uint8');
    assert(count==plan.frameBytes(f),'pac:IO','Incomplete frame write.');
end
assert(ftell(fid)==plan.totalBytes,'pac:Budget','Experimental byte accounting mismatch.'); clear guard
actual=8*plan.totalBytes/(numel(x)/fs)/1000;
stats=struct('input',char(inputPath),'output',char(outputPath),'model',pac.model_name(cfg), ...
    'targetKbps',storedRate/1000,'actualKbps',actual,'totalBytes',plan.totalBytes, ...
    'headerBytes',plan.headerBytes,'frameSideBits',sum(plan.side),'coefficientBits',sum(plan.coefficient), ...
    'paddingBits',8*sum(plan.frameBytes)-sum(plan.used),'framingBits',16*F, ...
    'compressionRatio',768/actual,'sizeReductionPercent',100*(1-plan.totalBytes/(2*numel(x))), ...
    'rateMode',mode,'vbrDistortionDB',plan.targetDB,'sampleCount',numel(x),'frames',F, ...
    'version',5,'flags',flags,'config',cfg,'coreTargetMisses',sum(plan.coreTargetMisses), ...
    'bandsOverScaledTarget',sum(plan.violations),'reservoirEnabled',reservoir.enabled, ...
    'reservoirCapacityBytes',plan.capacityBytes,'reservoirPeakBytes',max(plan.after), ...
    'borrowedBytes',sum(plan.borrowed),'policyReservedBits',sum(plan.reserved,1), ...
    'policySpentBits',sum(plan.spent,1),'fileBookUsed',plan.customBook, ...
    'windowBooksUsed',nnz(plan.localBooks),'windowBookSavingsBytes',sum(plan.localSavingsBytes), ...
    'fixedBookReferenceBytes',referenceBytes,'fixedBookReferenceUsefulBytes',referenceUseful, ...
    'usefulBytes',plan.usefulBytes,'shortFrames',nnz(modes==2));
pac.write_json([char(outputPath) '.json'],stats);
plan=rmfield(plan,'payload');
save([char(outputPath) '.diagnostics.mat'],'plan','frames','modes','detector');
fprintf('Encoded %s: %.3f kb/s, %d bytes (v5, %d short frames).\n',outputPath,actual,stats.totalBytes,stats.shortFrames);
end
