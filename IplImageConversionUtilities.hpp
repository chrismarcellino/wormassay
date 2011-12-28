//
//  IplImageConversionUtilities.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <CoreVideo/CoreVideo.h>
#import "opencv2/opencv.hpp"

extern IplImage *CreateIplImageFromCVPixelBuffer(CVPixelBufferRef cvImageBuffer);

extern CGImageRef CreateCGImageFromIplImage(IplImage *iplImage);
extern CGImageRef CreateCGImageFromIplImagePassingOwnership(IplImage *iplImage, bool passOwnership);
