//
//  VideoProcessor.m
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
#import "zxing/DecodeHints.h"
#import "zxing/common/HybridBinarizer.h"
#import "zxing/ReaderException.h"

static const NSTimeInterval MinimumWellMatchTimeToBeginTracking = 0.250; // 250 ms
static const NSTimeInterval BarcodeScanningPeriod = 1.0;
static const NSTimeInterval BarcodeRepeatSuccessCount = 3;
static const NSTimeInterval PresentationTimeDistantPast = -DBL_MAX;

@interface VideoProcessor() {
    NSString *_sourceIdentifier;
    id<VideoProcessorDelegate> _delegate;        // not retained
    Class _assayAnalyzerClass;
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
    
    BOOL _shouldScanForWells;
    BOOL _scanningForWells;
    BOOL _scanningForBarcodes;
    
    ProcessingState _processingState;
    int _wellCountHint;
    NSTimeInterval _firstWellFrameTime;
    NSTimeInterval _lastBarcodeScanTime;
    
    id<AssayAnalyzer> _assayAnalyzer;
    PlateData *_plateData;
    std::vector<Circle> _trackingWellCircles;    // circles used for tracking
    CvSize _trackedImageSize;
    std::vector<Circle> _lastCircles;       // the last circles returned by the well finder (not necessarily same as tracking)
    
    NSString *_lastBarcodeThisProcessor;
    NSUInteger _lastBarcodeThisProcessorRepeatCount;
}

- (void)performWellDeterminationCalculationAsyncWithFrame:(VideoFrame *)videoFrame;
- (void)performBarcodeReadingAsyncWithFrame:(VideoFrame *)videoFrame;

- (void)resetCaptureStateAndReportResults;
- (void)beginRecordingVideo;

@end


@implementation VideoProcessor

