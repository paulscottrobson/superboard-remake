@echo off
del /Q monitor.rom
64tass -c -b -o monitor.rom -L newmonitor.lst newmonitor.asm
if errorlevel 1 goto exit
..\emulator\sb2.exe go go
:exit
