//
//  VideoProcessor.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "VideoProcessor.h"
#import "CvUtilities.hpp"
#import "VideoFrame.h"
#import "PlateData.h"
#import "AssayAnalyzer.h"
#import "WellFinding.hpp"
#import "NSOperationQueue-Utility.h"
#import "VideoProcessorController.h"   // for RunLog()
#import <Vision/Vision.h>
// OpenCV
#import <opencv2/imgproc/types_c.h>
#import <opencv2/imgproc/imgproc_c.h>

#if BYTE_ORDER == BIG_ENDIAN
#define NS_WCHAR_ENCODING NSUTF32BigEndianStringEncoding
#elif BYTE_ORDER == LITTLE_ENDIAN
#define NS_WCHAR_ENCODING NSUTF32LittleEndianStringEncoding
#endif


static const NSTimeInterval MinimumWellMatchTimeToBeginTracking = 0.500; // 500 ms
static const NSTimeInterval BarcodeScanningPeriod = 0.5;
static const NSTimeInterval BarcodeRepeatSuccessCount = 3;      // to avoid incidental capture
static const NSTimeInterval PresentationTimeDistantPast = -DBL_MAX;
static const double WellDetectingAverageDeltaEndIdleThreshold = 5.0;
static const NSTimeInterval WellDetectingUnconditionalSearchPeriod = 10.0;

// Time lapse defaults keys
static NSString *const TimeLapseAnalyzeEnabled = @"TimeLapseAnalyzeEnabled";
static NSString *const TimeLapseAnalyzeDuration = @"TimeLapseAnalyzeDuration";
static NSString *const TimeLapseLockoutInterval = @"TimeLapseLockoutInterval";
static const NSTimeInterval TimeLapseAnalyzeDurationDefault = 60.0;
static const NSTimeInterval TimeLapseLockoutIntervalDefault = 5 * 60.0;


CGAffineTransform TransformForPlateOrientation(PlateOrientation plateOrientation)
{
    CGAffineTransform transform;
    switch (plateOrientation) {
        case PlateOrientationTopRead:
        case PlateOrientationNoWells:
            transform = CGAffineTransformIdentity;
            break;
        case PlateOrientationTopRead180DegreeRotated:
            transform = CGAffineTransformMakeScale(-1.0, -1.0); // horizontal and vertical flip
            break;
        case PlateOrientationBottomRead:
            transform = CGAffineTransformMakeScale(-1.0, 1.0);  // horizontal flip
            break;
        case PlateOrientationBottomRead180DegreeRotated:
            transform = CGAffineTransformMakeScale(1.0, -1.0);  // vertical flip
            break;
    }
    return transform;
}


// Here for C++ build safety
@interface VideoProcessor() {
    __weak id<VideoProcessorDelegate> _delegate;                        // not retained
    __weak id<VideoProcessorRecordingDelegate> _fileOutputDelegate;     // not retained
    NSString *_fileSourceDisplayName;
    Class _assayAnalyzerClass;
    PlateOrientation _plateOrientation;
    NSURL *_fileOutputURL;
    
    BOOL _shouldScanForWells;
    BOOL _scanningForWells;
    BOOL _scanningForBarcodes;
    
    ProcessingState _processingState;
    int _wellCountHint;
    CvScalar _lastWellAnalyzedFrameAverageValues;
    NSTimeInterval _firstWellFrameTime;     // not the beginning of tracking
    NSTimeInterval _lastBarcodeScanTime;
    NSTimeInterval _lastWellAnalysisBeginTime;  // the last time a well finding analysis was started. used to do idling when no plates present.
    // These two are used only for the optional time lapse feature
    NSTimeInterval _startOfTrackingFrameTime;
    NSTimeInterval _lockoutStartFrameTime;
    
    id<AssayAnalyzer> _assayAnalyzer;
    PlateData *_plateData;
    std::vector<Circle> _trackingWellCircles;    // circles used for tracking
    CvSize _trackedImageSize;
    std::vector<Circle> _lastCircles;       // the last circles returned by the well finder (not necessarily same as tracking)
    
