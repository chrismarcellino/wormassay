//
//  VideoFrame.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <ApplicationServices/ApplicationServices.h>
#import "opencv2/core/core_c.h"

// A reference-counted wrapper over IplImage to avoid unnecessary memory copying during the image pipeline.
@interface VideoFrame : NSObject <NSCopying> {
    IplImage *_image;
    NSTimeInterval _presentationTime;
}

- (id)initWithIplImageTakingOwnership:(IplImage *)image presentationTime:(NSTimeInterval)presentationTime;

- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer resultChannelCount:(int)outChannels presentationTime:(NSTimeInterval)presentationTime;
- (id)initByCopyingCGImage:(CGImageRef)cgImage resultChannelCount:(int)outChannels presentationTime:(NSTimeInterval)presentationTime;

@property(readonly) IplImage *image;
@property(readonly) NSTimeInterval presentationTime;

@end
