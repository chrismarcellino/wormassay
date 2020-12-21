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
#import <CoreGraphics/CoreGraphics.h>
#import <opencv2/core/core_c.h>

// A reference-counted wrapper over IplImage to avoid unnecessary memory copying during the image pipeline.
// The backing store is guaranteed to be valid and its address unchanged during the lifetime of the VideoFrame,
// however the actual graphical contents of the image may be modified (i.e. as part of the image pipeline)
// via access to the underlying IplImage's bytes and thus instances of this class should be considered
// *mutable* even if the properties themselves are not.
@interface VideoFrame : NSObject <NSCopying> {
    IplImage *_image;
    NSTimeInterval _presentationTime;
}

- (id)initWithIplImageTakingOwnership:(IplImage *)image presentationTime:(NSTimeInterval)presentationTime;
// Generates BGRA IplImages, converting if necessary from 422YpCbCr8.
- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer naturalSize:(NSSize)naturalSize presentationTime:(NSTimeInterval)presentationTime;

@property(readonly) IplImage *image;
@property(readonly) NSTimeInterval presentationTime;

// Note that these methods return objects that share the mutable data underlying the callee, and not copies of it.
// They will retain the callee during its lifetime to ensure the backing store remains valid.
// (See the comment above regarding mutability for more details.)
// If you wish to maintain a copy of the image, or for example, perform computations or pass the method to async
// system functions while the original could be modified, you should -copy this object prior to using these methods. 
- (NSData *)imageData;
- (CGImageRef)createCGImage  CF_RETURNS_RETAINED;

@end
