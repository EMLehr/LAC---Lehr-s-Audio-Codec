function root=lac_setup()
%LAC_SETUP Add codec, stages, and tests to this MATLAB session's path.
% Run once from the project root before using the command-line functions.
% listening_gui calls this automatically. No saved/global path is modified.
root=fileparts(mfilename('fullpath'));
addpath(root,fullfile(root,'src'),fullfile(root,'stages'),fullfile(root,'tests'));
end
