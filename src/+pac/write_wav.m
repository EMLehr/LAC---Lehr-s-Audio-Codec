function write_wav(path,x,fs)
%WRITE_WAV IEEE float WAV, preserving decoder levels including overshoots.
% Avoid implicit PCM clipping/normalization. Standard little-endian RIFF.
assert(numel(x)*4+50 < 2^32,'pac:WAV','WAV exceeds RIFF size limit.');
fid = fopen(path,'w','ieee-le');
assert(fid>=0,'pac:IO','Cannot open %s',path);
guard = onCleanup(@() fclose(fid));
fwrite(fid,'RIFF','char'); fwrite(fid,50+4*numel(x),'uint32');
fwrite(fid,'WAVEfmt ','char'); fwrite(fid,18,'uint32');
fwrite(fid,[3,1],'uint16'); % IEEE float, mono
fwrite(fid,[fs,4*fs],'uint32'); fwrite(fid,[4,32,0],'uint16');
fwrite(fid,'fact','char'); fwrite(fid,4,'uint32'); fwrite(fid,numel(x),'uint32');
fwrite(fid,'data','char'); fwrite(fid,4*numel(x),'uint32'); fwrite(fid,single(x),'single');
end
