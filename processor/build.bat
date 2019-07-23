@echo off
rem
rem					Generate the C code and copy it to the emulator build space.
rem
python process.py
copy *.h ..\emulator\6502

