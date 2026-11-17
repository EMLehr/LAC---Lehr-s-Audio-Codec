function X = bwe_reconstruct(X,parameters,frame)
%BWE_RECONSTRUCT Mirror decoded 0-12 kHz, mix deterministic noise, shape RMS.
N=numel(X); group=N/8; mirror=X(N/2:-1:1);
for g=1:4
    local=(g-1)*group+(1:group); target=N/2+local;
    if parameters(g,1)==0, X(target)=0; continue; end
    v=mirror(local); energy=sum(v.^2);
    if energy>0, v=v/sqrt(energy); end
    % Park-Miller generator: exact integer products below flintmax; no RNG state.
    seed=mod(frame*65537+g*257,2147483646)+1; noise=zeros(group,1);
    for k=1:group
        seed=mod(48271*seed,2147483647); noise(k)=2*seed/2147483647-1;
    end
    noise=noise/norm(noise); mix=parameters(g,2)/3;
    if energy==0, mix=1; end
    shape=sqrt(1-mix)*v+sqrt(mix)*noise;
    if norm(shape)<1e-12, shape=noise; end
    X(target)=shape/norm(shape)*sqrt(group)*10^((parameters(g,1)-160)/20);
end
end