    NSString *_lastBarcodeThisProcessor;
    NSUInteger _lastBarcodeThisProcessorRepeatCount;
}

@end


@implementation VideoProcessor

@synthesize fileSourceDisplayName = _fileSourceDisplayName;

- (id)initWithFileOutputDelegate:(id<VideoProcessorRecordingDelegate>)fileOutputDelegate
           fileSourceDisplayName:(NSString *)fileSourceDisplayName
{
    if ((self = [super init])) {
        _fileOutputDelegate = fileOutputDelegate;
        _fileSourceDisplayName = [fileSourceDisplayName copy];
        _lastWellAnalysisBeginTime = PresentationTimeDistantPast;
        _lockoutStartFrameTime = PresentationTimeDistantPast;
    }
    return self;
}

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate
{
    @synchronized (self) {
        _delegate = delegate;       // not retained
    };
}

- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass
{
    @synchronized (self) {
        if (_assayAnalyzerClass != assayAnalyzerClass) {
            _assayAnalyzerClass = assayAnalyzerClass;
            [self resetCaptureStateAndReportResults];
        }
    };
}

- (void)setPlateOrientation:(PlateOrientation)plateOrientation
{
    @synchronized (self) {
        if (_plateOrientation != plateOrientation) {
            _plateOrientation = plateOrientation;
            [self resetCaptureStateAndReportResults];
        }
    };
}

- (void)setShouldScanForWells:(BOOL)shouldScanForWells
{
    @synchronized (self) {
        _shouldScanForWells = shouldScanForWells;
        // If no longer scanning (e.g. another camera has a plate), reset our state
        if (!shouldScanForWells) {
            [self resetCaptureStateAndReportResults];
        }
    };
}

