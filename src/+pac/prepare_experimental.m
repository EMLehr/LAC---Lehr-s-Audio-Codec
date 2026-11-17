function [X,frames,modes,diagnostic,longBands,shortBands]=prepare_experimental(x,cfg)
e=pac.experiment_settings(cfg); bwe=cfg.features.bandwidthExtension;
longBands=pac.coding_bands(bwe); shortBands=pac.coding_bands(bwe,128);
longX=pac.analyze(x); [longAllowance,~,longDetails]=pac.pam(longX,cfg,longBands);
[modes,diagnostic]=pac.transient_plan(x,longX,longAllowance,longBands,e);
X=longX;
if any(modes), X=pac.analyze_switch(x,modes); end
F=size(X,2); frames=cell(1,F); state=[]; previousN=0;
for f=1:F
    g=pac.frame_geometry(modes(f),bwe,longBands,shortBands);
    if ~any(modes)
        a=longAllowance(:,f); E=longDetails.bandEnergy(:,f);
    else
        local=cfg; local.hop=g.N; local.windowLength=2*g.N;
        if g.N~=previousN, state=[]; end
        bands=longBands; if g.N==128, bands=shortBands; end
        [a,~,detail,state]=pac.pam(reshape(X(:,f),g.N,[]),local,bands,state);
        a=a(:); E=detail.bandEnergy(:); previousN=g.N;
    end
    pe=.5*g.count.*max(0,log2(max(E,realmin)./max(a,realmin)));
    protection=zeros(size(a));
    if e.perceptualEntropy
        density=pe./g.count;
        protection=e.peStrengthDB*min(1,density/max(1,mean(density)))+ ...
            e.attackProtectionDB*diagnostic.attack(f);
        a=a.*10.^(-protection/10);
    end
    params=zeros(4,2,g.units);
    if bwe
        for u=1:g.units, params(:,:,u)=pac.bwe_parameters(X((u-1)*g.N+(1:g.N),f)); end
    end
    frames{f}=struct('geometry',g,'allowance',a,'pe',pe,'protectionDB',protection,'parameters',params);
end
diagnostic.modes=modes;
end
