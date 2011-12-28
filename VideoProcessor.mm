//
//  VideoProcessor.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoProcessor.h"
#import "ImageProcessing.hpp"
#import "IplImageObject.h"

@interface VideoProcessor() {
    NSString *_sourceIdentifier;
    id<VideoProcessorDelegate> _delegate;        // not retained
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
    
    BOOL _shouldScanForWells;
    BOOL _scanningForWells;
    BOOL _scanningForBarcodes;
    
    ProcessingState _processingState;
    int _wellCountHint;
    NSTimeInterval _firstWellFrameTime;
    NSTimeInterval _startOfTrackingMotionTime;
    
    IplImageObject *_lastFrame;     // when tracking
    std::vector<cv::Vec3f> _trackingWellCircles;    // circles used for tracking
    std::vector<cv::Vec3f> _lastCircles;   // for debugging
}

- (void)performWellDeterminationCalculationAsyncWithFrame:(IplImageObject *)videoFrame presentationTime:(NSTimeInterval)presentationTime;
- (void)performBarcodeReadingAsyncWithFrame:(IplImageObject *)videoFrame presentationTime:(NSTimeInterval)presentationTime;

- (void)resetCaptureStateAndReportResults;
- (void)beginRecordingVideo;

@end


@implementation VideoProcessor

