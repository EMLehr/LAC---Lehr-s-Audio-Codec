function stage10_vbr(action)
%STAGE10_VBR Development comparisons at three PAM-relative quality targets.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=fileparts(mfilename('fullpath')); out=fullfile(root,'outputs','vbr');
if ~isfolder(out), mkdir(out); end
recipes=[0 0;1 0;2 0;4 0;8 0;15 0;0 1;0 2;0 3;15 1;15 2;15 3];
switch action
    case 'encode'
        for source={'harpsichord','castanets'}
            for quality=[-6 0 6]
                for k=1:size(recipes,1)
                    cfg=pac.pam_config(recipes(k,1)); cfg.rateMode='vbr'; cfg.vbr.distortionDB=quality;
                    cfg.features.huffman=bitand(recipes(k,2),1)~=0;
                    cfg.features.bandwidthExtension=bitand(recipes(k,2),2)~=0;
                    path=fullfile(out,sprintf('%s_%s_vbr_%+ddB.lac',source{1},pac.model_name(cfg),quality));
                    encode_audio(fullfile(root,'outputs','prepared',[source{1} '.mat']),path,cfg);
                end
            end
        end
    case 'decode'
        files=dir(fullfile(out,'*.lac')); rows=struct([]);
        assert(numel(files)==72,'pac:Input','Run stage10_vbr(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(out,files(k).name);
            [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']); info.file=files(k).name;
            if k==1, rows=info; else, rows(k)=info; end
        end
        pac.write_json(fullfile(out,'decode_verification.json'),rows);
        fprintf('Decoded %d VBR files in a fresh process.\n',numel(files));
    case 'evaluate'
        files=dir(fullfile(out,'*.lac')); rows=struct([]);
        assert(numel(files)==72,'pac:Input','Run stage10_vbr(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(out,files(k).name); st=jsondecode(fileread([path '.json']));
            [~,source]=fileparts(st.input); [x,fs]=pac.read_input(st.input);
            [y,fsY]=audioread([path(1:end-4) '_decoded.wav']);
            assert(fs==fsY && numel(x)==numel(y)); e=x-y;
            [pre,post,onsets]=pac.onset_windows(x,fs);
            d=load([path '.diagnostics.mat'],'frameBytes');
            row=struct('source',source,'model',st.model,'distortionDB',st.vbrDistortionDB, ...
                'bytes',st.totalBytes,'actualKbps',st.actualKbps,'compressionRatio',st.compressionRatio, ...
                'sizeReductionPercent',st.sizeReductionPercent,'snrDB',10*log10(sum(x.^2)/sum(e.^2)), ...
                'rmse',sqrt(mean(e.^2)),'preOnsetMSE',mean(e(pre).^2),'postOnsetMSE',mean(e(post).^2), ...
                'onsets',numel(onsets),'headerBits',8*st.headerBytes,'framingBits',st.framingBits, ...
                'sideBits',st.frameSideBits,'coefficientBits',st.coefficientBits,'paddingBits',st.paddingBits, ...
                'minFrameBytes',min(d.frameBytes),'maxFrameBytes',max(d.frameBytes), ...
                'coreTargetMisses',st.coreTargetMisses,'bandsOverScaledTarget',st.bandsOverScaledTarget, ...
                'listening','Not yet assessed');
            if k==1, rows=row; else, rows(k)=row; end
        end
        results=struct2table(rows); writetable(results,fullfile(out,'measurements.csv'));
        pac.write_json(fullfile(out,'measurements.json'),rows);
        disp(results(results.distortionDB==0,{'source','model','actualKbps','sizeReductionPercent','snrDB'}));
        plot_frames(out);
end
end

function plot_frames(out)
fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 1000 500]);
guard=onCleanup(@() close(fig));
for model={'baseline','huffman','tonal_temporal_spreading_mapping'}
    d=load(fullfile(out,['harpsichord_' model{1} '_vbr_+0dB.lac.diagnostics.mat']),'frameBytes');
    plot((0:numel(d.frameBytes)-1)*1024/48000,8*(d.frameBytes+2)/(1024/48000)/1000); hold on
end
grid on; xlabel('Frame time (s)'); ylabel('Frame rate including 2-byte prefix (kb/s)');
title('Harpsichord VBR at 0 dB allowance scale');
subtitle('Frame rates use a 1024-sample hop; file bitrate counts all bytes over the original 10 seconds');
xlim([0 10.01]);
legend('Baseline PAM','Baseline PAM + Huffman','All four PAM options','Location','best');
exportgraphics(fig,fullfile(out,'frame_rates.png'),'Resolution',150);
end
