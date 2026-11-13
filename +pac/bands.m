function bands = bands()
%BANDS Fixed one-Bark groups, shared by baseline and future PAM variants.
f = ((0:1023)'+0.5)*48000/2048;
z = 13*atan(0.00076*f)+3.5*atan((f/7500).^2);
labels = floor(z);
starts = [1; find(diff(labels)~=0)+1];
bands.edges = [starts; 1025]; % MATLAB indices, final edge exclusive.
bands.count = diff(bands.edges);
bands.frequency = f;
bands.bark = z;
bands.centers = zeros(numel(starts),1);
for b = 1:numel(starts)
    bands.centers(b) = mean(z(bands.edges(b):bands.edges(b+1)-1));
end
end
