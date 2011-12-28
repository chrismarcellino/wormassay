//
//  ProcessingController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ProcessingController.h"
#import "ImageProcessing.hpp"

@interface ProcessingController()

- (void)performWellDeterminationCalculationAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                                    fromSourceIdentifier:(NSString *)sourceIdentifier
                                                        presentationTime:(NSTimeInterval)presentationTime;

- (void)resetCaptureStateAndReportDataIfPossible;

- (void)performBarcodeReadingAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                      fromSourceIdentifier:(NSString *)sourceIdentifier
                                          presentationTime:(NSTimeInterval)presentationTime;

- (void)beginRecordingVideo;

@end


@implementation ProcessingController

+ (ProcessingController *)sharedInstance
{
    static dispatch_once_t pred = 0;
    static ProcessingController *sharedInstance = nil;
    dispatch_once(&pred, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if ((self = [super init])) {
        _queue = dispatch_queue_create("ProcessingController queue", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("Debug frame callback queue", NULL);
        _processingState = ProcessingStateNoPlate;
        _wellFindingInProcessSourceIdentifiers = [[NSMutableArray alloc] init];
        _barcodeFindingInProcessSourceIdentifiers = [[NSMutableArray alloc] init];
        
        // Initialize the debugging font
        cvInitFont(&debugImageFont, CV_FONT_HERSHEY_SIMPLEX, 1.0, 1.0, 0, 1);
    }
    return self;
}

- (void)dealloc
{
    dispatch_release(_queue);
    dispatch_release(_debugFrameCallbackQueue);
    [_wellCameraSourceIdentifier release];
    [super dealloc];
}

// Caller is responsible for calling cvReleaseImage() on debugFrame. Block will be called on an arbitrary thread. 
- (void)processVideoFrame:(IplImage *)videoFrame
     fromSourceIdentifier:(NSString *)sourceIdentifier
         presentationTime:(NSTimeInterval)presentationTime
debugVideoFrameCompletionTakingOwnership:(void (^)(IplImage *debugFrame))callback
{
    dispatch_sync(_queue, ^{
        // If we're not already in the process of anaylzing a frame from this source for wells, and we are interested
        // in this source, start an asynchronous analysis using a copy of the image (since the copy will persist pass
        // the return of this method.)
        bool alreadySearchingForThisSouce = [_wellFindingInProcessSourceIdentifiers containsObject:sourceIdentifier];
        bool interestedInThisSouce = _processingState == ProcessingStateNoPlate || [_wellCameraSourceIdentifier isEqual:sourceIdentifier];
        if (!alreadySearchingForThisSouce && interestedInThisSouce) {
            [self performWellDeterminationCalculationAsyncWithFrameTakingOwnership:cvCloneImage(videoFrame)
                                                              fromSourceIdentifier:sourceIdentifier
                                                                  presentationTime:presentationTime];
        }
        
        // If we are capturing, begin searching frames for a barcode until we obtrain one for this plate
        if (!_barcode && _processingState == ProcessingStateTrackingMotion && ![_barcodeFindingInProcessSourceIdentifiers containsObject:sourceIdentifier]) {
            [self performBarcodeReadingAsyncWithFrameTakingOwnership:cvCloneImage(videoFrame)
                                                fromSourceIdentifier:sourceIdentifier
                                                    presentationTime:presentationTime];
        }
        
        // Record statistics on this image syncrhounsly (at frame rate), so that we drop frames if we can't keep up.
        // It is imperative to base all statistics on the elapsed time so that the results are independent of hardware
        // performance.
        if (_processingState == ProcessingStateTrackingMotion) {
            // XXX calculate stats
        }
        
        // Once we're done with the frame, draw debugging stuff on a copy of the plate camera's frames and send it back
        IplImage *debugImage = cvCloneImage(videoFrame);
        if (_processingState == ProcessingStateNoPlate || [_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
            const std::vector<cv::Vec3f> circlesToDraw = (_processingState == ProcessingStateNoPlate) ?
                        _lastCirclesMap[std::string([sourceIdentifier UTF8String])] : _baselineWellCircles;
            for (size_t i = 0; i < circlesToDraw.size(); i++) {
                CvPoint center = cvPoint(cvRound(circlesToDraw[i][0]), cvRound(circlesToDraw[i][1]));
                int radius = cvRound(circlesToDraw[i][2]);
                // Draw the circle outline
                CvScalar color = (_processingState == ProcessingStateNoPlate) ? 
                        CV_RGB(255, 0, 0) :
                        ((_processingState == ProcessingStatePlateFirstFrameIdentified) ? CV_RGB(255, 255, 0) : CV_RGB(0, 255, 0));
                cvCircle(debugImage, center, radius, color, 3, 8, 0);
                
                // Draw text in the circle
                if (_processingState == ProcessingStateTrackingMotion) {
                    CvPoint textPoint = cvPoint(center.x - radius / 2, center.y - radius / 2);
                    cvPutText(debugImage,
                              wellIdentifierStringForIndex(i, circlesToDraw.size()).c_str(),
                              textPoint,
                              &debugImageFont,
                              cvScalar(255, 255, 0));
                }
            }
        }
        dispatch_async(_debugFrameCallbackQueue, ^{
            callback(debugImage);
        });
    });
}

- (void)noteSourceIdentifierHasDisconnected:(NSString *)sourceIdentifier
{
    dispatch_sync(_queue, ^{
        if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
            [self resetCaptureStateAndReportDataIfPossible];
        }
    });
}

// requires _queue to be held
- (void)performWellDeterminationCalculationAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                                    fromSourceIdentifier:(NSString *)sourceIdentifier
                                                        presentationTime:(NSTimeInterval)presentationTime
{
    [_wellFindingInProcessSourceIdentifiers addObject:sourceIdentifier];
    
    // Get instance variables while holding _queue
    int wellCountHint = _wellCountHint;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        std::vector<cv::Vec3f> wellCircles;
        bool plateFound = findWellCircles(videoFrame, wellCircles, wellCountHint);        // gets wells in row major order
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            [_wellFindingInProcessSourceIdentifiers removeObject:sourceIdentifier];
            
            // Store the circles for debugging later
            _lastCirclesMap[std::string([sourceIdentifier UTF8String])] = wellCircles;
            
            // If we've found a plate, store the well count to improve the performance of future searches
            if (plateFound) {
                _wellCountHint = wellCircles.size();
            }
            
            switch (_processingState) {
                case ProcessingStateNoPlate:
                    if (plateFound) {
                        NSAssert(!_wellCameraSourceIdentifier, @"In ProcessingStateNoPlate, but _wellCameraSourceIdentifier != nil");
                        _wellCameraSourceIdentifier = [sourceIdentifier copy];
                        _processingState = ProcessingStatePlateFirstFrameIdentified;
                        _baselineWellCircles = wellCircles;     // store the first circles as the baseline for the second set
                    }
                    break;
                    
                case ProcessingStatePlateFirstFrameIdentified:
                    // Since we've seen a plate in one camera, ignore any pending results from others
                    if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
                        if (plateFound) {
                            if (plateSequentialCirclesAppearSameAndStationary(_baselineWellCircles, wellCircles)) {
                                _processingState = ProcessingStateTrackingMotion;
                                _baselineWellCircles = wellCircles; // store the second set as the baseline for all remaining sets
                                _startOfTrackingMotionTime = presentationTime;
                                
                                [self beginRecordingVideo];
                            } else {
                                // There is still a plate, but it doesn't match or has moved so we stay in this state, but update the circles
                                _baselineWellCircles = wellCircles;
                            }
                        } else {
                            // Plate is gone so reset
                            [self resetCaptureStateAndReportDataIfPossible];
                        }
                    }
                    break;
                    
                case ProcessingStateTrackingMotion:
                    // Since we've seen a plate in one camera, ignore any pending results from others.
                    // But if the plate is gone, moved or different, reset
                    if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier] &&
                        (!plateFound || !plateSequentialCirclesAppearSameAndStationary(_baselineWellCircles, wellCircles))) {
                        [self resetCaptureStateAndReportDataIfPossible];
                    }
                            
            }
            
