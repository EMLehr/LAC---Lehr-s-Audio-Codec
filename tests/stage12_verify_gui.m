function stage12_verify_gui()
%STAGE12_VERIFY_GUI New independent switches, numeric settings, and audition.
root=pac.project_root(); app=listening_gui(); guard=onCleanup(@() app.close());
test=matlab.uitest.TestCase.forInteractiveUse;
test.press(app.UI.Side(2).ExperimentButton); d=app.UI.ExperimentDialog;
assert(all(~[d.Checks.Value]));
for k=1:5, test.press(d.Checks(k)); end
test.choose(d.Scope,'Per file + per-window books'); d.Numeric(1).Value=2;
exportapp(d.Figure,fullfile(root,'outputs','listening','experiments_controls.png'));
test.press(d.Apply); assert(app.Dirty && ~app.UI.Side(1).Experiments.variableWindows);
test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
assert(app.Data{2}.config.experiments.variableWindows && app.Data{2}.actualKbps==96);
test.choose(app.UI.Side(2).Mode,'Variable bitrate'); test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
path=app.Data{2}.path; test.press(app.UI.Load); assert(app.Data{2}.cacheHit && strcmp(path,app.Data{2}.path));
% PE must remain usable independently with required fixed windows.
test.press(app.UI.Side(2).ExperimentButton); d=app.UI.ExperimentDialog;
for k=[1 2 3 5], test.press(d.Checks(k)); end
test.press(d.Apply); test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
st=jsondecode(fileread([app.Data{2}.path '.json'])); assert(st.shortFrames==0 && st.config.experiments.perceptualEntropy);
% Disabling every new option restores the legacy path and baseline samples.
test.press(app.UI.Side(2).ExperimentButton); d=app.UI.ExperimentDialog; test.press(d.Checks(4)); test.press(d.Apply);
test.choose(app.UI.Side(2).Mode,'Fixed bitrate'); test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
reference=fullfile(root,'outputs','baseline','harpsichord_baseline_96k.lac');
assert(isequal(pac.file_bytes(reference),pac.file_bytes(app.Data{2}.path)));
app.UI.Notes.Value={'AUTOMATED TEST: experiment toggles only; no listening observations.'}; test.press(app.UI.Save);
exportapp(app.Figure,fullfile(root,'outputs','listening','experiments_preview.png'));
pac.write_json(fullfile(root,'outputs','listening','experiments_verification.json'), ...
    struct('fiveIndependentToggles',true,'bookScope',true,'settings',true,'peFixedWindow',true,'baselineRestored',true));
fprintf('PASS: five experiment controls, both modes, PE independent, and baseline restoration.\n');
end