- (void)processVideoFrame:(VideoFrame *)videoFrame debugFrameCallback:(void (^)(VideoFrame *image))callback
{
    NSTimeInterval processingStartTime = CACurrentMediaTime();
    VideoFrame *debugFrame;
    
    // This method is synchronous so that we don't enqueue frames faster than they should be processed. The document will drop the overflow.
    @synchronized (self) {
        if (_plateData) {
            [_plateData incrementReceivedFrameCount];
        }
        
        // Always look for barcodes since another camera might have a plate. Do this before rotating/flipping
        // since barcode stickers should always be plainly visible by a camera (except simple rotation may be needed.)
        if (!_scanningForBarcodes && _lastBarcodeScanTime < [videoFrame presentationTime] - BarcodeScanningPeriod) {
            _scanningForBarcodes = YES;
            VideoFrame *copy = [videoFrame copy];       // copy prior to dispatching since we are going to flip the data below
            // Perform the calculation on a concurrent queue so that we don't block the current thread
            [NSOperationQueue addOperationToGlobalQueueWithBlock:^{
                [self performBarcodeReadingSynchronouslyWithFrame:copy];
            }];
        }
        
        // Flip/rotate image if necessary
        BOOL flip = NO;
        int flipMode;
        switch (_plateOrientation) {
            case PlateOrientationTopRead:
            case PlateOrientationNoWells:
                break;
            case PlateOrientationTopRead180DegreeRotated:
                flip = YES;
                flipMode = -1;
                break;
            case PlateOrientationBottomRead:
                flip = YES;
                flipMode = 1;
                break;
            case PlateOrientationBottomRead180DegreeRotated:
                flip = YES;
                flipMode = 0;
                break;
        }
        if (flip) {
            cvFlip([videoFrame image], NULL, flipMode);
        }
        
        // If we're not already searching for wells, and no other processor has a plate, schedule an async processing
        if (!_scanningForWells && _shouldScanForWells) {
            // See if this plate looks grossly different from the last one we scanned.
            // If so, scan immediately, otherwise conserve CPU by scanning periodically.
            CvScalar currentAvg = cvAvg([videoFrame image]);
            double averageDelta = ABS(currentAvg.val[0] - _lastWellAnalyzedFrameAverageValues.val[0]) +
                                    ABS(currentAvg.val[1] - _lastWellAnalyzedFrameAverageValues.val[1]) +
                                    ABS(currentAvg.val[2] - _lastWellAnalyzedFrameAverageValues.val[2]) / 3;
            
            // Always scan if we are not idle, and scan if the average values change significantly or if we haven't scanned in a while
            if (_processingState != ProcessingStateNoPlate ||
                averageDelta > WellDetectingAverageDeltaEndIdleThreshold ||
                _lastWellAnalysisBeginTime + WellDetectingUnconditionalSearchPeriod < CACurrentMediaTime()) {
                // Begin an async well finding analysis
                _lastWellAnalysisBeginTime = CACurrentMediaTime();
                _lastWellAnalyzedFrameAverageValues = currentAvg;
                
                [self performWellDeterminationCalculationAsyncWithFrame:videoFrame];
            }
        }
        
        // Create a copy of the frame to draw debugging info/live feedback on, which we will send back
        debugFrame = [videoFrame copy];
        
        // First, draw debugging well circles and labels on each frame so that they appear underneath other drawing
        if (_shouldScanForWells) {
            CvScalar circleColor = _processingState == ProcessingStateNoPlate ? CV_RGBA(255, 0, 0, 255) :
            (_processingState == ProcessingStatePlateFirstFrameIdentified ? CV_RGBA(255, 255, 0, 255) : CV_RGBA(0, 255, 0, 255));
            drawWellCirclesAndLabelsOnDebugImage(_processingState == ProcessingStateNoPlate ? _lastCircles : _trackingWellCircles,
                                                 circleColor,
                                                 _processingState == ProcessingStateTrackingMotion,
                                                 [debugFrame image]);
        }
        
        // If this processor detected a barcode, draw it on the debug image
        NSMutableString *barcodeAndOrTimeText = [NSMutableString string];
        if (_lastBarcodeThisProcessor && _lastBarcodeThisProcessorRepeatCount >= BarcodeRepeatSuccessCount) {
            [barcodeAndOrTimeText appendString:_lastBarcodeThisProcessor];
            [barcodeAndOrTimeText appendString:@" "];
        }
        // Print the tracked time on the debug image
        if (_processingState == ProcessingStateTrackingMotion) {
            unsigned elapsed = [videoFrame presentationTime] - [_plateData startPresentationTime];
            [barcodeAndOrTimeText appendFormat:@"%u:%02u", elapsed / 60, elapsed % 60];
        }
        if ([barcodeAndOrTimeText length] > 0) {
            CvFont font = fontForNormalizedScale(3.5, [debugFrame image]);
            CvPoint point = cvPoint(10, [debugFrame image]->height - 10);
            cvPutText([debugFrame image], [barcodeAndOrTimeText UTF8String], point, &font, CV_RGBA(232, 0, 217, 255));
        }
        
        // Analyze tracked images synchronously (at frame rate), so that we drop frames if we can't keep up.
        if (_processingState == ProcessingStateTrackingMotion && sizeEqualsSize(_trackedImageSize, cvGetSize([videoFrame image]))) {
            if ([_assayAnalyzer willBeginFrameProcessing:videoFrame debugImage:[debugFrame image] plateData:_plateData]) {
                // Make a block to parallelize
                void (^processWellBlock)(NSUInteger, id) = ^(NSUInteger i, id criticalSection){
                    // Make stack copies of the headers so that they can have their own ROI's, etc.
                    IplImage wellImage = *[videoFrame image];
                    IplImage debugImage = *[debugFrame image];
                    if (_trackingWellCircles.size() > 0) {
                        CvRect boundingSquare = boundingSquareForCircle(_trackingWellCircles[i]);
                        cvSetImageROI(&wellImage, boundingSquare);
                        cvSetImageROI(&debugImage, boundingSquare);
                    }
                    [_assayAnalyzer processVideoFrameWellSynchronously:&wellImage
                                                               forWell:_trackingWellCircles.size() > 0 ? (int)i : -1
                                                            debugImage:&debugImage
                                                      presentationTime:[videoFrame presentationTime]
                                                             plateData:_plateData];
                    cvResetImageROI(&wellImage);
                    cvResetImageROI(&debugImage);
                };
                
                // Previously, this was conditionalized to only parallelize well analysis if we had at least 4 physical
                // cores to be conservative, since doing so on a 2.1 ghz Core 2 Duo (with 2 virtual/physical cores) decreased
                // performance 50% due to contention with decoding threads, however, the minimum linked version of the
                // OS now means that all computers will meet this requirement, and libdispatch has also improved somewhat since then.
                size_t iterations = _trackingWellCircles.size() > 0 ? _trackingWellCircles.size() : 1;      // i.e. wells
                if ([_assayAnalyzer canProcessInParallel]) {
                    [NSOperationQueue addOperationsInParallelWithInstances:iterations onGlobalQueueForBlock:processWellBlock];
                } else {
                    for (size_t i = 0; i < iterations; i++) {
                        processWellBlock(i, nil);
                    }
                }
            }
            [_assayAnalyzer didEndFrameProcessing:videoFrame plateData:_plateData];
            
            // Print the results in the wells averaged over the last 30 seconds (to limit computational complexity)
            CvFont wellFont = fontForNormalizedScale(0.75, [debugFrame image]);
            size_t labels = _trackingWellCircles.size() > 0 ? _trackingWellCircles.size() : 1;
            for (size_t i = 0; i < labels; i++) {
                double mean, stddev;
                if ([_plateData movementUnitsMean:&mean stdDev:&stddev forWell:(int)i inLastSeconds:30]) {
                    char text[20];
                    if (_trackingWellCircles.size() <= 24) {        // Draw the SD if the wells are large enough
                        snprintf(text, sizeof(text), "%.0f (SD: %.0f)", mean, stddev);
                    } else {
                        snprintf(text, sizeof(text), "%.0f", mean);
                    }
                    
                    CvPoint textPoint;
                    if (_trackingWellCircles.size() > 0) {
                        float radius = _trackingWellCircles[i].radius;
                        textPoint = cvPoint(_trackingWellCircles[i].center[0] - radius * 0.5, _trackingWellCircles[i].center[1]);
                    } else {
                        CvSize frameSize = cvGetSize([videoFrame image]);
                        textPoint = cvPoint(frameSize.width / 2, frameSize.height / 2);
                    }
                    cvPutText([debugFrame image],
                              text,
                              textPoint,
                              &wellFont,
                              CV_RGBA(0, 255, 255, 255));
                }
            }
            
            // Print performance statistics. The mean/stddev are for just the processing time. The frame rate is the total net rate.
            double mean, stddev;
            if ([_plateData processingTimeMean:&mean stdDev:&stddev inLastFrames:15]) {
                char text[100];
                snprintf(text, sizeof(text), "%.0f ms/f (SD: %.0f ms), %.1f fps, %.0f%% drop",
                         mean * 1000, stddev * 1000, [_plateData averageFramesPerSecond], [_plateData droppedFrameProportion] * 100);
                CvFont font;
                cvInitFont(&font, CV_FONT_HERSHEY_DUPLEX, 0.6, 0.6, 0, 0.6);
                cvPutText([debugFrame image], text, cvPoint(0, 15), &font, CV_RGBA(232, 0, 217, 255));
            }
        }
        
        // Add the processing time
        if (_plateData) {
            [_plateData addProcessingTime:CACurrentMediaTime() - processingStartTime];
        }
    }
        
    // Dispatch the debug image callback block last
    callback(debugFrame);
}

