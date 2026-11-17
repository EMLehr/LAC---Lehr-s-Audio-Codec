function report=stage10_verify_vbr_gui()
%STAGE10_VERIFY_VBR_GUI Independent rate modes, quality presets, and percentages.
root=pac.project_root(); app=listening_gui(); guard=onCleanup(@() app.close());
test=matlab.uitest.TestCase.forInteractiveUse;
test.choose(app.UI.Side(1).Kind,'Encoded'); test.choose(app.UI.Side(1).Rate,'64 kb/s');
test.choose(app.UI.Side(2).Mode,'Variable bitrate');
assert(app.UI.Side(2).Rate.Value==0 && app.Dirty);
test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
assert(strcmp(app.Data{1}.rateMode,'cbr') && app.Data{1}.actualKbps==64);
assert(strcmp(app.Data{2}.rateMode,'vbr') && app.Data{2}.config.vbr.distortionDB==0);
standardBytes=app.Data{2}.bytes; standardPath=app.Data{2}.path;
assert(contains(app.UI.Side(1).Info.Text,'91.67% smaller'));
assert(abs(app.Data{2}.sizeReductionPercent-100*(1-standardBytes/960000))<1e-10);
test.choose(app.UI.Side(2).Rate,'Higher quality (-6 dB)'); test.press(app.UI.Load);
assert(~app.Dirty && app.Data{2}.bytes>=standardBytes);
test.choose(app.UI.Side(2).Rate,'Smaller file (+6 dB)'); test.press(app.UI.Load);
assert(~app.Dirty && app.Data{2}.bytes<=standardBytes);
test.choose(app.UI.Side(2).Rate,'Standard (0 dB)'); test.press(app.UI.Load);
assert(app.Data{2}.cacheHit && strcmp(app.Data{2}.path,standardPath));
test.choose(app.UI.Side(1).Mode,'Variable bitrate'); test.press(app.UI.Load);
assert(strcmp(app.Data{1}.rateMode,'vbr') && isequal(app.Data{1}.x,app.Data{2}.x));
test.choose(app.UI.Side(1).Mode,'Fixed bitrate');
assert(app.UI.Side(1).Rate.Value==96 && app.Dirty);
test.choose(app.UI.Side(1).Kind,'Original'); test.press(app.UI.Load);
assert(~app.Dirty && app.Data{1}.original && strcmp(app.Data{2}.rateMode,'vbr'));
exportapp(app.Figure,fullfile(root,'outputs','listening','vbr_preview.png'));
report=struct('independentModes',true,'qualityPresetSizes',true,'percentageDisplay',true,'cacheIdentity',true);
pac.write_json(fullfile(root,'outputs','listening','vbr_verification.json'),report);
fprintf('PASS: VBR GUI modes, presets, percentages, and cache.\n');
end
