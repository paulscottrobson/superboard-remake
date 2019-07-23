@echo off 
copy ..\emulator\*.inc include
copy ..\emulator\sys_processor.cpp 
copy ..\emulator\hardware.cpp
copy ..\emulator\*.h include
copy ..\emulator\6502\* include
pio run -t upload

rem
rem	pio lib install 6143 	(fabgl)
rem