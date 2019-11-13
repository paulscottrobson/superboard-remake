cp ../emulator/*.inc include
cp ../emulator/sys_processor.cpp .
cp ../emulator/hardware.cpp .
cp ../emulator/*.h include
cp ../emulator/6502/* include
pio run -t upload

#
#	pio lib install 6143 	(fabgl)
#