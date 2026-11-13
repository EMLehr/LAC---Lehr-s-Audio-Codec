function stage7_pam_options(action)
%STAGE7_PAM_OPTIONS Run all 16 combinations of the four PAM switches.
% Does not use held-out speech and does not create a listening interface.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=fileparts(mfilename('fullpath')); out=fullfile(root,'outputs','pam_options');
if ~isfolder(out), mkdir(out); end
ids={'harpsichord','castanets'}; modes=cell(1,16);
for mask=0:15, modes{mask+1}=pac.model_name(pac.pam_config(mask)); end
assert(numel(unique(modes))==16,'pac:Config','Mode labels must be unique.');
switch action
    case 'encode'
        regression=struct([]); n=0;
        for k=1:numel(ids)
            input=fullfile(root,'outputs','prepared',[ids{k} '.mat']);
            for rate=[64 96 128]
                for mask=0:15
                    cfg=pac.pam_config(mask,rate); mode=pac.model_name(cfg);
                    name=sprintf('%s_%s_%dk.lac',ids{k},mode,rate);
                    if mask<4
                        original=fullfile(root,'outputs','tonality',name);
                        assert(isfile(original),'pac:Input','Run stage6_tonality(''encode'') first.');
                    end
                    path=fullfile(out,name); encode_audio(input,path,cfg);
                    if mask<4
                        assert(isequal(pac.file_bytes(original),pac.file_bytes(path)), ...
                            'pac:Regression','Existing %s bitstream changed.',mode);
                        n=n+1; row=struct('source',ids{k},'model',mode,'rate',rate,'identicalBytes',true);
                        if n==1, regression=row; else, regression(n)=row; end
                    end
                end
            end
        end
        pac.write_json(fullfile(out,'regression.json'),regression);
    case 'decode'
        files=dir(fullfile(out,'*.lac')); summary=struct([]);
        assert(~isempty(files),'pac:Input','Run stage7_pam_options(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(files(k).folder,files(k).name);
            [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
            info.file=files(k).name;
            if k==1, summary=info; else, summary(k)=info; end
        end
        pac.write_json(fullfile(out,'decode_verification.json'),summary);
        fprintf('Decoded %d PAM comparison files with the unchanged decoder.\n',numel(files));
    case 'evaluate'
        results=pac.evaluate_conditions(root,out,ids,modes);
        selected=ismember(results.model,{'baseline','spreading','mapping', ...
            'spreading_mapping','tonal_temporal_spreading_mapping'});
        writetable(results(selected,:),fullfile(out,'selected_measurements.csv'));
        pac.write_json(fullfile(out,'selected_measurements.json'),table2struct(results(selected,:)));
        plot_example(root,out);
end
end

function plot_example(root,out)
data=load(fullfile(root,'outputs','prepared','harpsichord.mat'),'x');
X=pac.analyze(data.x); bands=pac.bands(); frame=95;
names={'baseline','spreading','mapping','spreading_mapping','tonal_temporal_spreading_mapping'};
masks=[0 4 8 12 15]; allowances=zeros(numel(bands.count),5);
curves=zeros(1024,5); widths=zeros(numel(bands.count),5);
for k=1:5
    cfg=pac.pam_config(masks(k)); [a,T,details]=pac.pam(X,cfg,bands);
    allowances(:,k)=a(:,frame); curves(:,k)=T(:,frame);
    d=load(fullfile(out,sprintf('harpsichord_%s_96k.lac.diagnostics.mat',names{k})),'widths');
    widths(:,k)=d.widths(:,frame);
    if k==2, spreading=details.spreading; end
end
assert(isequal(curves(:,1),curves(:,3)),'Mapping must not change masking curves.');
time=((frame-1)*1024-0.5)/48000;
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 50 1150 950]);
guard=onCleanup(@() close(fig));
tiledlayout(3,1,'TileSpacing','compact'); nexttile;
semilogx(bands.frequency,10*log10(max(X(:,frame).^2/1024,1e-16)), ...
    'Color',[.5 .55 .6]); hold on
semilogx(bands.frequency,10*log10(curves(:,1)/1024),'LineWidth',1.5);
semilogx(bands.frequency,10*log10(curves(:,2)/1024),'LineWidth',1.5,'Color',[0 .4 .2]);
semilogx(bands.frequency,10*log10(curves(:,5)/1024),'--','LineWidth',1.5,'Color',[.5 .1 .6]);
xlim([20 24000]); ylim([-130 0]); grid on
xlabel('Frequency (Hz)'); ylabel('Bin power (dB re mean-square 1)');
title(sprintf('Harpsichord frame %d, center %.4f s: PAM options',frame,time));
subtitle('X^2 / 1024 (not PSD); unity mean-square assumed 96 dB SPL');
legend('Input','Baseline (also mapping-only)','Variable spreading','All four options','Location','southwest');
nexttile;
plot(10*log10(allowances(:,[1 2 3 5])/1024),'LineWidth',1.4); grid on
xlabel('Auditory band (ascending frequency)'); ylabel('Band allowance (dB re mean-square 1)');
title('Mapping changes band allowances even when the global curve is unchanged');
legend('Baseline sum','Variable spreading + sum','Harmonic mapping','All four','Location','eastoutside');
nexttile; bar(widths(:,[1 2 3 5])); grid on
xlabel('Auditory band (ascending frequency)'); ylabel('Bits per coefficient');
title('Actual allocation at 96 kb/s; identical quantizer and file budget');
legend('Baseline','Variable spreading','Harmonic mapping','All four','Location','eastoutside');
exportgraphics(fig,fullfile(out,'final_pam_comparison.png'),'Resolution',160);
frameData=struct('source','harpsichord','frame',frame,'centerTime',time, ...
    'selection','Same fixed frame as baseline and tonal examples','models',{names}, ...
    'allowances',allowances,'widths',widths, ...
    'upperSlopes',spreading.upperSlope(:,frame),'maskerLevels',spreading.sourceLevelDB(:,frame));
pac.write_json(fullfile(out,'masking_frame.json'),frameData);
save(fullfile(out,'masking_frame.mat'),'curves','allowances','widths','frame','spreading');
end
