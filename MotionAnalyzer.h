//
//  MotionAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

@class VideoFrame;
@class PlateData;

// Motion analyzers will only be instantiated (using -init) when a well positions are being tracked.
// A reference to the debug image is provided to each processing method which may be used to draw on to
// display information to the user.
@protocol MotionAnalyzer

// User visible analyzer name
- (NSString *)analyzerName;

// Return YES if multiple instances of the -process... method can be called on separate threads simultaneously. 
- (BOOL)canCallProcessMethodInParallel;

// These three methods are called each time a frame arrives. The first is called once per frame, synchronously, to allow the
// analyzer to perform any preprocessing or setup.
- (BOOL)willBeginFrameProcessing:(VideoFrame *)frame;
// This method is called once for each well on the plate (potentially in parallel if -canCallProcessMethodInParallel returns YES.)
// The videoFrame and debugImage have their ROI set to cover only the square corresponding to the exact boundaries of the well circle.
// The underlying videoFrame IplImage is unique to the callee and may be modified, but the underlying data may not.
// Both the plateData underlying IplImage and data may be modified, but only read/write atomicity is guaranteed for the ROI.
// The callee can return NO if processing of this frame should be aborted (e.g. poor image quality or movement), in which case
// no further delegate methods will be called.
- (void)processVideoFrameWellSynchronously:(VideoFrame *)videoFrame debugImage:(VideoFrame *)debugImage plateData:(PlateData *)plateData;
// This method is called after all -willBeginFrameProcessing: calls to allow comitting of 
- (void)didEndFrameProcessing:(VideoFrame *)

@end
