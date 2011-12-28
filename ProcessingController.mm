//
//  ProcessingController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ProcessingController.h"
#import "ImageProcessing.hpp"

@interface ProcessingController() {
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
    CvFont debugImageFont;
    
    ProcessingState _processingState;
    NSString *_wellCameraSourceIdentifier;
    NSMutableArray *_connectedSourceIdentifiers;
    NSMutableArray *_wellFindingInProcessSourceIdentifiers;
    NSMutableArray *_barcodeFindingInProcessSourceIdentifiers;
    int _wellCountHint;
    std::vector<cv::Vec3f> _trackingWellCircles;
    std::map<std::string, std::vector<cv::Vec3f> > _lastCirclesMap;    // for debugging
    
    NSTimeInterval _firstWellFrameTime;
    NSTimeInterval _startOfTrackingMotionTime;
    NSString *_barcode;
}

- (void)performWellDeterminationCalculationAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                                    fromSourceIdentifier:(NSString *)sourceIdentifier
                                                        presentationTime:(NSTimeInterval)presentationTime;

- (void)resetCaptureStateAndReportDataIfPossible;

- (void)performBarcodeReadingAsyncWithFrameTakingOwnership:(IplImage *)videoFrame
                                      fromSourceIdentifier:(NSString *)sourceIdentifier
                                          presentationTime:(NSTimeInterval)presentationTime;

- (void)beginRecordingVideo;

- (void)appendString:(NSString *)string toPath:(NSString *)path;

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
        _connectedSourceIdentifiers = [[NSMutableArray alloc] init];
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
    [_wellFindingInProcessSourceIdentifiers release];
    [_barcodeFindingInProcessSourceIdentifiers release];
    [_wellCameraSourceIdentifier release];
    [super dealloc];
}

- (void)noteSourceIdentifierHasConnected:(NSString *)sourceIdentifier
{
    dispatch_async(_queue, ^{
        NSAssert(![_connectedSourceIdentifiers containsObject:sourceIdentifier], @"Source identifier is already connected");
        [_connectedSourceIdentifiers addObject:sourceIdentifier];
    });
}

- (void)noteSourceIdentifierHasDisconnected:(NSString *)sourceIdentifier
{
    dispatch_async(_queue, ^{
        NSAssert([_connectedSourceIdentifiers containsObject:sourceIdentifier], @"Source identifier is not connected");
        [_connectedSourceIdentifiers removeObject:sourceIdentifier];
        
        _lastCirclesMap.erase(std::string([sourceIdentifier UTF8String]));
        [_wellFindingInProcessSourceIdentifiers removeObject:sourceIdentifier];
        [_barcodeFindingInProcessSourceIdentifiers removeObject:sourceIdentifier];
        
        if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
            [self resetCaptureStateAndReportDataIfPossible];
        }
    });
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
        if (!_barcode &&
            _processingState == ProcessingStateTrackingMotion &&
            ![_barcodeFindingInProcessSourceIdentifiers containsObject:sourceIdentifier]) {
            [self performBarcodeReadingAsyncWithFrameTakingOwnership:cvCloneImage(videoFrame)
                                                fromSourceIdentifier:sourceIdentifier
                                                    presentationTime:presentationTime];
        }
        
        // Create a copy of the frame to draw debugging info on that we will send back
        IplImage *debugImage = cvCloneImage(videoFrame);
        
        // Record statistics on this image syncrhounsly (at frame rate), so that we drop frames if we can't keep up.
        // It is imperative to base all statistics on the elapsed time so that the results are independent of hardware
        // performance.
        if (_processingState == ProcessingStateTrackingMotion && [_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
            for (size_t i = 0; i < _trackingWellCircles.size(); i++) {
                float filledArea;
                CvRect boundingSquare;
                IplImage *wellImage = createEdgeImageForWellImageFromImage(videoFrame, _trackingWellCircles[i], filledArea, boundingSquare);
                
                // Draw the well image edges back in
                cvSetImageROI(debugImage, boundingSquare);
                cvCvtColor(wellImage, debugImage, CV_GRAY2BGRA);
                cvResetImageROI(debugImage);
                
                cvReleaseImage(&wellImage);
            }
            
            // XXX calculate stats
        }
        
        // Draw debugging well circles and labels
        if (_processingState == ProcessingStateNoPlate || [_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
            const std::vector<cv::Vec3f> circlesToDraw = (_processingState == ProcessingStateNoPlate) ?
                        _lastCirclesMap[std::string([sourceIdentifier UTF8String])] : _trackingWellCircles;
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
            // If the device was removed, etc., ignore any detected plates
            if ([_connectedSourceIdentifiers containsObject:sourceIdentifier]) {
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
                            _trackingWellCircles = wellCircles;     // store the first circles as the baseline for the second set
                            _firstWellFrameTime = presentationTime;
                        }
                        break;
                        
                    case ProcessingStatePlateFirstFrameIdentified:
                        // Since we've seen a plate in one camera, ignore any pending results from others
                        if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier]) {
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
                                [self resetCaptureStateAndReportDataIfPossible];
                            }
                        }
                        break;
                        
                    case ProcessingStateTrackingMotion:
                        // Since we've seen a plate in one camera, ignore any pending results from others.
                        // But if the plate is gone, moved or different, reset
                        if ([_wellCameraSourceIdentifier isEqual:sourceIdentifier] &&
                            (!plateFound || !plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles))) {
                            [self resetCaptureStateAndReportDataIfPossible];
                        }
                        
                }
            }
        });
    });
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
            if ([_connectedSourceIdentifiers containsObject:sourceIdentifier]) {
            
                if (presentationTime >= _startOfTrackingMotionTime) {
                    // XXX STORE BARCODE RESULT TO BARCODE
                }
            }
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
    _trackingWellCircles.clear();
    _firstWellFrameTime = 0.0;
    
    [_barcode release];
    _barcode = nil;
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
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    NSLog(@"%@", string);
    [string release];
    va_end(args);
}

- (void)outputFormatToCurrentCSVFile:(NSString *)format, ...
{
    /// XXX TODO
    va_list args;
    va_start(args, format);
    NSLogv(format, args);
    va_end(args);   
}

- (void)appendString:(NSString *)string toPath:(NSString *)path
{
    bool success = false;
    
    for (int i = 0; i < 2 && !success; i++) {
        int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_SHLOCK, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
        if (fd != -1) {
            NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
            @try {
                [handle seekToEndOfFile];
                [handle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
                success = true;
            } @catch (NSException *e) {
                [self logFormat:@"Unable to write to file '%@': %@", path, e];
            }
            [handle release];
        } else if (i > 0) {
            [self logFormat:@"Unable to open file '%@': %s", path, strerror(errno)];
        }
        
        // Try creating the directory hiearchy if there was an issue and try again
        if (!success) {
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            NSString *directory = [path stringByDeletingLastPathComponent];
            if (![fileManager fileExistsAtPath:directory]) {
                [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            }
            [fileManager release];
            
        }
    }
}

@end
