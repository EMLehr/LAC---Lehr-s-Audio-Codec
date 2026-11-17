function results = stage2_verify_transform()
%STAGE2_VERIFY_TRANSFORM Exercise boundaries and lengths independently.
rng(1729,'twister');
lengths = [1 2 17 1023 1024 1025 2047 2048 2049 7919 480000];
results = struct([]);
t = 0;
for L = lengths
    signals = cell(1,5);
    signals{1}=zeros(L,1); signals{2}=0.1*randn(L,1);
    signals{3}=0.7*sin(2*pi*997*(0:L-1)'/48000);
    a = zeros(L,1); a(1)=1; signals{4}=a;
    a = zeros(L,1); a(end)=1; signals{5}=a;
    for s = 1:numel(signals)
        x = signals{s}; X = pac.analyze(x); y = pac.synthesize(X,L);
        e = max(abs(x-y));
        energyError = abs(sum(X(:).^2)-sum(x.^2))/max(1,sum(x.^2));
        assert(numel(y)==L && e < 2e-11 && energyError < 2e-11, ...
            'pac:Transform','Transform failed for length %d, signal %d.',L,s);
        t=t+1;
        row=struct('length',L,'signal',s,'maxError',e,'relativeEnergyError',energyError);
        if t == 1, results=row; else, results(t)=row; end
    end
end
out = fullfile(pac.project_root(),'outputs','validation');
if ~isfolder(out), mkdir(out); end
pac.write_json(fullfile(out,'transform.json'),results);
fprintf('PASS: %d transform cases; worst absolute error %.3g\n',t,max([results.maxError]));
end
