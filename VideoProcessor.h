//
//  VideoProcessor.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QTKit/QTKit.h>
#import "opencv2/core/core_c.h"

@class VideoFrame;
@class PlateData;
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

// CaptureSession is used for recording
- (id)initWithCaptureSession:(QTCaptureSession *)captureSession fileSourceFilename:(NSString *)fileSourceFilename;
@property(readonly) NSString *fileSourceFilename;       // nil if a device source

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate;
- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass;

- (void)setShouldScanForWells:(BOOL)shouldScanForWells;
- (void)reportFinalResultsBeforeRemoval;

// Synchronously processes a video frame (e.g. at frame rate)
- (void)processVideoFrame:(VideoFrame *)videoFrame debugFrameCallback:(void (^)(VideoFrame *image))callback;    // callback will be called on a background queue

- (void)noteVideoFrameWasDropped;

@end


@protocol VideoProcessorDelegate

- (void)videoProcessor:(VideoProcessor *)vp didBeginTrackingPlateAtPresentationTime:(NSTimeInterval)presentationTime;
- (void)videoProcessor:(VideoProcessor *)vp shouldBeginRecordingWithCaptureOutput:(QTCaptureFileOutput *)captureFileOutput;
- (void)videoProcessor:(VideoProcessor *)vp
didFinishAcquiringPlateData:(PlateData *)plateData
          successfully:(BOOL)successfully
stopRecordingCaptureOutput:(QTCaptureFileOutput *)recordingCaptureOutput
        captureSession:(QTCaptureSession *)captureSession;
- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcodeText:(NSString *)text atTime:(NSTimeInterval)presentationTime;

@end
