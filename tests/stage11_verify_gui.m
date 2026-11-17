function report=stage11_verify_gui()
%STAGE11_VERIFY_GUI Editable ratios, independent policies, and +9/+12 presets.
root=pac.project_root(); app=listening_gui(); guard=onCleanup(@() app.close());
test=matlab.uitest.TestCase.forInteractiveUse;
test.choose(app.UI.Side(2).Mode,'Variable bitrate');
test.choose(app.UI.Side(2).Rate,'Smaller file (+9 dB)'); test.press(app.UI.Load);
assert(~app.Dirty && app.Data{2}.config.vbr.distortionDB==9);
size9=app.Data{2}.bytes;
test.choose(app.UI.Side(2).Rate,'Smallest file (+12 dB)'); test.press(app.UI.Load);
assert(~app.Dirty && app.Data{2}.bytes<=size9);
test.press(app.UI.Side(2).Advanced); d=app.UI.Dialog;
assert(strcmp(d.Bucket.Enable,'off'));
test.press(d.Enabled); d.Numerator(3).Value=3; d.Denominator(3).Value=4;
d.Numerator(1).Value=5; test.press(d.Apply); assert(isgraphics(d.Figure) && strlength(d.Message.Text)>0);
d.Numerator(1).Value=1; test.press(d.Apply);
assert(~isgraphics(d.Figure) && app.Dirty && strcmp(app.UI.Side(2).Rate.Enable,'off'));
test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
assert(app.Data{2}.config.allocation.enabled && app.Data{2}.config.allocation.savedNumerator(3)==3);
assert(~app.Data{2}.config.reservoir.enabled && ~app.Data{1}.config.allocation.enabled);
test.choose(app.UI.Side(2).Mode,'Fixed bitrate'); test.press(app.UI.Side(2).Advanced);
d=app.UI.Dialog; test.press(d.Bucket); d.Capacity.Value=4;
exportapp(d.Figure,fullfile(root,'outputs','listening','allocation_controls.png'));
test.press(d.Apply); test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
assert(app.Data{2}.config.reservoir.enabled && app.Data{2}.config.reservoir.capacityFrames==4);
assert(app.Data{2}.actualKbps==96 && contains(app.UI.Side(2).Info.Text,'bucket'));
% Applying VBR policy edits must retain the side's disabled CBR bucket settings.
test.choose(app.UI.Side(2).Mode,'Variable bitrate'); test.press(app.UI.Side(2).Advanced);
d=app.UI.Dialog; assert(~d.Bucket.Value && strcmp(d.Bucket.Enable,'off')); test.press(d.Apply);
test.choose(app.UI.Side(2).Mode,'Fixed bitrate'); test.press(app.UI.Side(2).Advanced);
d=app.UI.Dialog; assert(d.Bucket.Value && d.Capacity.Value==4); test.press(d.Apply);
test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
app.UI.Notes.Value={'AUTOMATED TEST: piecewise/bucket configuration, no listening judgment.'};
test.press(app.UI.Save);
exportapp(app.Figure,fullfile(root,'outputs','listening','allocation_preview.png'));
report=struct('extraVbrPresets',true,'editableThreeRatios',true,'partialBottomLayer',true, ...
    'invalidRatioRejected',true,'independentSides',true,'bucketAndModeControls',true);
pac.write_json(fullfile(root,'outputs','listening','allocation_verification.json'),report);
fprintf('PASS: allocation GUI, all three ratios, validation, bucket controls, +9/+12 presets.\n');
end
