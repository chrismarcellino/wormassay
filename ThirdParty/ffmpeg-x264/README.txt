ffmpeg and x264 are distributed here under the GPLv2 license. As this is a standalone binary (not linked), this licensing does not affect WormAssay (which happens to also be distributed under the GPLv2 license.) The source for ffmpeg and x264 are included here per the GPL. 


ffmpeg & x264 were building instructions:
=========================================

1) Download yasm and extract, then cd into its directory and run:
./configure
make
sudo make install

2) Extract x264 (or a newer version, substituting its path below in the configure command) into a folder at the root of your drive (for brevity):

cd /x264-snapshot-20110509-2245
./configure
make

3) Extract ffmpeg into any folder and run:
./configure --enable-gpl --enable-libx264 --extra-cflags=-I/x264-snapshot-20110509-2245 --extra-ldflags=-L/x264-snapshot-20110509-2245
make

And then use the resulting ffmpeg binary as input to this folder and the Xcode project will copy it during the build into the app bundle.