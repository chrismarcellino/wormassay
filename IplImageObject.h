//
//  IplImageObject.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <ApplicationServices/ApplicationServices.h>
#import "opencv2/core/core_c.h"

// A reference-counted wrapper over IplImage to avoid unnecssary memory copying during the image pipeline.
@interface IplImageObject : NSObject <NSCopying> {
    IplImage *_image;
    NSData *_dataIfVMCopiedAttempted;
}

- (id)initWithIplImageTakingOwnership:(IplImage *)image;

// VM copying is much faster than memcpy()ing if the resulting image copy does not need to be modified.
// Intel Core 2 Duo 2.2 Ghz, VM copying an 8 MB buffer takes 12 us as where memcpy()ing takes 3060 us. 
// If the resulting destination VM copied OR **original source** buffer is modified significantly,
// the operation becomes orders of magnitudes slower
// than if the image was memcpy()ed in the first place.
- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer resultChannelCount:(int)outChannels vmCopyIfPossible:(BOOL)attemptVmCopy;
- (id)initByCopyingCGImage:(CGImageRef)cgImage resultChannelCount:(int)outChannels;

@property(readonly) IplImage *image;

@end
