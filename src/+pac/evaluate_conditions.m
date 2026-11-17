function results = evaluate_conditions(root,out,ids,modes)
rows=struct([]); n=0; onsetRecords=struct([]);
for k=1:numel(ids)
    data=load(fullfile(root,'outputs','prepared',[ids{k} '.mat']),'x','fs');
    x=data.x;
    [pre,post,onsets]=pac.onset_windows(x,data.fs);
    onsetRow=struct('source',ids{k},'samples',onsets,'timesSeconds',(onsets-1)/data.fs);
    if k==1, onsetRecords=onsetRow; else, onsetRecords(k)=onsetRow; end
    for rate=[64 96 128]
        for m=1:numel(modes)
            stem=fullfile(out,sprintf('%s_%s_%dk',ids{k},modes{m},rate));
            stats=jsondecode(fileread([stem '.lac.json']));
            [y,fs]=audioread([stem '_decoded.wav']);
            assert(fs==data.fs && numel(y)==numel(x) && stats.actualKbps==rate);
            e=x-y;
            L=floor(numel(x)/1024)*1024;
            xf=reshape(x(1:L),1024,[]); ef=reshape(e(1:L),1024,[]);
            active=mean(xf.^2,1)>1e-8;
            seg=10*log10((sum(xf(:,active).^2,1)+eps)./(sum(ef(:,active).^2,1)+eps));
            diag=load([stem '.lac.diagnostics.mat'],'widths');
            codingBands=pac.coding_bands(stats.config.features.bandwidthExtension);
            expandedWidths=repelem(diag.widths,codingBands.count,1);
            if m==1
                baselineSNR=10*log10(sum(x.^2)/max(sum(e.^2),realmin));
                baselinePre=mean_or_nan(e(pre).^2); baselinePost=mean_or_nan(e(post).^2);
                baselineWidths=diag.widths;
                baselineExpandedWidths=expandedWidths;
            end
            changedBands=NaN;
            entropySavings=0;
            if isfield(stats,'entropySavingsBits'), entropySavings=stats.entropySavingsBits; end
            if isequal(size(diag.widths),size(baselineWidths))
                changedBands=nnz(diag.widths~=baselineWidths);
            end
            row=struct('source',ids{k},'model',modes{m},'targetKbps',rate, ...
                'actualKbps',stats.actualKbps,'bytes',stats.totalBytes, ...
                'compressionRatio',stats.compressionRatio, ...
                'snrDB',10*log10(sum(x.^2)/max(sum(e.^2),realmin)), ...
                'segmentalSNRDB',mean(max(-10,min(35,seg))), ...
                'rmse',sqrt(mean(e.^2)),'preOnsetMSE',mean_or_nan(e(pre).^2), ...
                'postOnsetMSE',mean_or_nan(e(post).^2),'onsets',numel(onsets), ...
                'paddingBits',stats.paddingBits,'overFullScaleSamples',sum(abs(y)>1), ...
                'entropySavingsBits',entropySavings, ...
                'changedBandWidths',changedBands, ...
                'changedCoefficientWidths',nnz(expandedWidths~=baselineExpandedWidths), ...
                'listening','Not yet assessed');
            row.deltaSNRDB=row.snrDB-baselineSNR;
            row.preOnsetErrorChangeDB=10*log10(row.preOnsetMSE/baselinePre);
            row.postOnsetErrorChangeDB=10*log10(row.postOnsetMSE/baselinePost);
            n=n+1;
            if n==1, rows=row; else, rows(n)=row; end
        end
    end
end
results=struct2table(rows);
writetable(results,fullfile(out,'measurements.csv'));
pac.write_json(fullfile(out,'measurements.json'),rows);
pac.write_json(fullfile(out,'onsets.json'),onsetRecords);
disp(results(:,{'source','model','actualKbps','deltaSNRDB','preOnsetErrorChangeDB'}));
end

function value=mean_or_nan(values)
if isempty(values), value=NaN; else, value=mean(values); end
end
