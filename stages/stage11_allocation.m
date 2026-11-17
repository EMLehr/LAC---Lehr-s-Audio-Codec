function stage11_allocation(action)
%STAGE11_ALLOCATION Controlled bit-bucket and piecewise development runs.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=pac.project_root(); out=fullfile(root,'outputs','allocation');
if ~isfolder(out), mkdir(out); end
switch action
    case 'encode'
        for source={'harpsichord','castanets'}
            input=fullfile(root,'outputs','prepared',[source{1} '.mat']);
            for rate=[64 96 128]
                for mode={'baseline','bucket','piecewise','piecewise_bucket'}
                    cfg=codec_config(); cfg.targetKbps=rate;
                    cfg.allocation.enabled=contains(mode{1},'piecewise');
                    cfg.reservoir.enabled=contains(mode{1},'bucket');
                    path=fullfile(out,sprintf('%s_%s_%dk.lac',source{1},mode{1},rate));
                    encode_audio(input,path,cfg);
                    if strcmp(mode{1},'baseline')
                        original=fullfile(root,'outputs','baseline',sprintf('%s_baseline_%dk.lac',source{1},rate));
                        assert(isequal(pac.file_bytes(path),pac.file_bytes(original)));
                    end
                end
            end
            for mode={'vbr_final_limit','vbr_piecewise','vbr_partial_bottom','vbr_plus9','vbr_plus12'}
                cfg=codec_config(); cfg.rateMode='vbr'; cfg.vbr.distortionDB=-24;
                cfg.allocation.enabled=ismember(mode{1},{'vbr_piecewise','vbr_partial_bottom'});
                if strcmp(mode{1},'vbr_partial_bottom')
                    cfg.allocation.savedNumerator(3)=3; cfg.allocation.savedDenominator(3)=4;
                elseif strcmp(mode{1},'vbr_plus9'), cfg.vbr.distortionDB=9;
                elseif strcmp(mode{1},'vbr_plus12'), cfg.vbr.distortionDB=12;
                end
                encode_audio(input,fullfile(out,sprintf('%s_%s.lac',source{1},mode{1})),cfg);
            end
        end
    case 'decode'
        files=dir(fullfile(out,'*.lac')); rows=struct([]);
        assert(numel(files)==34,'pac:Input','Run stage11_allocation(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(out,files(k).name); [~,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
            info.file=files(k).name; if k==1, rows=info; else, rows(k)=info; end
        end
        pac.write_json(fullfile(out,'decode_verification.json'),rows);
        fprintf('Decoded %d allocation comparison files in a fresh process.\n',numel(files));
    case 'evaluate'
        files=dir(fullfile(out,'*.lac')); rows=struct([]);
        assert(numel(files)==34,'pac:Input','Run stage11_allocation(''encode'') first.');
        for k=1:numel(files)
            path=fullfile(out,files(k).name); st=jsondecode(fileread([path '.json']));
            [x,fs]=pac.read_input(st.input); [y,fsY]=audioread([path(1:end-4) '_decoded.wav']);
            assert(fs==fsY && numel(x)==numel(y)); e=x-y; [pre,post,onsets]=pac.onset_windows(x,fs);
            row=struct('file',files(k).name,'rateMode',st.rateMode,'actualKbps',st.actualKbps, ...
                'bytes',st.totalBytes,'sizeReductionPercent',st.sizeReductionPercent, ...
                'snrDB',10*log10(sum(x.^2)/sum(e.^2)),'preOnsetMSE',mean(e(pre).^2), ...
                'postOnsetMSE',mean(e(post).^2),'onsets',numel(onsets), ...
                'paddingBits',st.paddingBits,'borrowedBytes',st.borrowedBytes, ...
                'bucketCapacityBytes',st.reservoirCapacityBytes,'bucketPeakBytes',st.reservoirPeakBytes, ...
                'ratioReservedBits',sum(st.policyReservedBits),'policyBandsAboveLimit',st.policyBandsAboveLimit, ...
                'bandsOverScaledTarget',st.bandsOverScaledTarget,'listening','Not yet assessed');
            if k==1, rows=row; else, rows(k)=row; end
        end
        results=struct2table(rows); writetable(results,fullfile(out,'measurements.csv'));
        pac.write_json(fullfile(out,'measurements.json'),rows);
        disp(results(:,{'file','actualKbps','snrDB','borrowedBytes','ratioReservedBits'}));
        fig=figure('Visible','off','Theme','light','Color','w','Position',[100 100 1050 650]);
        guard=onCleanup(@() close(fig)); tiledlayout(2,1);
        for mode={'bucket','piecewise_bucket'}
            d=load(fullfile(out,['harpsichord_' mode{1} '_96k.lac.diagnostics.mat']));
            t=(0:numel(d.frameBytes)-1)*1024/48000;
            nexttile; plot(t,d.reservoirAfter,'LineWidth',1.2); hold on
            plot(t,d.borrowedBytes,'LineWidth',1); grid on
            xlabel('Frame time (s)'); ylabel('Bytes'); title(strrep(mode{1},'_',' '));
            legend('Saved bucket balance after frame','Borrowed for coefficient payload','Location','best');
        end
        exportgraphics(fig,fullfile(out,'bucket_balance.png'),'Resolution',150);
end
end
