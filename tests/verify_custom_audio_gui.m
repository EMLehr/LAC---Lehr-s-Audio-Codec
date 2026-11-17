function verify_custom_audio_gui()
%VERIFY_CUSTOM_AUDIO_GUI Import, preparation, cache identity, and source switching.
root=pac.project_root(); folder=fullfile(root,'outputs','listening','custom_test');
if ~isfolder(folder), mkdir(folder); end
t=(0:22049)'/44100; stereo=[.2*sin(2*pi*440*t) .1*cos(2*pi*880*t)];
path=fullfile(folder,'custom stereo.wav'); audiowrite(path,stereo,44100);
before=pac.file_bytes(path);
app=pac.ListeningApp(root); guard=onCleanup(@() app.close());
app.importFile(path);
assert(strcmp(app.UI.Source.Value,'custom') && app.Dirty,app.UI.Status.Text);
assert(contains(app.UI.Source.Items{4},'custom stereo.wav'));
app.loadComparison(); assert(~app.Dirty,app.UI.Status.Text);
[raw,~]=audioread(path); expected=resample(mean(raw,2),160,147);
assert(isequal(app.Data{1}.x,expected) && numel(expected)==24000);
assert(app.Data{1}.fs==48000 && app.Data{2}.actualKbps==96);
assert(app.Data{1}.sourceMetadata.originalChannels==2);
assert(isequal(before,pac.file_bytes(path)));
[decoded,~]=decode_audio(app.Data{2}.path); assert(isequal(decoded,app.Data{2}.x));
firstPath=app.Data{2}.path;
app.loadComparison(); assert(app.Data{2}.cacheHit && strcmp(firstPath,app.Data{2}.path));
% Invalid files leave the loaded comparison and source selection intact.
app.importFile(fullfile(folder,'missing.wav'));
assert(~app.Dirty && strcmp(app.UI.Source.Value,'custom') && contains(app.UI.Status.Text,'Could not import'));
% A different file must not reuse the previous audio's cache.
path2=fullfile(folder,'custom mono.wav');
audiowrite(path2,.1*sin(2*pi*1234*(0:24016)'/48000),48000);
app.importFile(path2); app.loadComparison(); assert(~app.Dirty,app.UI.Status.Text);
assert(numel(app.Data{1}.x)==24017 && ~strcmp(firstPath,app.Data{2}.path));
assert(isequal(app.Data{1}.x,audioread(path2)));
app.UI.Notes.Value={'AUTOMATED TEST: custom input; no listening observations.'};
app.saveNotes(); notes=jsondecode(fileread(extractAfter(app.UI.Status.Text,'Saved listening notes: ')));
assert(strcmp(notes.A.sourceMetadata.filename,'custom mono.wav') && ~notes.heldOut);
test=matlab.uitest.TestCase.forInteractiveUse;
test.choose(app.UI.Side(2).Mode,'Variable bitrate'); test.press(app.UI.Load);
assert(~app.Dirty && strcmp(app.Data{2}.rateMode,'vbr'),app.UI.Status.Text);
test.choose(app.UI.Source,'Harpsichord'); test.press(app.UI.Load);
assert(~app.Dirty && strcmp(app.Data{1}.source,'harpsichord'),app.UI.Status.Text);
test.choose(app.UI.Source,'Custom: custom mono.wav'); test.press(app.UI.Load);
assert(~app.Dirty && numel(app.Data{1}.x)==24017,app.UI.Status.Text);
exportapp(app.Figure,fullfile(folder,'custom_gui.png'));
fprintf('PASS: custom import, exact preparation, source preservation, standalone decode, cache, notes, CBR/VBR, source switching.\n');
end
