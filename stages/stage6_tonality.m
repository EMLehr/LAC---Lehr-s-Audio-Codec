function stage6_tonality(action)
%STAGE6_TONALITY Compare baseline, temporal, tonal, and both options together.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=pac.project_root(); out=fullfile(root,'outputs','tonality');
if ~isfolder(out), mkdir(out); end
ids={'harpsichord','castanets'};
modes={'baseline','temporal','tonal','tonal_temporal'};
switch action
    case 'encode'
        regression=struct([]); n=0;
        for k=1:numel(ids)
            input=fullfile(root,'outputs','prepared',[ids{k} '.mat']);
            for rate=[64 96 128]
                for m=1:numel(modes)
                    cfg=codec_config(); cfg.targetKbps=rate;
                    cfg.features.tonalMaskers=contains(modes{m},'tonal');
                    cfg.features.temporalMasking=contains(modes{m},'temporal');
                    name=sprintf('%s_%s_%dk.lac',ids{k},modes{m},rate);
                    path=fullfile(out,name);
                    if m<=2
                        original=fullfile(root,'outputs',modes{m},name);
                        assert(isfile(original),'pac:Input', ...
                            'Run stages 4 and 5 encoding first: missing %s',original);
                    end
                    encode_audio(input,path,cfg);
                    if m<=2
                        assert(isequal(pac.file_bytes(original),pac.file_bytes(path)), ...
                            'pac:Regression','Existing %s bytes changed.',modes{m});
                        n=n+1; row=struct('source',ids{k},'model',modes{m}, ...
                            'rate',rate,'identicalBytes',true);
                        if n==1, regression=row; else, regression(n)=row; end
                    end
                end
            end
        end
        pac.write_json(fullfile(out,'regression.json'),regression);
    case 'decode'
        files=dir(fullfile(out,'*.lac')); summary=struct([]);
        assert(~isempty(files),'pac:Input','Run stage6_tonality(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(files(k).folder,files(k).name);
            [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
            info.file=files(k).name;
            if k==1, summary=info; else, summary(k)=info; end
        end
        pac.write_json(fullfile(out,'decode_verification.json'),summary);
        fprintf('Decoded %d tonal-stage files using the unchanged decoder.\n',numel(files));
    case 'evaluate'
        pac.evaluate_conditions(root,out,ids,modes);
        plot_example(root,out);
end
end

function plot_example(root,out)
data=load(fullfile(root,'outputs','prepared','harpsichord.mat'),'x');
X=pac.analyze(data.x); bands=pac.bands(); cfg=codec_config();
[~,T0]=pac.pam(X,cfg,bands);
cfg.features.tonalMaskers=true; [~,T1,details]=pac.pam(X,cfg,bands);
cfg.features.temporalMasking=true; [~,T2]=pac.pam(X,cfg,bands);
frame=95; time=((frame-1)*1024-0.5)/48000;
names={'baseline','tonal','tonal_temporal'}; widths=zeros(numel(bands.count),3);
for k=1:3
    d=load(fullfile(out,sprintf('harpsichord_%s_96k.lac.diagnostics.mat',names{k})),'widths');
    widths(:,k)=d.widths(:,frame);
end
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 50 1100 950]);
guard=onCleanup(@() close(fig));
tiledlayout(3,1,'TileSpacing','compact'); nexttile;
semilogx(bands.frequency,10*log10(max(X(:,frame).^2/1024,1e-16)), ...
    'Color',[.5 .55 .6]); hold on
semilogx(bands.frequency,10*log10(T0(:,frame)/1024),'LineWidth',1.4);
semilogx(bands.frequency,10*log10(T1(:,frame)/1024),'Color',[.05 .4 .15],'LineWidth',1.4);
semilogx(bands.frequency,10*log10(T2(:,frame)/1024),'--','Color',[.5 .15 .7],'LineWidth',1.2);
xlim([20 24000]); ylim([-130 0]); grid on
xlabel('Frequency (Hz)'); ylabel('Bin power (dB re mean-square 1)');
title(sprintf('Harpsichord frame %d, center %.4f s: tonal/noise masking',frame,time));
subtitle('X^2 / 1024 (not PSD); unity mean-square assumed 96 dB SPL');
legend('Input spectrum','Baseline','Tonal/noise','Tonal/noise + temporal','Location','southwest');
nexttile;
bar(details.tonal.alpha(:,frame),'FaceColor',[.05 .4 .15]);
ylim([0 1]); grid on
xlabel('Auditory band (ascending frequency)'); ylabel('Tonality score');
title('Spectral flatness classification: 0 = noise-like, 1 = tonal');
nexttile;
bar(widths); grid on
xlabel('Auditory band (ascending frequency)'); ylabel('Bits per coefficient');
title('Actual allocation at 96 kb/s; identical quantizer and file budget');
legend('Baseline','Tonal/noise','Tonal/noise + temporal','Location','northeastoutside');
exportgraphics(fig,fullfile(out,'tonality_masking_comparison.png'),'Resolution',160);
frameData=struct('source','harpsichord','frame',frame,'centerTime',time, ...
    'selection','Same fixed frame 95 as initial baseline plot', ...
    'alpha',details.tonal.alpha(:,frame),'offsetDB',details.tonal.offsetDB(:,frame), ...
    'flatnessDB',details.tonal.flatnessDB(:,frame),'widths',widths);
pac.write_json(fullfile(out,'masking_frame.json'),frameData);
save(fullfile(out,'masking_curves.mat'),'T0','T1','T2','frame','cfg','details');
end