// requires lock to be held
- (void)performWellDeterminationCalculationAsyncWithFrame:(VideoFrame *)videoFrame
{
    // If well finding is disabled, report success and bail
    bool wellFindingDisabled = _plateOrientation == PlateOrientationNoWells;
    
    _scanningForWells = YES;
    
    // Get instance variables while locked for thread-safety
    int wellCountHint = _wellCountHint;
    bool searchAllPlateSizes = _processingState == ProcessingStateNoPlate;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    [NSOperationQueue addOperationToGlobalQueueWithBlock:^{
        // Get wells in row major order
        std::vector<Circle> wellCircles;
        bool plateFound;
        if (wellFindingDisabled) {
            plateFound = YES;
        } else if (searchAllPlateSizes) {
            plateFound = findWellCircles([videoFrame image], wellCircles, wellCountHint);
        } else {
            plateFound = findWellCirclesForWellCount([videoFrame image], wellCountHint, wellCircles);
        }
        
        // Process and store the results while locked
        @synchronized (self) {
            _scanningForWells = NO;
            // If the device was removed, etc., ignore any detected plates
            if (_shouldScanForWells) {
                // Store the circles for debugging later
                _lastCircles = wellCircles;
                // If we've found a plate, store the well count to improve the performance of future searches
                if (plateFound) {
                    _wellCountHint = (int)wellCircles.size();
                }
                
                switch (_processingState) {
                    case ProcessingStateNoPlate:
                        if (plateFound) {
                            _processingState = ProcessingStatePlateFirstFrameIdentified;
                            _trackingWellCircles = wellCircles;     // store the first circles as the baseline for the second set
                            _firstWellFrameTime = [videoFrame presentationTime];
                        }
                        break;
                        
                    case ProcessingStatePlateFirstFrameIdentified:
                        if (plateFound) {
                            // If the second identification yields matching results as the first, and they are spread by at least
                            // 250 ms, begin motion tracking and video recording
                            if (plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles) &&
                                [videoFrame presentationTime] - _firstWellFrameTime >= MinimumWellMatchTimeToBeginTracking &&
                                [videoFrame presentationTime] > _lockoutStartFrameTime) {
                                _startOfTrackingFrameTime = [videoFrame presentationTime];
                                _processingState = ProcessingStateTrackingMotion;
                                _trackingWellCircles = wellCircles; // store the second set as the baseline for all remaining sets
                                _trackedImageSize = cvGetSize([videoFrame image]);
                                _lastBarcodeScanTime = PresentationTimeDistantPast;     // Now that plate is in place, immediately retry barcode capture
                                
                                // Notify the delegate
                                [_delegate videoProcessor:self didBeginTrackingPlateAtPresentationTime:[videoFrame presentationTime]];
                                
                                // Create plate data and analyzer
                                if (_trackingWellCircles.size () > 0) {
                                    RunLog(@"Began tracking %li well plate using %@ analyzer.", _trackingWellCircles.size(), [_assayAnalyzerClass analyzerName]);
                                } else {
                                    RunLog(@"Began tracking entire plate using %@ analyzer.", [_assayAnalyzerClass analyzerName]);
                                }
                                NSAssert(!_plateData && !_assayAnalyzer, @"plate data or motion analyzer already exists");
                                _plateData = [[PlateData alloc] initWithWellCount:wellCircles.size() startPresentationTime:[videoFrame presentationTime]];
                                _assayAnalyzer = [[_assayAnalyzerClass alloc] init];
                                NSAssert1(_assayAnalyzer, @"failed to allocate AssayAnalyzer %@", _assayAnalyzerClass);
                                [_assayAnalyzer willBeginPlateTrackingWithPlateData:_plateData];
                                
                                // Start recording if we have a session to record from (e.g. this is a device source)
                                _fileOutputURL = nil;
                                if (_fileOutputDelegate) {
                                    _fileOutputURL = [_delegate outputFileURLForVideoProcessor:self];
                                    [_fileOutputDelegate videoProcessor:self shouldBeginRecordingToURL:_fileOutputURL withNaturalOrientation:_plateOrientation];
                                }
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
                        
                    case ProcessingStateTrackingMotion: {
                        // Get values for the optional time lapse feature
                        NSTimeInterval trackingLimit, lockoutTime;
                        BOOL timeLapseEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:TimeLapseAnalyzeEnabled];
                        if (timeLapseEnabled) {
                            trackingLimit = [[NSUserDefaults standardUserDefaults] doubleForKey:TimeLapseAnalyzeDuration];
                            // Set sensible defaults
                            if (trackingLimit <= 0.0) {
                                trackingLimit = TimeLapseAnalyzeDurationDefault;
                            }
                            lockoutTime = [[NSUserDefaults standardUserDefaults] doubleForKey:TimeLapseLockoutInterval];
                            if (lockoutTime <= 0.0) {
                                lockoutTime = TimeLapseLockoutIntervalDefault;
                            }
                        }
                        
                        // Since we've seen a plate in one camera, ignore any pending results from others.
                        // But if the plate is gone, moved or different, reset
                        if (!plateFound || !plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles)) {
                            [self resetCaptureStateAndReportResults];
                        } else if (timeLapseEnabled && [videoFrame presentationTime] > _startOfTrackingFrameTime + trackingLimit) {
                            // We've hit the tracking limit, so stop capturing and wait until we aren't locked out
                            [self resetCaptureStateAndReportResults];       // clears _lockoutStartFrameTime
                            _lockoutStartFrameTime = [videoFrame presentationTime] + lockoutTime;
                            RunLog(@"Pausing capture for %u:%02g for time lapse recording.", (unsigned)lockoutTime / 60, fmod(lockoutTime, 60.0));
                        }
                    }
                }
            }
        };
    }];
}

