function stage8_coding_features(action)
%STAGE8_CODING_FEATURES Compare optional coding tools with fixed PAM settings.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=fileparts(mfilename('fullpath')); ids={'harpsichord','castanets'};
groups={'baseline_pam','all_pam'};
for group=1:2
    pamMask=15*(group-1); out=fullfile(root,'outputs','coding_features',groups{group});
    if ~isfolder(out), mkdir(out); end
    modes=cell(1,4);
    for flags=0:3, modes{flags+1}=pac.model_name(config(pamMask,flags,96)); end
    switch action
        case 'encode'
            regression=struct([]); n=0;
            for k=1:numel(ids)
                input=fullfile(root,'outputs','prepared',[ids{k} '.mat']);
                for rate=[64 96 128]
                    for flags=0:3
                        cfg=config(pamMask,flags,rate); mode=pac.model_name(cfg);
                        name=sprintf('%s_%s_%dk.lac',ids{k},mode,rate); path=fullfile(out,name);
                        encode_audio(input,path,cfg);
                        if flags==0
                            original=fullfile(root,'outputs','pam_options',name);
                            assert(isfile(original),'pac:Input','Run stage7_pam_options(''encode'') first.');
                            assert(isequal(pac.file_bytes(original),pac.file_bytes(path)), ...
                                'pac:Regression','Previous PAM-only bytes changed.');
                            n=n+1; regression(n).file=name; regression(n).identicalBytes=true;
                        end
                    end
                end
            end
            pac.write_json(fullfile(out,'regression.json'),regression);
        case 'decode'
            files=dir(fullfile(out,'*.lac')); summary=struct([]);
            assert(numel(files)==24,'pac:Input','Run stage8_coding_features(''encode'') first.');
            for k=1:numel(files)
                path=fullfile(files(k).folder,files(k).name);
                [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']); info.file=files(k).name;
                if k==1, summary=info; else, summary(k)=info; end
            end
            pac.write_json(fullfile(out,'decode_verification.json'),summary);
            fprintf('Decoded 24 %s files in a separate process.\n',groups{group});
        case 'evaluate'
            pac.evaluate_conditions(root,out,ids,modes);
    end
end
if strcmp(action,'evaluate'), plot_example(root); end
end

function cfg=config(mask,flags,rate)
cfg=pac.pam_config(mask,rate); cfg.features.huffman=bitand(flags,1)~=0;
cfg.features.bandwidthExtension=bitand(flags,2)~=0;
end

function plot_example(root)
out=fullfile(root,'outputs','coding_features');
data=load(fullfile(root,'outputs','prepared','harpsichord.mat'),'x');
X=pac.analyze(data.x); frame=95; freq=((0:1023)'+.5)*48000/2048;
spectra=zeros(1024,4); spectra(:,1)=X(:,frame);
modes={'baseline','huffman','huffman_bwe'};
for k=1:3
    y=decode_audio(fullfile(out,'baseline_pam',sprintf('harpsichord_%s_96k.lac',modes{k})));
    Y=pac.analyze(y); spectra(:,k+1)=Y(:,frame);
end
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 1100 550]);
guard=onCleanup(@() close(fig));
plot(freq/1000,10*log10(max(spectra.^2/1024,1e-16)),'LineWidth',1);
xline(12,'--','BWE boundary'); grid on; xlim([0 24]); ylim([-140 0]);
xlabel('Frequency (kHz)'); ylabel('Bin power (dB re mean-square 1)');
title('Harpsichord frame 95 (2.0053 s), 96 kb/s, baseline PAM');
subtitle('Reanalyzed decoded audio; X^2 / 1024, not PSD; original playback levels');
legend('Original','Direct packing','Huffman','Huffman + BWE','Location','southwest');
exportgraphics(fig,fullfile(out,'coding_comparison.png'),'Resolution',150);
end
