function root=project_root()
%PROJECT_ROOT Locate data and outputs independently of the current folder.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
end
