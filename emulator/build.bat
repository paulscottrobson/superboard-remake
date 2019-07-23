@echo off
rem
rem		Build emulator.
rem
del /Q *.inc
pushd ..\processor
call build.bat
popd
pushd ..\roms
call build.bat
popd
del /Q sb2 *.rom
mingw32-make


