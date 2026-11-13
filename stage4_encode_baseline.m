function stage4_encode_baseline(includeHeldOut)
%STAGE4_ENCODE_BASELINE Generate all development conditions; holdout is opt-in.
if nargin<1, includeHeldOut=false; end
root=fileparts(mfilename('fullpath'));
out=fullfile(root,'outputs','baseline');
if ~isfolder(out), mkdir(out); end
ids={'harpsichord','castanets'};
if includeHeldOut, ids{end+1}='speech'; end
for k=1:numel(ids)
    for rate=[64 96 128]
        cfg=codec_config(); cfg.targetKbps=rate;
        encode_audio(fullfile(root,'outputs','prepared',[ids{k} '.mat']), ...
            fullfile(out,sprintf('%s_baseline_%dk.lac',ids{k},rate)),cfg);
    end
end
end
