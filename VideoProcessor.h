//
//  VideoProcessor.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

@class VideoFrame;
@class PlateData;
@protocol VideoProcessorDelegate;
@protocol VideoProcessorRecordingDelegate;

typedef enum {
    ProcessingStateNoPlate,
    ProcessingStatePlateFirstFrameIdentified,
    ProcessingStateTrackingMotion
} ProcessingState;

typedef enum {
    PlateOrientationTopRead,
    PlateOrientationTopRead180DegreeRotated,
    PlateOrientationBottomRead,
    PlateOrientationBottomRead180DegreeRotated,
    PlateOrientationNoWells
#define PlateOrientationMax PlateOrientationNoWells
} PlateOrientation;


FOUNDATION_EXPORT CGAffineTransform TransformForPlateOrientation(PlateOrientation plateOrientation);


// Thread-safe.
@interface VideoProcessor : NSObject
// Instance variables are declared in the implementation file as they contain C++ objects
// which would prevent importation by C/Obj-C compilation units

- (id)initWithFileOutputDelegate:(id<VideoProcessorRecordingDelegate>)fileOutputDelegate
           fileSourceDisplayName:(NSString *)fileSourceDisplayName;     // for data labeling of file sources, pass nil if this is live
@property(readonly) NSString *fileSourceDisplayName;       // nil if a device source

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate;

- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass;
- (void)setPlateOrientation:(PlateOrientation)plateOrietation;

- (void)setShouldScanForWells:(BOOL)shouldScanForWells;
- (void)reportFinalResultsBeforeRemoval;
- (void)manuallyReportResultsAndReset;

// Synchronously processes a video frame (e.g. at frame rate)
- (void)processVideoFrame:(VideoFrame *)videoFrame debugFrameCallback:(void (^)(VideoFrame *image))callback;    // callback will be called on a background queue
- (void)noteVideoFrameWasDropped;

@end


@protocol VideoProcessorDelegate

- (void)videoProcessor:(VideoProcessor *)vp didBeginTrackingPlateAtPresentationTime:(NSTimeInterval)presentationTime;
- (NSURL *)outputFileURLForVideoProcessor:(VideoProcessor *)vp;    // provide the URL for the processor to use or nil to not record

- (void)videoProcessor:(VideoProcessor *)vp
didFinishAcquiringPlateData:(PlateData *)plateData
          successfully:(BOOL)successfully
willStopRecordingToOutputFileURL:(NSURL *)outputFileURL;     // nil if not recording; stopping is async

- (void)videoProcessorDidFinishRecordingToFileURL:(NSURL *)outputFileURL error:(NSError *)error;    // error is nil upon success

- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcodeText:(NSString *)text atTime:(NSTimeInterval)presentationTime;

@end

// Controls video file recording
@protocol VideoProcessorRecordingDelegate <NSObject>

- (void)videoProcessor:(VideoProcessor *)vp shouldBeginRecordingToURL:(NSURL *)outputFileURL withNaturalOrientation:(PlateOrientation)orientation;
- (void)videoProcessorShouldStopRecording:(VideoProcessor *)vp completion:(void (^)(NSError *error))completion; // error will be nil upon success

@end

