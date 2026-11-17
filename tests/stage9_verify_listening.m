function report=stage9_verify_listening(testAudio)
%STAGE9_VERIFY_LISTENING UI, cache, alignment, and optional muted audio checks.
if nargin<1, testAudio=false; end
root=pac.project_root(); app=listening_gui();
guard=onCleanup(@() app.close());
test=matlab.uitest.TestCase.forInteractiveUse;
assert(~app.Dirty && app.Data{1}.original && ~app.Data{2}.original);
assert(isequal(app.Data{1}.x,pac.read_input(fullfile(root,'outputs','prepared','harpsichord.mat'))));
assert(isequal(app.Data{2}.x,decode_audio(app.Data{2}.path)));
old=fullfile(root,'outputs','pam_options','harpsichord_baseline_96k.lac');
assert(isequal(pac.file_bytes(old),pac.file_bytes(app.Data{2}.path)));
path=app.Data{2}.path; test.press(app.UI.Load);
assert(app.Data{2}.cacheHit && strcmp(path,app.Data{2}.path));
% Actual UI gestures change source type, independent bitrates, and six switches.
test.choose(app.UI.Side(1).Kind,'Encoded');
test.choose(app.UI.Side(1).Rate,'64 kb/s');
test.choose(app.UI.Side(2).Rate,'128 kb/s');
for k=1:6, test.press(app.UI.Side(2).Checks(k)); end
test.choose(app.UI.Side(2).Temporal,'Pre-echo only');
assert(app.Dirty && strcmp(app.UI.Play.Enable,'off'));
test.press(app.UI.Load); assert(~app.Dirty,app.UI.Status.Text);
assert(app.Data{1}.actualKbps==64 && app.Data{2}.actualKbps==128);
assert(all(structfun(@(x) x,app.Data{2}.config.features)));
assert(~app.Data{2}.config.pam.temporal.postMasking && app.Data{2}.config.pam.temporal.preEchoControl);
assert(strcmp(app.Data{2}.model,'tonal_temporal_preecho_only_spreading_mapping_huffman_bwe'));
assert(isequal(app.Data{2}.x,decode_audio(app.Data{2}.path)));
assert(numel(app.Data{1}.x)==numel(app.Data{2}.x));
assert(max(abs([app.Data{1}.x;app.Data{2}.x]))*app.Gain<=.98);
app.seek(1.234); test.press(app.UI.B); assert(app.Active==2 && abs(app.Cursor-1.234)<1e-9);
test.press(app.UI.A); assert(app.Active==1 && abs(app.Cursor-1.234)<1e-9);
% Region validation and transport bookkeeping without requiring audio hardware.
app.UI.Start.Value=2; app.UI.Finish.Value=1;
app.UI.Start.ValueChangedFcn(app.UI.Start,[]);
assert(app.UI.Start.Value==0 && app.UI.Finish.Value==10);
app.UI.Start.Value=.2; app.UI.Finish.Value=.8;
app.UI.Start.ValueChangedFcn(app.UI.Start,[]); assert(app.Cursor==.2);
app.seek(.5); test.press(app.UI.Stop); assert(app.Cursor==.2);
app.UI.Notes.Value={'AUTOMATED UI TEST: not a human listening observation.'};
test.press(app.UI.Save);
notes=dir(fullfile(root,'outputs','listening','notes','*.json')); [~,latest]=max([notes.datenum]);
record=jsondecode(fileread(fullfile(notes(latest).folder,notes(latest).name)));
assert(record.startSeconds==.2 && record.endSeconds==.8 && ~record.heldOut);
assert(record.A.actualKbps==64 && record.B.actualKbps==128);
audioPassed=false;
if testAudio
    app.UI.Volume.Value=0; app.UI.Volume.ValueChangedFcn(app.UI.Volume,[]);
    % UI gesture settling can exceed a short clip; use callbacks directly
    % for timing-sensitive transport checks after the gesture checks above.
    app.UI.Finish.Value=8;
    app.playPause(); pause(.15); drawnow;
    assert(app.IsPlaying,app.UI.Status.Text); before=app.Cursor;
    app.select(2); assert(app.IsPlaying && app.Active==2 && app.Cursor>=before);
    app.playPause(); assert(~app.IsPlaying);
    app.stop(); assert(app.Cursor==.2);
    app.UI.Finish.Value=.8;
    app.UI.Loop.Value=true; app.playPause(); pause(1.1); drawnow;
    assert(app.IsPlaying && app.Cursor>=.2 && app.Cursor<=.8);
    app.stop(); app.UI.Loop.Value=false;
    app.UI.Finish.Value=.3; app.playPause(); pause(.5); drawnow;
    assert(~app.IsPlaying && app.Cursor==.3); audioPassed=true;
end
% Source changes invalidate playback without automatically consuming speech.
test.choose(app.UI.Source,'Speech (final test)'); assert(app.Dirty);
assert(strcmp(app.Data{1}.source,'harpsichord')); % Not loaded by selection alone.
test.choose(app.UI.Source,'Castanets');
test.choose(app.UI.Side(1).Kind,'Original');
test.choose(app.UI.Side(2).Kind,'Original'); test.press(app.UI.Load);
assert(~app.Dirty && strcmp(app.Data{1}.source,'castanets') && isequal(app.Data{1}.x,app.Data{2}.x));
test.choose(app.UI.Source,'Harpsichord'); test.choose(app.UI.Side(2).Kind,'Encoded');
for k=1:6, test.press(app.UI.Side(2).Checks(k)); end
test.choose(app.UI.Side(2).Rate,'96 kb/s'); test.press(app.UI.Load);
app.UI.Notes.Value={''};
if testAudio, app.UI.Volume.Value=75; app.UI.Volume.ValueChangedFcn(app.UI.Volume,[]); end
exportapp(app.Figure,fullfile(root,'outputs','listening','gui_preview.png'));
report=struct('uiGestures',true,'contentCache',true,'baselineIdenticalBytes',true, ...
    'independentRatesAndFeatures',true,'alignmentAndSharedGain',true, ...
    'regionAndNotes',true,'speechNotLoaded',true,'mutedAudioPassed',audioPassed);
pac.write_json(fullfile(root,'outputs','listening','verification.json'),report);
fprintf('PASS: listening GUI controls, cache, alignment, notes; muted audio = %d.\n',audioPassed);
end
