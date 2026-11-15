function g=frame_geometry(mode,bwe,longBands,shortBands)
if mode==2, N=128; units=8; bands=shortBands; else, N=1024; units=1; bands=longBands; end
edges=[];
for u=1:units, edges=[edges;bands.edges(1:end-1)+(u-1)*N]; end %#ok<AGROW>
g=struct('edges',[edges;1025],'count',diff([edges;1025]),'N',N,'units',units);
g.active=true(numel(edges),1);
if bwe, g.active=mod(edges-1,N)<N/2; end
g.mandatory=8+4*numel(edges)+40*units*double(bwe);
end
