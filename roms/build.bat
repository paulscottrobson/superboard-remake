@echo off
rem
rem		Compile CEGMON\600 and copy ROM images to emulator space.
rem
64tass -c -b -o cegmon.rom -L cegmon.lst cegmon.asm
fc /b cegmon.rom cegmon.rom.original 

copy cegmon.rom ..\emulator\monitor.rom
copy basic.rom ..\emulator\basic.rom

rem
rem		Export font as .h file.
rem
python export.py