- (id)initWithSourceIdentifier:(NSString *)sourceIdentifier
{
    if ((self = [super init])) {
        _sourceIdentifier = [sourceIdentifier copy];
        _queue = dispatch_queue_create("edu.ucsf.chrismarcellino.nematodeassay.videoprocessor", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("edu.ucsf.chrismarcellino.nematodeassay.callback", NULL);
        _processingState = ProcessingStateNoPlate;
    }
    return self;
}

- (void)dealloc
{
    [_sourceIdentifier release];
    dispatch_release(_queue);
    dispatch_release(_debugFrameCallbackQueue);
    [_lastFrame release];
    [super dealloc];
}

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate
{
    dispatch_async(_queue, ^{
        _delegate = delegate;       // not retained
    });
}

- (void)setShouldScanForWells:(BOOL)shouldScanForWells
{
    dispatch_async(_queue, ^{
        _shouldScanForWells = shouldScanForWells;
        // If no longer scanning (e.g. another camera has a plate), reset our state
        if (!shouldScanForWells) {
            [self resetCaptureStateAndReportResults];
        }
    });
}

- (void)processVideoFrame:(IplImageObject *)videoFrame
         presentationTime:(NSTimeInterval)presentationTime
       debugFrameCallback:(void (^)(IplImageObject *image))callback
{
    // This method is synchronous so that we don't enqueue frames faster than they should be processed. QT will drop the overflow.
    dispatch_sync(_queue, ^{
        // If we're not already processing an image for wells, and no other processor has a plate, schedule an async processing
        if (!_scanningForWells && _shouldScanForWells) {
            [self performWellDeterminationCalculationAsyncWithFrame:videoFrame presentationTime:presentationTime];
        }
        
        // If we are capturing, begin searching frames for a barcode until we obtrain one for this plate
        if (!_scanningForBarcodes && _processingState == ProcessingStateTrackingMotion) {
            [self performBarcodeReadingAsyncWithFrame:videoFrame presentationTime:presentationTime];
        }
        
        // Create a copy of the frame to draw debugging info on, which we will send back
        IplImageObject *debugImage = [videoFrame copy];
        
        // Record statistics on the tracked image synchronously (at frame rate), so that we drop frames if we can't keep up.
        // It is important to base all statistics on the elapsed time so that the results are independent of hardware
        // performance.
        if (_processingState == ProcessingStateTrackingMotion) {
            if (_lastFrame) {
                // XXX calculate and store stats (don't do the first every frame?)
                calculateEdgePixelsForWellsFromImages([videoFrame image], _trackingWellCircles, [debugImage image]);
                std::vector<int> movedPixelCounts = calculateMovedPixelsForWellsFromImages([_lastFrame image],
                                                                                           [videoFrame image],
                                                                                           _trackingWellCircles,
                                                                                           [debugImage image]);
            }
            
            // Store the current image for the next pass
            [_lastFrame release];
            _lastFrame = [videoFrame retain];
        }
        
        // Draw debugging well circles and labels on each frame
        if (_shouldScanForWells) {
            CvScalar circleColor = _processingState == ProcessingStateNoPlate ? CV_RGBA(255, 0, 0, 255) :
                (_processingState == ProcessingStatePlateFirstFrameIdentified ? CV_RGBA(255, 255, 0, 255) : CV_RGBA(0, 255, 0, 255));
            drawWellCirclesAndLabelsOnDebugImage(_processingState == ProcessingStateNoPlate ? _lastCircles : _trackingWellCircles,
                                                 circleColor,
                                                 _processingState == ProcessingStateTrackingMotion,
                                                 [debugImage image]);
        }
        
        // Dispatch the debug image asynchronously to increase parallelism 
        dispatch_async(_debugFrameCallbackQueue, ^{
            callback(debugImage);
        });
        [debugImage release];
    });
}

// requires _queue to be held
- (void)performWellDeterminationCalculationAsyncWithFrame:(IplImageObject *)videoFrame presentationTime:(NSTimeInterval)presentationTime
{
    _scanningForWells = YES;
    
    // Get instance variables while holding _queue for thread-safety
    int wellCountHint = _wellCountHint;
    bool searchAllPlateSizes = _processingState == ProcessingStateNoPlate;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Get wells in row major order
        std::vector<cv::Vec3f> wellCircles;
        bool plateFound;
        if (searchAllPlateSizes) {
            plateFound = findWellCircles([videoFrame image], wellCircles, wellCountHint);
        } else {
            plateFound = findWellCirclesForPlateCount([videoFrame image], wellCountHint, wellCircles);
        }
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            _scanningForWells = NO;
            // If the device was removed, etc., ignore any detected plates
            if (_shouldScanForWells) {
                // Store the circles for debugging later
                _lastCircles = wellCircles;
                
                // If we've found a plate, store the well count to improve the performance of future searches
                if (plateFound) {
                    _wellCountHint = wellCircles.size();
                }
                
                switch (_processingState) {
                    case ProcessingStateNoPlate:
                        if (plateFound) {
                            _processingState = ProcessingStatePlateFirstFrameIdentified;
                            _trackingWellCircles = wellCircles;     // store the first circles as the baseline for the second set
                            _firstWellFrameTime = presentationTime;
                        }
                        break;
                        
                    case ProcessingStatePlateFirstFrameIdentified:
                        if (plateFound) {
                            // If the second identification yields matching results as the first, and they are spread by at least
                            // 100 ms, begin motion tracking and video recording
                            if (plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles) &&
                                presentationTime - _firstWellFrameTime >= 0.100) {
                                _processingState = ProcessingStateTrackingMotion;
                                _trackingWellCircles = wellCircles; // store the second set as the baseline for all remaining sets
                                _startOfTrackingMotionTime = presentationTime;
                                
                                [self beginRecordingVideo];
                            } else {
                                // There is still a plate, but it doesn't match or more likely is still moving moved, or not enough
                                // time has lapsed, so we stay in this state, but update the circles
                                _trackingWellCircles = wellCircles;
                            }
                        } else {
                            // Plate is gone so reset
                            [self resetCaptureStateAndReportResults];
                        }
                        break;
                        
                    case ProcessingStateTrackingMotion:
                        // Since we've seen a plate in one camera, ignore any pending results from others.
                        // But if the plate is gone, moved or different, reset
                        if (!plateFound || !plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles)) {
                            [self resetCaptureStateAndReportResults];
                        }
                }
            }
        });
    });
}

// requires _queue to be held
- (void)performBarcodeReadingAsyncWithFrame:(IplImageObject *)videoFrame presentationTime:(NSTimeInterval)presentationTime
{
    _scanningForBarcodes = YES;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // XXX DO BARCODE FIND HERE (SYNC).   FIGURE OUT A WAY TO PREVENT FROM OVER BARCODE SEARCHING!!
        sleep(1);
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            _scanningForBarcodes = NO;
            if (presentationTime >= _startOfTrackingMotionTime) {
                // XXX STORE BARCODE RESULT TO BARCODE
            }
        });
    });
}

// requires _queue to be held
- (void)resetCaptureStateAndReportResults
{
    // XXX IF RECORDING
    //[self endRecordingVideoWithName];
    // XXX if (RECORCORDING && > 5 seconds total), save the stats and stuff
    
    _processingState = ProcessingStateNoPlate;
    
    _startOfTrackingMotionTime = _firstWellFrameTime = 0.0;
    _trackingWellCircles.clear();
    _lastCircles.clear();
}

- (void)beginRecordingVideo
{
    
}

@end
