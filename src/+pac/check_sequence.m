function check_sequence(modes)
%CHECK_SEQUENCE Legal start/stop transitions are part of version-5 syntax.
assert(~isempty(modes) && all(ismember(modes,0:3)) && ...
    ismember(modes(1),[0 1]) && ismember(modes(end),[0 3]),'pac:Format','Invalid boundary window sequence.');
allowed=[1 1 0 0;0 0 1 0;0 0 1 1;1 1 0 0];
for f=2:numel(modes)
    assert(allowed(modes(f-1)+1,modes(f)+1),'pac:Format','Invalid window transition.');
end
end