- (void)performBarcodeReadingSynchronouslyWithFrame:(VideoFrame *)videoFrame
{
    CGImageRef cgImage = [videoFrame createCGImage];
    
    // Create the request
    VNDetectBarcodesRequest *request = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:NULL];
    NSArray *requestArray = @[ request ];
    VNSequenceRequestHandler *handler = [[VNSequenceRequestHandler alloc] init];
    
    // (These are the pure rotations. We don't need to flip since the image is coming straight from a camera and is a barcode label.)
    CGImagePropertyOrientation orientations[] = {
        kCGImagePropertyOrientationUp,
        kCGImagePropertyOrientationDown,
        kCGImagePropertyOrientationRight,
        kCGImagePropertyOrientationLeft
    };
    // Perform the request in all orientations since the barcode may not match the reading orientation and use the highest confidence result.
    VNBarcodeObservation *bestObservation = nil;
    for (NSUInteger i = 0; i < sizeof(orientations) / sizeof(*orientations); i++) {
        NSError *error = nil;
        if (![handler performRequests:requestArray onCGImage:cgImage orientation:orientations[i] error:&error]) {
            RunLog(@"Error creating barcode reading request: %@ (orientation %u)", error, orientations[i]);
        }
        for (VNBarcodeObservation *observation in [request results]) {
            NSAssert([observation isKindOfClass:[VNBarcodeObservation class]], @"unexpected return observation type: %@", observation);
            // Use the highest confidence barcode over all orientations. There will be many reads of even the same code
            // (though almost always the same final result but different bounding rects etc. of no importance to us.)
            if (!bestObservation || [observation confidence] > [bestObservation confidence]) {
                bestObservation = observation;
            }
        }
    }
    CGImageRelease(cgImage);
    
    NSString *barcodeString = [bestObservation payloadStringValue];     // may be nil if no result or non-string barcode
    // Process and store the results unconditionally (since we need to mark barcode reading completed to try again)
    @synchronized (self) {
        [self barcodeReadingCompletedWithFrame:videoFrame resultString:barcodeString];
    };
}

