//
//  VideoProcessor.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

@class IplImageObject;
@protocol VideoProcessorDelegate;

typedef enum {
    ProcessingStateNoPlate,
    ProcessingStatePlateFirstFrameIdentified,
    ProcessingStateTrackingMotion
} ProcessingState;


// Thread-safe.
@interface VideoProcessor : NSObject
// Instance variables are declared in the implementation file as they contain C++ objects
// which would prevent importation by C/Obj-C compilation units

- (id)initWithSourceIdentifier:(NSString *)sourceIdentifier;
- (void)setDelegate:(id<VideoProcessorDelegate>)delegate;

- (void)setShouldScanForWells:(BOOL)shouldScanForWells;

// Synchronously processes a video frame (e.g. at frame rate)
- (void)processVideoFrame:(IplImageObject *)videoFrame
         presentationTime:(NSTimeInterval)presentationTime
       debugFrameCallback:(void (^)(IplImageObject *image))callback;    // callback will be called on a background queue

@end


@protocol VideoProcessorDelegate

- (void)videoProcessorDidBeginTrackingPlate:(VideoProcessor *)vp;
- (void)videoProcessor:(VideoProcessor *)vp didFinishAcquiringPlateResults:(id)something;
- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcodeText:(NSString *)text atTime:(NSTimeInterval)presentationTime;

@end