#if 1       // DEBUG
            CvPoint center = plateCenterForWellCircles(wellCircles);
            CvPoint benchmarkCenter = plateCenterForWellCircles(_baselineWellCircles);
            [self logFormat:@"Avg pos (%.1f, %.1f).  Delta from benchmark: (%.1f, %.1f)",
             (double)center.x, (double)center.y, (double)(center.x - benchmarkCenter.x), (double)(center.y - benchmarkCenter.y)];
#endif
        });
    });
}

// requires _queue to be held
- (void)resetCaptureStateAndReportDataIfPossible
{
    // XXX IF RECORDING
        //[self endRecordingVideoWithName];
    
    // XXX if (RECORCORDING && > 5 seconds total), save the stats and stuff
    
    _processingState = ProcessingStateNoPlate;
    [_wellCameraSourceIdentifier release];
    _wellCameraSourceIdentifier = nil;
    
    _startOfTrackingMotionTime = 0.0;
    
    [_barcode release];
    _barcode = nil;
}

// requires _queue to be held
- (void)performBarcodeReadingAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                      fromSourceIdentifier:(NSString *)sourceIdentifier
                                          presentationTime:(NSTimeInterval)presentationTime
{
    [_barcodeFindingInProcessSourceIdentifiers addObject:sourceIdentifier];
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // XXX DO BARCODE FIND HERE (SYNC)
        sleep(1);
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            [_barcodeFindingInProcessSourceIdentifiers removeObject:sourceIdentifier];
            
            if (presentationTime >= _startOfTrackingMotionTime) {
                // XXX STORE BARCODE RESULT TO BARCODE
            }
        });
    });
}

- (void)beginRecordingVideo
{
    
}

- (void)logFormat:(NSString *)format, ...
{
    // XXX: todo, write documents folder appropriately, and show on screen in a window.
    // for now, syslog.  (remember to add locking)
    va_list args;
    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}

@end
