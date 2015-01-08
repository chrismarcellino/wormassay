[Download latest release of WormAssay](https://github.com/chrismarcellino/wormassay/releases/latest)

## WormAssay
WormAssay is a Mac application for the automated screening of the motility of macroscopic parasites and other organisms in 6 through 96 well microtiter plates. A variety of HD and better camera hardware is supported (QuickTime X compatible or Blackmagic capture devices) and a Mac running Mac OS X 10.9 Mavericks is required. 

To use, download the latest WormAssay binary (or build from source, below) and run the application. Simply run the application and attach a camera (see below). Use the Options menu to choose an algorithm and to choose the proper orientation of the plate so that it appears with A1 in the upper left on screen.

We have had excellent results screening *B. malayi* with the Canon Vivia HV30 and HV40 camcorders attached via IEEE1394 (FireWire) or with Canon HD camcorders attached through Blackmagic capture hardware via HDMI, and white LED lights illuminating the sides of the plate in a dark box, recording the plate from below (i.e. dark-field for maximum contrast). See the manuscript below for more information on recording conditions. 

Any HD or better camera supported by QuickTime X for recording should work equally well (launch QuickTime and try) but if your camera doesn't have a FireWire port, you will generally either need a capture device that supports QuickTime X (rare) or a [Blackmagic](http://www.blackmagicdesign.com) Thunderbolt or PCIe capture device, such as the [UltraStudio Mini Recorder](http://www.blackmagicdesign.com/products/ultrastudiothunderbolt/techspecs/#31781) (~$145 USD), [Intensity Shuttle Thunderbolt](http://www.blackmagicdesign.com/products/intensity/techspecs?pid1=26718&pid2=24831#techspecs-top) (~$227 USD) or [Intensity Extreme](http://www.blackmagicdesign.com/products/intensity/techspecs?pid1=26718&pid2=24831#techspecs-top) (~$284 USD) to allow live capture with any camera with over HDMI or analog outputs depending on the device. (If using Blackmagic hardware, it is recommended that you download and install the latest Desktop Video drivers from their [support website](http://www.blackmagicdesign.com/support)) CSV output files and H.264/MPEG4 videos will be saved in your Documents folder (use the Options menu to customize.) 

See the manuscript linked below for a detailed description of which algorithm to choose. In short, if you have a single parasite in each well, try using the Optical Flow algorithm. Otherwise, you should probably use the Luminance Difference algorithm. For best results, set your camera to 1080p and ≤30 fps, with image stabilization OFF and Instant Autofocus OFF (normal AF/TTL is optional and ok to use.)

WormAssay's source code is distributed under the GPLv2 (or later, your choice). ZXing and OpenCV are also bundled under their respective Apache and GPL licenses. Building the source code (which is not required) requires the Xcode Developer Tools, which can be downloaded from the Mac App Store. To build, open the WormAssay.xcodeproj file, and choose 'Run.'

**An open-access manuscript describing the publication is available in PLoS NTDs at [doi:10.1371/journal.pntd.0001494](http://www.plosntds.org/article/info%3Adoi%2F10.1371%2Fjournal.pntd.0001494). See a [video demonstrating WormAssay in use](http://vimeo.com/34962651) at the Sandler Center for Drug Discovery.**

The [change log](https://github.com/chrismarcellino/wormassay/blob/master/CHANGES.txt) can be viewed in the source section.

This work was supported by grants from the Bill & Melinda Gates Foundation and the Sandler Center for Drug Discovery. 

Chris Marcellino
UCSF Center for Discovery and Innovation in Parasitic Diseases, UCSF QB3
Case Western Reserve University School of Medicine

Judy Sakanari, PhD
UCSF Center for Discovery and Innovation in Parasitic Diseases, UCSF QB3


## Links:
[Manuscript at PLoS NTDs] (http://www.plosntds.org/article/info%3Adoi%2F10.1371%2Fjournal.pntd.0001494)

[California Institute for Quantitative Biosciences] (http://qb3.org/)

[Center for Innovation and Discovery in Parasitic Diseases](http://www.cdipd.org)

[Bill & Melinda Gates Foundation](http://www.gatesfoundation.org/)

[Demonstration Video](http://vimeo.com/34962651)

[OpenCV](http://opencv.org)

[Blackmagic Design](http://www.blackmagicdesign.com)

[ZXing](https://code.google.com/p/zxing/)
