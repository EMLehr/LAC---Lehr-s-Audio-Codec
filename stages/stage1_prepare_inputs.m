function manifest = stage1_prepare_inputs(outputDir)
%STAGE1_PREPARE_INPUTS Prepare once; MAT doubles are authoritative inputs.
root = pac.project_root();
if nargin < 1, outputDir = fullfile(root,'outputs','prepared'); end
if ~isfolder(outputDir), mkdir(outputDir); end
assert(exist('resample','file')==2,'pac:Dependency', ...
    'Input preparation requires Signal Processing Toolbox resample.');
sources = {'harpsichord','40_harpsichord_arpegio_melodious_phrase_stereo.wav'; ...
    'castanets','27_castanets_single_tone_rhythm_stereo.wav'; ...
    'speech','49_female_speech_english_mono.wav'};
manifest = struct([]);
for k = 1:size(sources,1)
    source = fullfile(root,sources{k,2});
    info = audioinfo(source);
    assert(info.TotalSamples >= 10*info.SampleRate,'pac:Input','Source is shorter than 10 seconds.');
    [x,fsIn] = audioread(source,[1,10*info.SampleRate]);
    x = mean(x,2);
    [p,q] = rat(48000/fsIn);
    x = resample(x,p,q);
    assert(numel(x)==480000 && all(isfinite(x)),'pac:Input','Unexpected resampling result.');
    fs = 48000;
    id = sources{k,1};
    entry = struct('id',id,'source',sources{k,2},'sourceRate',fsIn, ...
        'sourceChannels',info.NumChannels,'samples',numel(x), ...
        'sampleRate',fs,'heldOut',strcmp(id,'speech'), ...
        'preparation','First 10 s; channel mean; resample default FIR; no gain normalization', ...
        'peak',max(abs(x)),'matlabVersion',version);
    save(fullfile(outputDir,[id '.mat']),'x','fs','entry');
    pac.write_wav(fullfile(outputDir,[id '.wav']),x,fs);
    if k == 1, manifest = entry; else, manifest(k) = entry; end
    fprintf('Prepared %s: %d samples at %d Hz; held out = %d\n',id,numel(x),fs,entry.heldOut);
end
pac.write_json(fullfile(outputDir,'manifest.json'),manifest);
end
