function write_json(path,value)
fid = fopen(path,'w');
assert(fid>=0,'pac:IO','Cannot open %s',path);
guard = onCleanup(@() fclose(fid));
fprintf(fid,'%s\n',jsonencode(value,PrettyPrint=true));
end
