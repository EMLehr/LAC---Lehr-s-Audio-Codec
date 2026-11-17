function y = synthesize(X,sampleCount)
%SYNTHESIZE Inverse MDCT, sine window, overlap-add, exact delay/length removal.
N = 1024;
validateattributes(X,{'double'},{'real','finite','2d','nrows',N});
validateattributes(sampleCount,{'numeric'},{'scalar','integer','positive'});
assert(size(X,2) == ceil(double(sampleCount)/N)+1, ...
    'pac:Length','Frame count disagrees with original sample count.');
[A,w] = pac.basis();
frames = (A*X).*w;
y = zeros((size(X,2)+1)*N,1);
for f = 1:size(X,2)
    idx = (1:2*N)+(f-1)*N;
    y(idx) = y(idx)+frames(:,f);
end
y = y(N+(1:double(sampleCount)));
end
