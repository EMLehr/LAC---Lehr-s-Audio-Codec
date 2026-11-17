function stage5_temporal(action)
%STAGE5_TEMPORAL Independent 'encode', 'decode', or 'evaluate' stage.
% Only development clips; speech stays held out. 'decode' reads .lac only.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=pac.project_root();
out=fullfile(root,'outputs','temporal');
if ~isfolder(out), mkdir(out); end
ids={'harpsichord','castanets'};
modes={'temporal','temporal_post_only','temporal_preecho_only'};
switch action
    case 'encode'
        regression=struct([]); n=0;
        for k=1:numel(ids)
            input=fullfile(root,'outputs','prepared',[ids{k} '.mat']);
            for rate=[64 96 128]
                % Re-encode all-off and compare with the frozen baseline files.
                cfg=codec_config(); cfg.targetKbps=rate;
                original=fullfile(root,'outputs','baseline',sprintf('%s_baseline_%dk.lac',ids{k},rate));
                assert(isfile(original),'pac:Input','Run stage4_encode_baseline first.');
                copy=fullfile(out,sprintf('%s_baseline_%dk.lac',ids{k},rate));
                encode_audio(input,copy,cfg);
                assert(isequal(pac.file_bytes(original),pac.file_bytes(copy)), ...
                    'pac:Regression','All-off baseline bytes changed: %s',original);
                n=n+1; row=struct('source',ids{k},'rate',rate,'identicalBytes',true);
                if n==1, regression=row; else, regression(n)=row; end
                for m=1:numel(modes)
                    cfg=mode_config(modes{m},rate);
                    path=fullfile(out,sprintf('%s_%s_%dk.lac',ids{k},modes{m},rate));
                    encode_audio(input,path,cfg);
                end
            end
        end
        pac.write_json(fullfile(out,'baseline_regression.json'),regression);
    case 'decode'
        files=dir(fullfile(out,'*.lac')); summary=struct([]);
        assert(~isempty(files),'pac:Input','Run stage5_temporal(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(files(k).folder,files(k).name);
            [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
            info.file=files(k).name;
            if k==1, summary=info; else, summary(k)=info; end
        end
        pac.write_json(fullfile(out,'decode_verification.json'),summary);
        fprintf('Decoded %d files using the unchanged standalone decoder.\n',numel(files));
    case 'evaluate'
        pac.evaluate_conditions(root,out,ids,[{'baseline'},modes]);
        plot_example(root,out);
end
end

function cfg=mode_config(mode,rate)
cfg=codec_config(); cfg.targetKbps=rate;
cfg.features.temporalMasking=~strcmp(mode,'baseline');
cfg.pam.temporal.postMasking=~strcmp(mode,'temporal_preecho_only');
cfg.pam.temporal.preEchoControl=~strcmp(mode,'temporal_post_only');
end

function plot_example(root,out)
data=load(fullfile(root,'outputs','prepared','castanets.mat'),'x');
bands=pac.bands(); X=pac.analyze(data.x);
cfg=codec_config(); [a0,T0]=pac.pam(X,cfg,bands);
cfg.features.temporalMasking=true; [a1,T1,details]=pac.pam(X,cfg,bands);
% Illustrative frame chosen by largest threshold reduction, not quality gain.
change=mean(10*log10(T1./T0),1);
[~,frame]=min(change);
time=((frame-1)*1024-0.5)/48000;
d0=load(fullfile(out,'castanets_baseline_96k.lac.diagnostics.mat'),'widths');
d1=load(fullfile(out,'castanets_temporal_96k.lac.diagnostics.mat'),'widths');
fig=figure('Visible','off','Color','w','Theme','light','Position',[100 100 1100 760]);
guard=onCleanup(@() close(fig));
tiledlayout(2,1,'TileSpacing','compact');
nexttile;
semilogx(bands.frequency,10*log10(max(X(:,frame).^2/1024,1e-16)), ...
    'Color',[.45 .5 .6]); hold on
semilogx(bands.frequency,10*log10(T0(:,frame)/1024),'LineWidth',1.5);
semilogx(bands.frequency,10*log10(T1(:,frame)/1024),'LineWidth',1.5);
grid on; xlim([20 24000]); ylim([-130 0]);
xlabel('Frequency (Hz)'); ylabel('Bin power (dB re mean-square 1; not PSD)');
title(sprintf('Castanets frame %d, center %.4f s: temporal masking',frame,time));
subtitle('X^2 / 1024; unity mean-square assumed 96 dB SPL');
legend('Input MDCT spectrum','Baseline global threshold','Temporal global threshold','Location','southwest');
nexttile;
bar([d0.widths(:,frame),d1.widths(:,frame)]);
xlabel('Auditory band (ascending frequency)'); ylabel('Bits per coefficient');
title('Actual allocation at 96 kb/s (same quantizer and file budget)');
legend('Baseline','Temporal'); grid on
exportgraphics(fig,fullfile(out,'temporal_masking_comparison.png'),'Resolution',160);
frameData=struct('source','castanets','frame',frame,'centerTime',time, ...
    'selection','Largest mean log-threshold reduction; not selected for quality gain', ...
    'baselineAllowance',a0(:,frame),'temporalAllowance',a1(:,frame), ...
    'baselineWidth',d0.widths(:,frame),'temporalWidth',d1.widths(:,frame), ...
    'postRaisedBands',nnz(details.temporal.postRaised(:,frame)), ...
    'preEchoLimitedBands',nnz(details.temporal.preEchoLimited(:,frame)));
pac.write_json(fullfile(out,'masking_frame.json'),frameData);
save(fullfile(out,'masking_curves.mat'),'T0','T1','frame','cfg','details');
end
