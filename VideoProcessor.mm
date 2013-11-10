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
#import "VideoProcessorController.h"   // for RunLog()
#import "zxing/common/GreyscaleLuminanceSource.h"
#import "zxing/MultiFormatReader.h"
#import "zxing/BarcodeFormat.h"
#import "zxing/DecodeHints.h"
#import "zxing/common/HybridBinarizer.h"
#import "zxing/ReaderException.h"
#import <sys/sysctl.h>

static const NSTimeInterval MinimumWellMatchTimeToBeginTracking = 0.500; // 500 ms
static const NSTimeInterval BarcodeScanningPeriod = 0.5;
static const NSTimeInterval BarcodeRepeatSuccessCount = 3;
static const NSTimeInterval PresentationTimeDistantPast = -DBL_MAX;
static const double WellDetectingAverageDeltaEndIdleThreshold = 5.0;
static const NSTimeInterval WellDetectingUnconditionalSearchPeriod = 10.0;

static int numberOfPhysicalCPUS();

// Here for C++ build safety
@interface VideoProcessor() {
    __weak id<VideoProcessorDelegate> _delegate;                        // not retained
    __weak id<VideoProcessorRecordingDelegate> _fileOutputDelegate;    // not retained
    NSString *_fileSourceDisplayName;
    Class _assayAnalyzerClass;
    PlateOrientation _plateOrientation;
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
    NSURL *_fileOutputURL;
    
    BOOL _shouldScanForWells;
    BOOL _scanningForWells;
    BOOL _scanningForBarcodes;
    
    ProcessingState _processingState;
    int _wellCountHint;
    CvScalar _lastWellAnalyzedFrameAverageValues;
    NSTimeInterval _firstWellFrameTime;     // not the begining of tracking
    NSTimeInterval _lastBarcodeScanTime;
    NSTimeInterval _lastWellAnalysisBeginTime;  // the last time a well finding analysis was started. used to do idling when no plates present.
    
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
        _queue = dispatch_queue_create("video-processor", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("video-processor-callback", NULL);
        _lastWellAnalysisBeginTime = PresentationTimeDistantPast;
    }
    return self;
}

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate
{
    dispatch_async(_queue, ^{
        _delegate = delegate;       // not retained
    });
}

- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass
{
    dispatch_async(_queue, ^{
        if (_assayAnalyzerClass != assayAnalyzerClass) {
            _assayAnalyzerClass = assayAnalyzerClass;
            [self resetCaptureStateAndReportResults];
        }
    });
}

