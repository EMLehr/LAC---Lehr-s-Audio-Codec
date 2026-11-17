function [headerBytes,nominal,capacityBytes]=reservoir_layout(L,F,B,rate,extra,capacityFrames)
%RESERVOIR_LAYOUT Fixed total bytes; reserve header and two-byte frame prefixes.
headerBytes=40+2*(B+1);
pool=floor(double(L)/48000*rate*1000/8)-headerBytes-2*F;
assert(pool>=F*ceil((4*B+extra)/8),'pac:Budget','Clip cannot fit reservoir framing at this rate.');
nominal=diff(floor((0:F)*pool/F)); capacityBytes=floor(capacityFrames*pool/F);
assert(max(nominal)+capacityBytes<=65535,'pac:Budget','Reservoir and frame budget exceed uint16 length.');
end
