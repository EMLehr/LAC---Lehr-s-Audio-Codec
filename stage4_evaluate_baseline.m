function results = stage4_evaluate_baseline(includeHeldOut)
%STAGE4_EVALUATE_BASELINE Measurements and one baseline masking example.
% Listening observations are deliberately left for actual listening sessions.
if nargin<1, includeHeldOut=false; end
root=fileparts(mfilename('fullpath'));
out=fullfile(root,'outputs','baseline');
ids={'harpsichord','castanets'};
if includeHeldOut, ids{end+1}='speech'; end
rows=struct([]); n=0;
for k=1:numel(ids)
    data=load(fullfile(root,'outputs','prepared',[ids{k} '.mat']),'x','fs');
    x=data.x;
    for rate=[64 96 128]
        stem=fullfile(out,sprintf('%s_baseline_%dk',ids{k},rate));
        stats=jsondecode(fileread([stem '.lac.json']));
        [y,fs]=audioread([stem '_decoded.wav']);
        assert(fs==data.fs && numel(y)==numel(x));
        e=x-y;
        L=floor(numel(x)/1024)*1024;
        xf=reshape(x(1:L),1024,[]); ef=reshape(e(1:L),1024,[]);
        active=mean(xf.^2,1)>1e-8;
        segmentSNR=10*log10((sum(xf(:,active).^2,1)+eps)./(sum(ef(:,active).^2,1)+eps));
        row=struct('source',ids{k},'model','baseline','targetKbps',rate, ...
            'actualKbps',stats.actualKbps,'bytes',stats.totalBytes, ...
            'compressionRatio',stats.compressionRatio, ...
            'snrDB',10*log10(sum(x.^2)/max(sum(e.^2),realmin)), ...
            'segmentalSNRDB',mean(max(-10,min(35,segmentSNR))), ...
            'rmse',sqrt(mean(e.^2)),'decodedPeak',max(abs(y)), ...
            'overFullScaleSamples',sum(abs(y)>1),'paddingBits',stats.paddingBits, ...
            'listening','Not yet assessed');
        n=n+1;
        if n==1, rows=row; else, rows(n)=row; end
    end
end
results=struct2table(rows);
writetable(results,fullfile(out,'measurements.csv'));
pac.write_json(fullfile(out,'measurements.json'),rows);
% Fixed identified frame, selected independently of quality comparisons.
data=load(fullfile(root,'outputs','prepared','harpsichord.mat'),'x');
cfg=codec_config(); bands=pac.bands(); X=pac.analyze(data.x);
frame=95;
[allowance,threshold,details]=pac.pam(X(:,frame),cfg,bands);
fig=figure('Visible','off','Color','w','Theme','light','Position',[100 100 1100 600]);
guard=onCleanup(@() close(fig));
semilogx(bands.frequency,10*log10(max(X(:,frame).^2/cfg.hop,1e-16)), ...
    'Color',[0.3 0.4 0.55]); hold on
semilogx(bands.frequency,10*log10(threshold/cfg.hop),'LineWidth',1.6);
semilogx(bands.frequency,10*log10(details.ath/cfg.hop),'--','LineWidth',1);
grid on; xlim([20 24000]); ylim([-130 0]);
xlabel('Frequency (Hz)'); ylabel('Bin power (dB re digital mean-square 1; not PSD)');
centerTime=((frame-1)*cfg.hop-0.5)/cfg.sampleRate;
title(sprintf('Harpsichord: baseline PAM, frame %d, center %.4f s',frame,centerTime));
subtitle('X^2 / 1024; unity mean-square assumed 96 dB SPL; thresholds are model estimates');
legend('Input MDCT spectrum','Global masking threshold','Threshold in quiet','Location','southwest');
exportgraphics(fig,fullfile(out,'baseline_masking_curve.png'),'Resolution',160);
save(fullfile(out,'baseline_masking_frame.mat'),'frame','centerTime','threshold','allowance','details','cfg');
disp(results(:,{'source','targetKbps','actualKbps','snrDB','paddingBits'}));
end
