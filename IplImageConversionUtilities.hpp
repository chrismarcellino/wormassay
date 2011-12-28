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

extern IplImage *CreateIplImageFromCVPixelBuffer(CVPixelBufferRef cvImageBuffer, int outChannels);

extern CVPixelBufferRef CreateCVPixelBufferFromIplImage(IplImage *iplImage);
extern CVPixelBufferRef CreateCVPixelBufferFromIplImagePassingOwnership(IplImage *iplImage, bool passOwnership);

#ifdef __cplusplus
}
#endif
