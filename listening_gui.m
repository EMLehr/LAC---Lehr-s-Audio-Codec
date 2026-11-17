function app = listening_gui()
%LISTENING_GUI Compare originals and all independently selectable codec modes.
% Run from the project folder. Missing versions are generated on demand.
root=lac_setup();
app=pac.ListeningApp(root);
app.loadComparison();
end
