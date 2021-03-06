[Download the latest release of WormAssay](https://github.com/chrismarcellino/wormassay/releases/latest) | [Read the manuscript](http://www.plosntds.org/article/info%3Adoi%2F10.1371%2Fjournal.pntd.0001494) | [Watch the tutorial video](http://vimeo.com/34962651)

## WormAssay
WormAssay is a Mac application for the automated screening of the motility of macroscopic parasites and other organisms in 6 through 96 well microtiter plates. A variety of HD and better camera hardware is supported (QuickTime X compatible or Blackmagic capture devices) and a Mac running macOS 10.14 Mojave or later is required. Both Intel (x86-64) and Apple Silicon (arm64) Macs are supported.

To use, download the latest WormAssay binary above (or build from source) and simply run the application and attach a camera (see below). Use the Options menu to choose a screening algorithm and to set the proper orientation of the plate so that it appears with A1 in the upper left on screen so that results are not transposed.

We have had excellent results screening *B. malayi* with the Canon Vivia HV30 and HV40 camcorders attached via IEEE1394 (FireWire) or with Canon HD camcorders attached through Blackmagic capture hardware via HDMI, and white LED lights illuminating the sides of the plate in a dark box, recording the plate from below (i.e. dark-field for maximum contrast). See the manuscript for more information on recording conditions and examples of plate videos to compare to and test and our tutorial video above. 

However, any HD or better camcorder supported by QuickTime for recording should work equally well (launch QuickTime on an updated macOS and try to view the camera using File...New Movie Recording...). If your camera and Mac doesn't have a FireWire port or adapter, you will generally either need a HDMI-to-USB adapter and cable that supports QuickTime (there are many; inexpensive) or a [Blackmagic](http://www.blackmagicdesign.com) Thunderbolt or PCIe capture device, such as the UltraStudio Mini Recorder (under $100 used), Intensity Shuttle Thunderbolt, or Intensity Extreme. HD (1080p) capture hardware versions (as opposed to 4k) are sufficient. (If using Blackmagic hardware, it is recommended that you download and install the latest Desktop Video drivers from their [support website](http://www.blackmagicdesign.com/support). For native operation on Apple Silicon, Desktop Video 12.0 or higher is required, otherwise a minimum version of 11.4 is required.) Webcam-type hardware is not recommended due to lower quality optics and poor results (except for the purposes of reading barcodes only.)

For best results, set your camcorder to 1080p and ≤30 fps, with image stabilization OFF and Instant Autofocus OFF (normal AF/TTL is optional and ok to use.) 4k is not recommended to ensure optimal frame rate and accuracy. 

CSV output files and H.264/MPEG4 videos will be saved in your Documents folder (use the Options menu to customize or disable video saving.) If you apply a barcode to the plate and either ensure it is in the view of the main camera, or connect a second camera to i.e. image the side of plate, WormAssay will name the output files and videos using the barcode label text. QR codes are recommended though a wide variety of 1-D and 2-D barcodes can be read. If using a 2nd camera, any inexpensive USB webcam will do for barcode reading. No configuration is required as the barcodes are detected automatically. 

See the manuscript linked below for a detailed description of which algorithm to choose. In short, if you have a single parasite in each well, try using the Optical Flow algorithm. Otherwise, you should probably use the Luminance Difference algorithm. 

WormAssay's source code is distributed under the GPLv2 (or later, your choice). OpenCV 2 modules are included under its 3-clause BSD license. Building the source code (which is not required) requires the Xcode Developer Tools, which can be downloaded from the Mac App Store. To build, open the WormAssay.xcodeproj file, and choose 'Run.' Note that there is a significant performance difference (two-fold) between debug and release versions due to compiler optimization. 

**An open-access manuscript describing the publication is available in PLoS NTDs at [doi:10.1371/journal.pntd.0001494](http://www.plosntds.org/article/info%3Adoi%2F10.1371%2Fjournal.pntd.0001494). See a [video demonstrating WormAssay in use](http://vimeo.com/34962651) at the Sandler Center for Drug Discovery.**

The [change log](https://github.com/chrismarcellino/wormassay/blob/master/CHANGES.txt) can be viewed in the source section.

This work was supported by grants from the Bill & Melinda Gates Foundation and the Sandler Center for Drug Discovery. 

Chris Marcellino, MD<br>
UCSF Center for Discovery and Innovation in Parasitic Diseases, UCSF QB3<br>
Case Western Reserve University School of Medicine<br>
Mayo Clinic, Department of Neurological Surgery<br>

Judy Sakanari, PhD<br>
UCSF Center for Discovery and Innovation in Parasitic Diseases, UCSF QB3


## Links:
[Manuscript at PLoS NTDs](http://www.plosntds.org/article/info%3Adoi%2F10.1371%2Fjournal.pntd.0001494)

[California Institute for Quantitative Biosciences](http://qb3.org/)

[Center for Innovation and Discovery in Parasitic Diseases](http://www.cdipd.org)

[Bill & Melinda Gates Foundation](http://www.gatesfoundation.org/)

[Demonstration Video](http://vimeo.com/34962651)

[OpenCV](http://opencv.org)

[Blackmagic Design](http://www.blackmagicdesign.com)
