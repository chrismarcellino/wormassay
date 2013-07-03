//
//  AssayAnalyzer.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

// Shared defines
NSTimeInterval IgnoreFramesPostMovementTimeInterval();

@class VideoFrame;
@class PlateData;

// Well analyzers will only be instantiated (using -init) when a well positions are being tracked.
// A reference to the debug image is provided to each processing method which may be used to draw on to
// display information to the user (e.g. movement indicators or worm contours, etc.).
@protocol AssayAnalyzer <NSObject>

// User visible analyzer name
+ (NSString *)analyzerName;

// Return YES if multiple instances of the -processVideoFrame... method can be called on separate threads simultaneously.
- (BOOL)canProcessInParallel;

// Called once, before any frame processing begins to allow class to initialized data structures and create PlateData columns.
- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData;

// These three methods are called each time a frame arrives. The first is called once per frame, synchronously, to allow the
// analyzer to perform any preprocessing or setup. 
// PlateData should not be modified, but may be retained indefinitely (as resources permit). DebugImage does not have a ROI set.
// The callee can return NO if processing of this frame should be aborted (e.g. poor image quality or movement) or if all computation is
// already complete (e.g. entire frame was processed here), in which case the processVideoFrame:... method will not be called for this 
// frame, but the didEndFrame:... method will still be called.
- (BOOL)willBeginFrameProcessing:(VideoFrame *)videoFrame debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData;

// This method is called once for each well on the plate (potentially in parallel if -canCallProcessMethodInParallel returns YES.)
// The videoFrame and debugImage have their ROI set to cover only the square corresponding to the exact boundaries of the well circle.
// Hence, the center point of the circle is the box midpoint. Well is 0 indexed and in row-major order.
// The underlying videoFrame IplImage is unique to the callee and may be modified, but the underlying data may not.
// Both the plateData underlying IplImage and data may be modified, but only read/write atomicity is guaranteed for the ROI.
- (void)processVideoFrameWellSynchronously:(IplImage*)wellImage
                                   forWell:(int)well
                                debugImage:(IplImage*)debugImage
                          presentationTime:(NSTimeInterval)presentationTime
                                 plateData:(PlateData *)plateData;

// This method is called after all -willBeginFrameProcessing: calls returns, to allow comitting of any final plate data for this frame.
- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData;

// The final callback before this instance is released. Use for any final post-processing.
- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData;

// Minimum for reporting of data
- (NSTimeInterval)minimumTimeIntervalProcessedToReportData;
- (NSUInteger)minimumSamplesProcessedToReportData;

@end
