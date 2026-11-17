function [headerBytes,frameBytes] = layout(sampleCount,frameCount,bandCount,targetKbps,extraFrameBits)
%LAYOUT Deterministic byte schedule includes complete file overhead.
headerBytes=36+2*(bandCount+1);
if nargin<5, extraFrameBits=0; end
totalBytes=floor(double(sampleCount)/48000*targetKbps*1000/8);
payload=totalBytes-headerBytes;
assert(payload>=frameCount*ceil((4*bandCount+extraFrameBits)/8),'pac:Budget', ...
    'Input too short for this bitrate and mandatory headers. Use a longer input or higher rate.');
frameBytes=diff(floor((0:frameCount)*payload/frameCount));
end
