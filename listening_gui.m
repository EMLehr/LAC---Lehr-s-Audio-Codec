function app = listening_gui()
%LISTENING_GUI Compare originals and all independently selectable codec modes.
% Run from the project folder. Missing versions are generated on demand.
app=pac.ListeningApp(fileparts(mfilename('fullpath')));
app.loadComparison();
end
