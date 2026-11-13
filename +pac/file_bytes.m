function bytes = file_bytes(path)
%FILE_BYTES Read raw bytes for bitstream regression checks.
fid=fopen(path,'r');
assert(fid>=0,'pac:IO','Cannot open %s',path);
guard=onCleanup(@() fclose(fid));
bytes=fread(fid,inf,'*uint8');
end
