function source = listening_import(root,path)
%LISTENING_IMPORT Prepare a full custom clip without changing its source file.
[x,inputRate]=audioread(path);
validateattributes(x,{'double'},{'real','finite','nonempty','2d'});
channels=size(x,2); inputSamples=size(x,1);
x=mean(x,2); fs=48000;
if inputRate~=fs
    assert(exist('resample','file')==2,'pac:Input', ...
        'Resampling requires Signal Processing Toolbox. Alternatively select a 48 kHz file.');
    [p,q]=rat(fs/inputRate); x=resample(x,p,q);
end
assert(max(abs(x))<=1,'pac:Input', ...
    'Prepared audio exceeds full scale. Lower the source level and import again; no automatic normalization is applied.');
[~,name,ext]=fileparts(path);
metadata=struct('filename',[name ext],'originalPath',char(java.io.File(path).getCanonicalPath()), ...
    'originalSampleRate',inputRate,'originalChannels',channels,'originalSamples',inputSamples, ...
    'sampleRate',fs,'samples',numel(x),'durationSeconds',numel(x)/fs, ...
    'preparation','Full file; channels averaged; resampled to 48 kHz if needed; no normalization');
digest=java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(x(:),'int8'));
key=lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[]));
folder=fullfile(root,'outputs','listening','imports');
if ~isfolder(folder), mkdir(folder); end
input=fullfile(folder,[key '.mat']);
if ~isfile(input), save(input,'x','fs','-v7.3'); end
source=struct('input',input,'metadata',metadata);
end
