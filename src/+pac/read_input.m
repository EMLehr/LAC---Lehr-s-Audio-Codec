function [x,fs] = read_input(path)
[~,~,ext]=fileparts(path);
if strcmpi(ext,'.mat')
    data=load(path,'x','fs'); x=data.x; fs=data.fs;
else
    [x,fs]=audioread(path);
end
assert(fs==48000 && size(x,2)==1,'pac:Input', ...
    'Encoder requires prepared 48 kHz mono input. Run stage1_prepare_inputs.');
validateattributes(x,{'double'},{'real','finite','vector','nonempty'});
x=x(:);
assert(max(abs(x))<=1,'pac:Input','Input exceeds full-scale range [-1,1].');
end
