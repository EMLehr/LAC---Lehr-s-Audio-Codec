function summary = stage4_decode_baseline()
%STAGE4_DECODE_BASELINE Run in a fresh MATLAB process; only .lac files are read.
root=pac.project_root();
out=fullfile(root,'outputs','baseline');
files=dir(fullfile(out,'*.lac'));
assert(~isempty(files),'pac:Input','Run stage4_encode_baseline first.');
summary=struct([]);
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    [y,info]=decode_audio(path,[path(1:end-4) '_decoded.wav']);
    assert(numel(y)==info.sampleCount);
    info.file=files(k).name;
    if k==1, summary=info; else, summary(k)=info; end
    fprintf('Decoded %s: %d samples, %.3f kb/s\n',files(k).name,info.sampleCount,info.actualKbps);
end
pac.write_json(fullfile(out,'decode_verification.json'),summary);
end
