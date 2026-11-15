function [A,w]=switch_basis(mode)
%SWITCH_BASIS 0 long, 1 start, 2 eight-short, 3 stop; sine TDAC windows.
[A,w]=pac.basis();
if mode==0, return; end
persistent shortA shortW
if isempty(shortA)
    N=128; n=(0:255)'; k=0:127;
    shortA=sqrt(2/N)*cos((pi/N)*(n+.5+N/2)*(k+.5));
    shortW=sin(pi*(n+.5)/(2*N));
end
if mode==1
    w=[w(1:1024);ones(448,1);shortW(129:256);zeros(448,1)];
elseif mode==2
    A=shortA; w=shortW;
elseif mode==3
    w=[zeros(448,1);shortW(1:128);ones(448,1);w(1025:2048)];
else
    error('pac:Format','Invalid window sequence.');
end
end
