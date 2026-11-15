function stage12_experiments(action)
%STAGE12_EXPERIMENTS Encode, fresh-process decode, and evaluate development clips.
arguments
    action (1,:) char {mustBeMember(action,{'encode','decode','evaluate'})}
end
root=fileparts(mfilename('fullpath')); out=fullfile(root,'outputs','experiments');
if ~isfolder(out), mkdir(out); end
options={'zeroRun','fileHuffman','smartQuantizer','perceptualEntropy','variableWindows'};
switch action
    case 'encode'
        for source={'harpsichord','castanets'}
            input=fullfile(root,'outputs','prepared',[source{1} '.mat']);
            for mode={'baseline','zeroRun','fileHuffman','windowHuffman','smartQuantizer','perceptualEntropy','variableWindows','peWindows','all'}
                for rate={'cbr','vbr'}
                    cfg=codec_config(); cfg.rateMode=rate{1};
                    if ismember(mode{1},options), cfg.experiments.(mode{1})=true; end
                    if strcmp(mode{1},'windowHuffman')
                        cfg.experiments.fileHuffman=true; cfg.experiments.huffmanScope='window';
                    elseif strcmp(mode{1},'peWindows')
                        cfg.experiments.perceptualEntropy=true; cfg.experiments.variableWindows=true;
                    elseif strcmp(mode{1},'all')
                        for k=1:5, cfg.experiments.(options{k})=true; end
                        cfg.experiments.huffmanScope='window';
                    end
                    encode_audio(input,fullfile(out,sprintf('%s_%s_%s.lac',source{1},mode{1},rate{1})),cfg);
                end
            end
            for rate=[64 128]
                cfg=codec_config(); cfg.targetKbps=rate;
                for k=1:5, cfg.experiments.(options{k})=true; end
                cfg.experiments.huffmanScope='window'; cfg.reservoir.enabled=true; cfg.allocation.enabled=true;
                encode_audio(input,fullfile(out,sprintf('%s_all_bucket_%dk.lac',source{1},rate)),cfg);
            end
        end
    case 'decode'
        files=dir(fullfile(out,'*.lac')); assert(numel(files)==40,'pac:Input','Run encode first.');
        for k=1:numel(files)
            path=fullfile(out,files(k).name); [y,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
            assert(numel(y)==480000 && info.sampleRate==48000);
        end
        pac.write_json(fullfile(out,'fresh_decode.json'),struct('files',numel(files),'samples',480000));
        fprintf('PASS: %d fresh-process experimental decodes.\n',numel(files));
    case 'evaluate'
        files=dir(fullfile(out,'*.lac')); rows=struct([]);
        for k=1:numel(files)
            path=fullfile(out,files(k).name); st=jsondecode(fileread([path '.json']));
            [x,fs]=pac.read_input(st.input); y=audioread([path(1:end-4) '_decoded.wav']); error=x-y;
            [pre,post]=pac.onset_windows(x,fs);
            row=struct('file',files(k).name,'bytes',st.totalBytes,'actualKbps',st.actualKbps, ...
                'sizeReductionPercent',st.sizeReductionPercent,'snrDB',10*log10(sum(x.^2)/sum(error.^2)), ...
                'preOnsetMSE',mean(error(pre).^2),'postOnsetMSE',mean(error(post).^2), ...
                'paddingBits',st.paddingBits,'fileBookUsed',false,'windowBooks',0,'shortFrames',0, ...
                'listening','Not yet assessed');
            if st.version==5
                row.fileBookUsed=st.fileBookUsed; row.windowBooks=st.windowBooksUsed; row.shortFrames=st.shortFrames;
            end
            if k==1, rows=row; else, rows(k)=row; end
        end
        writetable(struct2table(rows),fullfile(out,'measurements.csv')); pac.write_json(fullfile(out,'measurements.json'),rows);
        disp(struct2table(rows));
end
end
