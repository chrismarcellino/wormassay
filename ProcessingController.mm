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
                                                       frameAbsoluteTime:(NSTimeInterval)frameAbsoluteTime;

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
        frameAbsoluteTime:(NSTimeInterval)frameAbsoluteTime
debugVideoFrameCompletionTakingOwnership:(void (^)(IplImage *debugFrame))callback
{
    dispatch_sync(_queue, ^{
        switch (_state) {
            case ProcessingStateNoPlate:
                // No well positions acquired, so start an asynchronous analysis using a copy of the image,
                // since it must persist pass the return of this method
                IplImage *videoFrameCopy = cvCloneImage(videoFrame);
                [self performWellDeterminationCalculationAsyncWithFrameTakingOwnership:videoFrameCopy frameAbsoluteTime:frameAbsoluteTime];
                // Transition the state to waiting, so we don't start any more calculations in the interim
                _state = ProcessingStateWaitingForFirstWellAnalysisResults;
                break;
            case ProcessingStateWaitingForFirstWellAnalysisResults:
                // Self-edge
                break;
            case ProcessingStateWaitingForFrameToBeginSecondWellAnalysis:
                // Begin async processing of another frame
                IplImage *videoFrameCopy = cvCloneImage(videoFrame);
                [self performWellDeterminationCalculationAsyncWithFrameTakingOwnership:videoFrameCopy frameAbsoluteTime:frameAbsoluteTime];
                _state = ProcessingStateWaitingForSecondWellAnalysisResults;
                break;
            case ProcessingStateWaitingForSecondWellAnalysisResults:
                // Self-edge
                break;:
            case ProcessingStateAcquiringMotionFramesWaitingToBeginWellAnalysis:
            case ProcessingStateAcquiringMotionFramesAndWaitingForWellAnalysisResults:
                // If we need to start another well analysis, do so async
                if (_state == ProcessingStateAcquiringMotionFramesWaitingToBeginWellAnalysis) {
                    IplImage *videoFrameCopy = cvCloneImage(videoFrame);
                    [self performWellDeterminationCalculationAsyncWithFrameTakingOwnership:videoFrameCopy frameAbsoluteTime:frameAbsoluteTime];
                    _state = ProcessingStateAcquiringMotionFramesAndWaitingForWellAnalysisResults;
                }
                
                // XXX: start storing statistics on worm motion
                break;
        }
        
        // Once we're done with the frame, draw debugging stuff on a copy and send it back
        IplImage *debugImage = cvCloneImage(videoFrame);
        for (size_t i = 0; i < wellCircles.size(); i++) {
            CvPoint center = cvPoint(cvRound(wellCircles[i][0]), cvRound(wellCircles[i][1]));
            int radius = cvRound(wellCircles[i][2]);
            // Draw the circle outline
            cvCircle(debugImage, center, radius, success ? CV_RGB(0, 0, 255) : CV_RGB(255, 255, 0), 3, 8, 0);
            
            // Draw text in the circle
            if (success) {
                CvPoint textPoint = cvPoint(center.x - radius / 2, center.y - radius / 2);
                cvPutText(debugImage,
                          wellIdentifierStringForIndex(i, wellCount).c_str(),
                          textPoint,
                          &debugImageFont,
                          cvScalar(255, 255, 0));
            }
        }
        
        [self logFormat:@"Avg pos (%.1f, %.1f).  Delta: (%.1f, %.1f) Moved: %i",
         (double)plateCenter.x, (double)plateCenter.y,
         (double)(plateCenter.x - _firstPlateCenter.x), (double)(plateCenter.y - _firstPlateCenter.y),
         plateHasMoved(_matchCount > 2 ? _secondPlateCenter : _firstPlateCenter, plateCenter)];
        
        dispatch_async(_debugFrameCallbackQueue, ^{
            callback(debugImage);
        });
    });
}

// requires _queue to be held
- (void)performWellDeterminationCalculationAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                                    fromSourceIdentifier:(NSString *)sourceIdentifier
                                                       frameAbsoluteTime:(NSTimeInterval)frameAbsoluteTime
{
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        std::vector<cv::Vec3f> wellCircles;
        int wellCount;
        bool plateFound = findWellCircles(videoFrame, wellCount, wellCircles, _wellCountHint);        // gets wells in row major order
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            switch (_state) {
                case ProcessingStateWaitingForFrameToBeginFirstWellAnaysis:
                case ProcessingStateWaitingForFrameToBeginSecondWellCalculationResults:
                case ProcessingStateAcquiringMotionFramesWaitingToBeginWellAnalysis:
                    // non-existant edges
                    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                                   reason:@"Waiting to begin a frame process, but results just arrived"
                                                 userInfo:nil];
                case ProcessingStateWaitingForFirstWellAnalysisResults:
                    if (plateFound) {
                        // Store the identifier of camera that has the plate that we're interested in
                        NSAssert(!_wellCameraSourceIdentifier, @"_wellCameraIdentifier shouldn't be set");
                        _wellCameraSourceIdentifier = [sourceIdentifier copy];
                        
                    }
                    break;
                case ProcessingStateWaitingForSecondWellAnalysisResults:
                    
                    break;
                case ProcessingStateAcquiringMotionFramesAndWaitingForWellAnalysisResults:
                    
                    break;
            }
        });
    };

/*    CvPoint plateCenter = plateCenterForWellCircles(wellCircles);*/

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