- (void)setPlateOrientation:(PlateOrientation)plateOrientation
{
    dispatch_async(_queue, ^{
        if (_plateOrientation != plateOrientation) {
            _plateOrientation = plateOrientation;
            [self resetCaptureStateAndReportResults];
        }
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

- (void)processVideoFrame:(VideoFrame *)videoFrame debugFrameCallback:(void (^)(VideoFrame *image))callback
{
    NSTimeInterval processingStartTime = CACurrentMediaTime();
    
    // This method is synchronous so that we don't enqueue frames faster than they should be processed. The document will drop the overflow.
    dispatch_sync(_queue, ^{
        if (_plateData) {
            [_plateData incrementReceivedFrameCount];
        }
        
        // Always look for barcodes since another camera might have a plate.
        // Do this before flipping so we aren't flipping any barcodes. 
        if (!_scanningForBarcodes && _lastBarcodeScanTime < [videoFrame presentationTime] - BarcodeScanningPeriod) {
            VideoFrame *copy = [videoFrame copy];
            [self performBarcodeReadingAsyncWithFrame:copy];
        }
        
        // Rotate image if necessary
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
            
            // Always scan if we are not idle, and scan if the average values change signifigantly or if we haven't scanned in a while
            if (_processingState != ProcessingStateNoPlate ||
                averageDelta > WellDetectingAverageDeltaEndIdleThreshold ||
                _lastWellAnalysisBeginTime + WellDetectingUnconditionalSearchPeriod < CACurrentMediaTime()) {
                // Begin an async well finding analysis
                _lastWellAnalysisBeginTime = CACurrentMediaTime();
                _lastWellAnalyzedFrameAverageValues = currentAvg;
                
                VideoFrame *copy = [videoFrame copy];
                [self performWellDeterminationCalculationAsyncWithFrame:copy];
            }
        }
        
        // Create a copy of the frame to draw debugging info on, which we will send back
        VideoFrame *debugFrame = [videoFrame copy];
        
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
                void (^processWellBlock)(size_t) = ^(size_t i){
                    // Make stack copies of the headers so that they can have their own ROI's, etc.
                    IplImage wellImage = *[videoFrame image];
                    IplImage debugImage = *[debugFrame image];
                    if (_trackingWellCircles.size() > 0) {
                        CvRect boundingSquare = boundingSquareForCircle(_trackingWellCircles[i]);
                        cvSetImageROI(&wellImage, boundingSquare);
                        cvSetImageROI(&debugImage, boundingSquare);
                    }
                    [_assayAnalyzer processVideoFrameWellSynchronously:&wellImage
                                                               forWell:_trackingWellCircles.size() > 0 ? i : -1
                                                            debugImage:&debugImage
                                                      presentationTime:[videoFrame presentationTime]
                                                             plateData:_plateData];
                    cvResetImageROI(&wellImage);
                    cvResetImageROI(&debugImage);
                };
                
                // Only parallelize well analysis if we have at least 4 (physical) cores to be conservative, since doing so on
                // a 2.1 ghz Core 2 Duo (with 2 virtual/physical cores) decreased performance 50% due to contention with decoding threads.
                size_t iterations = _trackingWellCircles.size() > 0 ? _trackingWellCircles.size() : 1;      // i.e. wells
                if ([_assayAnalyzer canProcessInParallel] && numberOfPhysicalCPUS() >= 4) {
                    dispatch_apply(iterations, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), processWellBlock);
                } else {
                    for (size_t i = 0; i < iterations; i++) {
                        processWellBlock(i);
                    }
                }
            }
            [_assayAnalyzer didEndFrameProcessing:videoFrame plateData:_plateData];
            
            // Print the results in the wells averaged over the last 30 seconds (to limit computational complexity)
            CvFont wellFont = fontForNormalizedScale(0.75, [debugFrame image]);
            size_t labels = _trackingWellCircles.size() > 0 ? _trackingWellCircles.size() : 1;
            for (size_t i = 0; i < labels; i++) {
                double mean, stddev;
                if ([_plateData movementUnitsMean:&mean stdDev:&stddev forWell:i inLastSeconds:30]) {
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
            
            // Print performance statistics. The mean/stddev are for just the procesing time. The frame rate is the total net rate.
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
                
        // Dispatch the debug image asynchronously to increase parallelism 
        dispatch_async(_debugFrameCallbackQueue, ^{
            @autoreleasepool {
                callback(debugFrame);
            }
        });
        
        // Add the processing time last
        if (_plateData) {
            [_plateData addProcessingTime:CACurrentMediaTime() - processingStartTime];
        }
    });
}

// requires _queue to be held
- (void)performWellDeterminationCalculationAsyncWithFrame:(VideoFrame *)videoFrame
{
    // If well finding is disabled, report success and bail
    bool wellFindingDisabled = _plateOrientation == PlateOrientationNoWells;
    
    _scanningForWells = YES;
    
    // Get instance variables while holding _queue for thread-safety
    int wellCountHint = _wellCountHint;
    bool searchAllPlateSizes = _processingState == ProcessingStateNoPlate;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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
                            _firstWellFrameTime = [videoFrame presentationTime];
                        }
                        break;
                        
                    case ProcessingStatePlateFirstFrameIdentified:
                        if (plateFound) {
                            // If the second identification yields matching results as the first, and they are spread by at least
                            // 250 ms, begin motion tracking and video recording
                            if (plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles) &&
                                [videoFrame presentationTime] - _firstWellFrameTime >= MinimumWellMatchTimeToBeginTracking) {
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
                                    [_fileOutputDelegate videoProcessor:self shouldBeginRecordingToURL:_fileOutputURL];
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
- (void)performBarcodeReadingAsyncWithFrame:(VideoFrame *)videoFrame
{
    _scanningForBarcodes = YES;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Convert the image to grayscale
        IplImage *grayscaleImage = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 1);
        NSAssert(grayscaleImage->widthStep == grayscaleImage->width * grayscaleImage->nChannels, @"image not byte packed");
        cvCvtColor([videoFrame image], grayscaleImage, CV_BGRA2GRAY);
        zxing::ArrayRef<char> arrayRefData((char *)grayscaleImage->imageData, grayscaleImage->imageSize);
        zxing::Ref<zxing::GreyscaleLuminanceSource> luminanceSource(new zxing::GreyscaleLuminanceSource(arrayRefData,
                                                                                                        grayscaleImage->widthStep,
                                                                                                        grayscaleImage->height,
                                                                                                        0,
                                                                                                        0,
                                                                                                        grayscaleImage->width,
                                                                                                        grayscaleImage->height));
        
        NSString *text = nil;
        // Binarize the image
        try {
            zxing::Ref<zxing::Binarizer> binarizer(new zxing::HybridBinarizer(luminanceSource));
            zxing::Ref<zxing::BinaryBitmap> binaryBitmap(new zxing::BinaryBitmap(binarizer));
            
            // Search for barcodes
            zxing::Ref<zxing::MultiFormatReader> reader(new zxing::MultiFormatReader());
            zxing::DecodeHints hints;
            hints.addFormat(zxing::BarcodeFormat::QR_CODE);
            hints.addFormat(zxing::BarcodeFormat::DATA_MATRIX);
            hints.addFormat(zxing::BarcodeFormat::CODE_128);
            hints.addFormat(zxing::BarcodeFormat::CODE_39);
            hints.setTryHarder(true);           // rotate images in search of barcodes, etc.
            
            zxing::Ref<zxing::Result> barcodeResult = reader->decode(binaryBitmap, hints);
            text = [NSString stringWithUTF8String:barcodeResult->getText()->getText().c_str()];
        } catch (...) {
            // No barcode found or error binarizing image
        }
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            _scanningForBarcodes = NO;
            _lastBarcodeScanTime = [videoFrame presentationTime];
            _lastBarcodeThisProcessor = text;
            
            if (text && _lastBarcodeThisProcessor && [text isEqual:_lastBarcodeThisProcessor]) {
                _lastBarcodeThisProcessorRepeatCount++;
            } else if (text) {
                _lastBarcodeThisProcessorRepeatCount = 1;
            } else {
                _lastBarcodeThisProcessorRepeatCount = 0;
            }
            
            if (text && _lastBarcodeThisProcessorRepeatCount >= BarcodeRepeatSuccessCount) {
                [_delegate videoProcessor:self didCaptureBarcodeText:text atTime:[videoFrame presentationTime]];
            }
        });
        
        cvReleaseImage(&grayscaleImage);
    });
}

