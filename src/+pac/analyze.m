function X = analyze(x)
%ANALYZE One leading hop plus enough trailing zeros for complete TDAC.
validateattributes(x,{'double'},{'real','finite','vector','nonempty'});
x = x(:);
N = 1024;
F = ceil(numel(x)/N)+1;
xp = [zeros(N,1); x; zeros((F+1)*N-N-numel(x),1)];
indices = (1:2*N)' + (0:F-1)*N;
[A,w] = pac.basis();
X = A'*(xp(indices).*w);
end