- (id)initWithSourceIdentifier:(NSString *)sourceIdentifier
{
    if ((self = [super init])) {
        _sourceIdentifier = [sourceIdentifier copy];
        _queue = dispatch_queue_create("videoprocessor", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("videoprocessor.callback", NULL);
    }
    return self;
}

- (void)dealloc
{
    [_sourceIdentifier release];
    dispatch_release(_queue);
    dispatch_release(_debugFrameCallbackQueue);
    [_plateData release];
    [_assayAnalyzer release];
    [_lastBarcodeThisProcessor release];
    [super dealloc];
}

- (void)setDelegate:(id<VideoProcessorDelegate>)delegate
{
    dispatch_sync(_queue, ^{
        _delegate = delegate;       // not retained
    });
}

- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass
{
    dispatch_sync(_queue, ^{
        _assayAnalyzerClass = assayAnalyzerClass;
        [self resetCaptureStateAndReportResults];
    });
}

- (void)setShouldScanForWells:(BOOL)shouldScanForWells
{
    dispatch_sync(_queue, ^{
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
    
    // This method is synchronous so that we don't enqueue frames faster than they should be processed. QT will drop the overflow.
    dispatch_sync(_queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        if (_plateData) {
            [_plateData incrementReceivedFrameCount];
        }
        
        // If we're not already searching for wells, and no other processor has a plate, schedule an async processing
        if (!_scanningForWells && _shouldScanForWells) {
            VideoFrame *copy = [videoFrame copy];
            [self performWellDeterminationCalculationAsyncWithFrame:copy];
            [copy release];
        }
        
        // Always look for barcodes since another camera might have a plate
        BOOL repeatBarcodeScanImmediately = _lastBarcodeThisProcessorRepeatCount > 0 && _lastBarcodeThisProcessorRepeatCount < BarcodeRepeatSuccessCount;
        if (!_scanningForBarcodes && (_lastBarcodeScanTime < [videoFrame presentationTime] - BarcodeScanningPeriod || repeatBarcodeScanImmediately)) {
            VideoFrame *copy = [videoFrame copy];
            [self performBarcodeReadingAsyncWithFrame:copy];
            [copy release];
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
        if (_lastBarcodeThisProcessor && _lastBarcodeThisProcessorRepeatCount >= BarcodeRepeatSuccessCount) {
            // Draw the movement text
            CvFont font = fontForNormalizedScale(3.5, [debugFrame image]);
            CvPoint point = cvPoint(10, [debugFrame image]->height - 10);
            cvPutText([debugFrame image], [_lastBarcodeThisProcessor UTF8String], point, &font, CV_RGBA(232, 0, 217, 255));
        }
        
        // Analyze tracked images synchronously (at frame rate), so that we drop frames if we can't keep up.
        if (_processingState == ProcessingStateTrackingMotion && sizeEqualsSize(_trackedImageSize, cvGetSize([videoFrame image]))) {
            if ([_assayAnalyzer willBeginFrameProcessing:videoFrame debugImage:[debugFrame image] plateData:_plateData]) {
                void (^processWellBlock)(size_t) = ^(size_t i){
                    // Make stack copies of the headers so that they can have their own ROI's, etc.
                    CvRect boundingSquare = boundingSquareForCircle(_trackingWellCircles[i]);
                    IplImage wellImage = *[videoFrame image];
                    cvSetImageROI(&wellImage, boundingSquare);
                    IplImage debugImage = *[debugFrame image];
                    cvSetImageROI(&debugImage, boundingSquare);
                    [_assayAnalyzer processVideoFrameWellSynchronously:&wellImage
                                                               forWell:i
                                                            debugImage:&debugImage
                                                      presentationTime:[videoFrame presentationTime]
                                                             plateData:_plateData];
                };
                
                // Only parallelize well analysis if we have at least 4 (virtual) cores to be conservative, since doing so on
                // a 2.1 ghz Core 2 Duo (with 2 virtual and physical cores) decreased performance 50% due to contention with decoding threads.
                if ([_assayAnalyzer canProcessInParallel] && [[NSProcessInfo processInfo] activeProcessorCount] >= 4) {
                    dispatch_apply(_trackingWellCircles.size(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), processWellBlock);
                } else {
                    for (size_t i = 0; i < _trackingWellCircles.size(); i++) {
                        processWellBlock(i);
                    }
                }
            }
            [_assayAnalyzer didEndFrameProcessing:videoFrame plateData:_plateData];
            
            // Print the stats in the wells averaged over the last 30 seconds (to limit computational complexity)
            CvFont wellFont = fontForNormalizedScale(0.75, [debugFrame image]);
            for (size_t i = 0; i < _trackingWellCircles.size(); i++) {
                double mean, stddev;
                if ([_plateData movementUnitsMean:&mean stdDev:&stddev forWell:i inLastSeconds:30]) {
                    char text[20];
                    snprintf(text, sizeof(text), "%.0f (SD: %.0f)", mean * 1000, stddev * 1000);
                    
                    float radius = _trackingWellCircles[i].radius;
                    CvPoint textPoint = cvPoint(_trackingWellCircles[i].center[0] - radius * 0.5, _trackingWellCircles[i].center[1]);
                    cvPutText([debugFrame image],
                              text,
                              textPoint,
                              &wellFont,
                              CV_RGBA(0, 255, 255, 255));
                }
            }
            
            // Print performance statistics. The mean/stddev are for just the procesing time. The frame rate is the total net rate.
            double mean, stddev;
            if ([_plateData processingTimeMean:&mean stdDev:&stddev inLastFrames:100]) {
                double fps = (double)[_plateData receivedFrameCount] / ([_plateData lastPresentationTime] - [_plateData startPresentationTime]);
                double drop = (double)[_plateData frameDropCount] / ([_plateData receivedFrameCount] + [_plateData frameDropCount]);
                
                char text[100];
                snprintf(text, sizeof(text), "%.0f ms/f (SD: %.0f ms), %.1f fps, %.0f%% drop", mean * 1000, stddev * 1000, fps, drop * 100);
                CvFont font;
                cvInitFont(&font, CV_FONT_HERSHEY_DUPLEX, 0.6, 0.6, 0, 0.6);
                cvPutText([debugFrame image], text, cvPoint(0, 15), &font, CV_RGBA(232, 0, 217, 255));
            }
        }
                
        // Dispatch the debug image asynchronously to increase parallelism 
        dispatch_async(_debugFrameCallbackQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            callback(debugFrame);
            [pool release];
        });
        [debugFrame release];
        
        // Add the processing time last
        if (_plateData) {
            [_plateData addProcessingTime:CACurrentMediaTime() - processingStartTime];
        }
        
        [pool release];
    });
}

// requires _queue to be held
- (void)performWellDeterminationCalculationAsyncWithFrame:(VideoFrame *)videoFrame
{
    _scanningForWells = YES;
    
    // Get instance variables while holding _queue for thread-safety
    int wellCountHint = _wellCountHint;
    bool searchAllPlateSizes = _processingState == ProcessingStateNoPlate;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{        
        // Get wells in row major order
        std::vector<Circle> wellCircles;
        bool plateFound;
        if (searchAllPlateSizes) {
            plateFound = findWellCircles([videoFrame image], wellCircles, wellCountHint);
        } else {
            plateFound = findWellCirclesForWellCount([videoFrame image], wellCountHint, wellCircles);
        }
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
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
                                
                                // Create plate data and analyzer
                                RunLog(@"Began tracking %i well plate using %@ analyzer.", _trackingWellCircles.size(), [_assayAnalyzerClass analyzerName]);
                                NSAssert(!_plateData && !_assayAnalyzer, @"plate data or motion analyzer already exists");
                                _plateData = [[PlateData alloc] initWithWellCount:wellCircles.size() startPresentationTime:[videoFrame presentationTime]];
                                _assayAnalyzer = [[_assayAnalyzerClass alloc] init];
                                NSAssert1(_assayAnalyzer, @"failed to allocate AssayAnalyzer %@", _assayAnalyzerClass);
                                [_assayAnalyzer willBeginPlateTrackingWithPlateData:_plateData];
                                // Begin recording video
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
            [pool release];
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
        cvCvtColor([videoFrame image], grayscaleImage, CV_BGRA2GRAY);
        zxing::Ref<zxing::GreyscaleLuminanceSource> luminanceSource (new zxing::GreyscaleLuminanceSource((unsigned char *)grayscaleImage->imageData,
                                                                                                         grayscaleImage->widthStep,
                                                                                                         grayscaleImage->height,
                                                                                                         0,
                                                                                                         0,
                                                                                                         grayscaleImage->width,
                                                                                                         grayscaleImage->height));
        
        // Binarize the image
        zxing::Ref<zxing::Binarizer> binarizer(new zxing::HybridBinarizer(luminanceSource));
        zxing::Ref<zxing::BinaryBitmap> binaryBitmap (new zxing::BinaryBitmap(binarizer));
        
        // Search for barcodes
        zxing::Ref<zxing::MultiFormatReader> reader(new zxing::MultiFormatReader());
        zxing::DecodeHints hints;
        hints.setTryHarder(true);           // rotates images in all directions in search of barcodes, etc.
        NSString *text;
        try {
            zxing::Ref<zxing::Result> barcodeResult = reader->decode(binaryBitmap, hints);
            text = [[NSString alloc] initWithUTF8String:barcodeResult->getText()->getText().c_str()];
        } catch (zxing::ReaderException &e) {
            // No barcode found
            text = nil;
        }
        
        // Process and store the results when holding _queue
        dispatch_async(_queue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            _scanningForBarcodes = NO;
            _lastBarcodeScanTime = [videoFrame presentationTime];
            [_lastBarcodeThisProcessor release];
            _lastBarcodeThisProcessor = [text retain];
            
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
            [pool release];
        });
        
        [text release];
        cvReleaseImage(&grayscaleImage);
    });
}

// requires _queue to be held
- (void)resetCaptureStateAndReportResults
{
    [_assayAnalyzer didEndTrackingPlateWithPlateData:_plateData];
    [_assayAnalyzer release];
    _assayAnalyzer = nil;
    
    // Send the stats unconditionally and let the controller sort it out
    if (_plateData) {
        RunLog(@"Ended tracking after zyx");
        [_delegate videoProcessor:self didFinishAcquiringPlateData:_plateData];
        // SAVE AND NAME VIDEO XXX DONT DEADLOCK WHEN GETTING RESULT NAME  (INSTEAD PASS TEMP FILE NAME TO VIDEO PROCESSOR
        //[self endRecordingVideoWithName];
        // ELSE IF TOO SHORT DELETE THE VIDEO
    }
    
    _processingState = ProcessingStateNoPlate;
    [_plateData release];
    _plateData = nil;
    
    _firstWellFrameTime = PresentationTimeDistantPast;
    _lastBarcodeScanTime = PresentationTimeDistantPast;
    _trackingWellCircles.clear();
    _trackedImageSize = cvSize(0, 0);
}

- (void)beginRecordingVideo
{
    
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