// requires _queue to be held
- (void)resetCaptureStateAndReportResults
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
        
        // Notify the two delegates
        [_delegate videoProcessor:self didFinishAcquiringPlateData:_plateData successfully:longEnough willStopRecordingToOutputFileURL:_fileOutputURL];
        [_fileOutputDelegate videoProcessorShouldStopRecording:self completion:^(NSError *error) {
            dispatch_async(_queue, ^{
                [_delegate videoProcessorDidFinishRecordingToFileURL:_fileOutputURL error:error];
                _fileOutputURL = nil;
            });
        }];
    
        // Release the analyzer
        _assayAnalyzer = nil;
    
        // Release the plate data
        _plateData = nil;
    }
    NSAssert(!_assayAnalyzer && !_plateData, @"inconsistent state");
    
    // Reset state
    _processingState = ProcessingStateNoPlate;
    _firstWellFrameTime = PresentationTimeDistantPast;
    _lastBarcodeScanTime = PresentationTimeDistantPast;
    _lastWellAnalysisBeginTime = PresentationTimeDistantPast;
    _trackingWellCircles.clear();
    _trackedImageSize = cvSize(0, 0);
}

- (void)reportFinalResultsBeforeRemoval
{
    dispatch_async(_queue, ^{
        [self resetCaptureStateAndReportResults];
        [self setShouldScanForWells:NO];
    });
}

- (void)manuallyReportResultsAndReset
{
    dispatch_async(_queue, ^{
        [self resetCaptureStateAndReportResults];
    });
}

- (void)noteVideoFrameWasDropped
{
    dispatch_async(_queue, ^{
        if (_plateData) {
            [_plateData incrementFrameDropCount];
        }
    });
}

@end

static int numberOfPhysicalCPUS()
{
    int physicalCPUS = 0;
    size_t length = sizeof(physicalCPUS);
    sysctlbyname("hw.physicalcpu", &physicalCPUS, &length , NULL, 0);
    NSCAssert(physicalCPUS > 0, @"unable to get CPU count");
    return physicalCPUS;
}