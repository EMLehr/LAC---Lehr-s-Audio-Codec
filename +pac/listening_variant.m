function result = listening_variant(root,source,cfg,original)
%LISTENING_VARIANT Load original or a content-keyed, independently decoded cache.
assert(ismember(source,{'harpsichord','castanets','speech'}),'pac:Input','Unknown excerpt.');
input=fullfile(root,'outputs','prepared',[source '.mat']);
assert(isfile(input),'pac:Input','Prepared audio missing. Run stage1_prepare_inputs first.');
[x,fs]=pac.read_input(input);
result=struct('x',x,'fs',fs,'source',source,'model','original','path',input, ...
    'config',cfg,'original',original,'actualKbps',768,'bytes',2*numel(x),'cacheHit',false, ...
    'sizeReductionPercent',0,'rateMode','original');
if original, return; end
pac.validate_config(cfg);
% Hash samples, exact configuration, and codec implementation. GUI changes
% do not invalidate audio; a source/codec/configuration change always does.
digest=java.security.MessageDigest.getInstance('SHA-256');
add(typecast(x(:),'uint8')); add(unicode2native(jsonencode(cfg),'UTF-8'));
files=[dir(fullfile(root,'+pac','*.m'));dir(fullfile(root,'codec_config.m')); ...
    dir(fullfile(root,'encode_audio.m'));dir(fullfile(root,'decode_audio.m'))];
for k=1:numel(files)
    if startsWith(files(k).name,'listening_') || strcmp(files(k).name,'ListeningApp.m'), continue; end
    add(unicode2native(files(k).name,'UTF-8'));
    add(unicode2native(fileread(fullfile(files(k).folder,files(k).name)),'UTF-8'));
end
key=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[]));
folder=fullfile(root,'outputs','listening','cache');
if ~isfolder(folder), mkdir(folder); end
[mode,~]=pac.rate_settings(cfg);
path=fullfile(folder,sprintf('%s_%s_%s.lac',source,mode,key));
result.cacheHit=isfile(path);
if ~result.cacheHit
    temporary=[tempname(folder) '.lac'];
    guard=onCleanup(@() remove_temporary(temporary));
    stats=encode_audio(input,temporary,cfg);
    % Verify the complete file before making it available as a cache entry.
    [decoded,info]=decode_audio(temporary);
    assert(numel(decoded)==numel(x) && info.sampleRate==fs,'pac:Format','Decoded length mismatch.');
    stats.output=path; pac.write_json([temporary '.json'],stats);
    movefile([temporary '.diagnostics.mat'],[path '.diagnostics.mat']);
    movefile([temporary '.json'],[path '.json']);
    movefile(temporary,path);
    clear guard
else
    [decoded,info]=decode_audio(path);
end
assert(numel(decoded)==numel(x) && info.sampleRate==fs,'pac:Format','Cached audio mismatch.');
wav=[path(1:end-4) '_decoded.wav'];
if ~isfile(wav), pac.write_wav(wav,decoded,fs); end
result.x=decoded; result.path=path; result.actualKbps=info.actualKbps;
result.bytes=info.totalBytes; result.model=pac.model_name(cfg);
result.sizeReductionPercent=info.sizeReductionPercent; result.rateMode=info.rateMode;
    function add(bytes)
        digest.update(typecast(uint8(bytes(:)),'int8'));
    end
end

function remove_temporary(path)
for suffix={'','.json','.diagnostics.mat'}
    item=[path suffix{1}]; if isfile(item), delete(item); end
end
end
