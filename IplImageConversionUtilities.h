//
//  IplImageConversionUtilities.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <CoreVideo/CoreVideo.h>
#import <ApplicationServices/ApplicationServices.h>
#import "opencv2/core/core_c.h"

#ifdef __cplusplus
extern "C" {
#endif

// CVPixelBuffer conversions that are 32-bit 4bpp packed are optimal straight memcpy()s.
extern IplImage *CreateIplImageFromCVPixelBuffer(CVPixelBufferRef cvImageBuffer, int outChannels);
extern IplImage *CreateIplImageFromCGImage(CGImageRef cgImage, int outChannels);

#ifdef __cplusplus
}
#endif