// must be called at the end of a barcode analysis whether or not a string was found; requires lock to be held
- (void)barcodeReadingCompletedWithFrame:(VideoFrame *)videoFrame resultString:(NSString *)barcodeString
{
    _scanningForBarcodes = NO;
    _lastBarcodeScanTime = [videoFrame presentationTime];
    _lastBarcodeThisProcessor = barcodeString;
    
    if (barcodeString && _lastBarcodeThisProcessor && [barcodeString isEqual:_lastBarcodeThisProcessor]) {
        _lastBarcodeThisProcessorRepeatCount++;
    } else if (barcodeString) {
        _lastBarcodeThisProcessorRepeatCount = 1;
    } else {
        _lastBarcodeThisProcessorRepeatCount = 0;
    }
    
    if (barcodeString && _lastBarcodeThisProcessorRepeatCount >= BarcodeRepeatSuccessCount) {
        [_delegate videoProcessor:self didCaptureBarcodeText:barcodeString atTime:[videoFrame presentationTime]];
    }
}

- (void)resetCaptureStateAndReportResults       // requires lock to be held
{
    [_assayAnalyzer didEndTrackingPlateWithPlateData:_plateData];
    
    // Send the stats and video file information to the video controller
    if (_plateData) {
        NSTimeInterval trackingDuration = [_plateData lastPresentationTime] - [_plateData startPresentationTime];
        BOOL longEnough = trackingDuration >= [_assayAnalyzer minimumTimeIntervalProcessedToReportData] &&
                            [_plateData sampleCount] > [_assayAnalyzer minimumSamplesProcessedToReportData];
        if (longEnough) {
            RunLog(@"Ended tracking after %.3f seconds (%.1f fps)", trackingDuration, [_plateData averageFramesPerSecond]);
        } else {
            RunLog(@"Ignoring truncated run of %.3f seconds", trackingDuration);
        }
        
        // Notify the two delegates in a delayed fashion to avoid re-entry, and without using instance variables
        // since they can change, and instead snapshot with local variables
        PlateData *plateData = _plateData;
        NSURL *fileOutputURL = _fileOutputURL;   // esp. since two in flight encodings could overlap e.g. during a short recording after a long one
        
        [NSOperationQueue addOperationToGlobalQueueWithBlock:^{
            [_delegate videoProcessor:self
          didFinishAcquiringPlateData:plateData
                         successfully:longEnough
     willStopRecordingToOutputFileURL:fileOutputURL];
            
            [_fileOutputDelegate videoProcessorShouldStopRecording:self completion:^(NSError *error) {
                [_delegate videoProcessorDidFinishRecordingToFileURL:fileOutputURL error:error];
            }];
        }];
        
        // Release the plate data and output URL
        _plateData = nil;
        _fileOutputURL = nil;
        
        // Clear the analyzer
        _assayAnalyzer = nil;
    }
    NSAssert(!_assayAnalyzer && !_plateData, @"inconsistent state");
    
    // Reset state
    _processingState = ProcessingStateNoPlate;
    _firstWellFrameTime = PresentationTimeDistantPast;
    _startOfTrackingFrameTime = PresentationTimeDistantPast;
    _lockoutStartFrameTime = PresentationTimeDistantPast;
    _lastBarcodeScanTime = PresentationTimeDistantPast;
    _lastWellAnalysisBeginTime = PresentationTimeDistantPast;
    _trackingWellCircles.clear();
    _trackedImageSize = cvSize(0, 0);
}

- (void)reportFinalResultsBeforeRemoval
{
    @synchronized (self) {
        [self resetCaptureStateAndReportResults];
        [self setShouldScanForWells:NO];
    };
}

- (void)manuallyReportResultsAndReset
{
    @synchronized (self) {
        [self resetCaptureStateAndReportResults];
    };
}

- (void)noteVideoFrameWasDropped
{
    @synchronized (self) {
        if (_plateData) {
            [_plateData incrementFrameDropCount];
        }
    };
}

@end
