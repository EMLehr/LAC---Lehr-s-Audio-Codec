function bands = coding_bands(bandwidthExtension)
%CODING_BANDS Preserve baseline bands; split at 12 kHz only for BWE.
bands=pac.bands();
if ~bandwidthExtension, return; end
bands.edges=unique([bands.edges;513]); bands.count=diff(bands.edges);
bands.centers=zeros(numel(bands.count),1);
for b=1:numel(bands.count)
    bands.centers(b)=mean(bands.bark(bands.edges(b):bands.edges(b+1)-1));
end
end
