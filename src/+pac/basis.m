function [A,w] = basis()
%BASIS Explicit normalized MDCT basis, cached. No Audio Toolbox required.
persistent matrix window
if isempty(matrix)
    N = 1024;
    n = (0:2*N-1)';
    k = 0:N-1;
    matrix = sqrt(2/N)*cos((pi/N)*(n+0.5+N/2)*(k+0.5));
    window = sin(pi*(n+0.5)/(2*N));
end
A = matrix;
w = window;
end
