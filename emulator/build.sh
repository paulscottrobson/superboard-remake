#
#		Build emulator.
#
rm *.inc
pushd ../processor
sh build.sh
popd
pushd ../roms
sh build.sh
popd
rm sb2 *.rom
make -f makefile.linux


