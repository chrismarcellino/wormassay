//
//  IplImageConversionUtilities.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <CoreVideo/CoreVideo.h>
#import <ApplicationServices/ApplicationServices.h>
#ifdef __cplusplus
#import "opencv2/opencv.hpp"
#else
typedef void *IplImage;
#endif

#ifdef __cplusplus
extern "C" {
#endif

extern IplImage *CreateIplImageFromCVPixelBuffer(CVPixelBufferRef cvImageBuffer, int outChannels);

extern CVPixelBufferRef CreateCVPixelBufferFromIplImage(IplImage *iplImage);
extern CVPixelBufferRef CreateCVPixelBufferFromIplImagePassingOwnership(IplImage *iplImage, bool passOwnership);

#ifdef __cplusplus
}
#endif
