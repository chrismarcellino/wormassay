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

// A reference-counted wrapper over IplImage to avoid unnecessary memory copying during the image pipeline.
@interface IplImageObject : NSObject <NSCopying> {
    IplImage *_image;
}

- (id)initWithIplImageTakingOwnership:(IplImage *)image;

- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer resultChannelCount:(int)outChannels;
- (id)initByCopyingCGImage:(CGImageRef)cgImage resultChannelCount:(int)outChannels;

@property(readonly) IplImage *image;

@end
