//
//  VideoProcessor.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoProcessor.h"
#import "ImageProcessing.hpp"
#import "IplImageObject.h"
#import "PlateData.h"
#import "zxing/common/GreyscaleLuminanceSource.h"
#import "zxing/MultiFormatReader.h"
#import "zxing/DecodeHints.h"
#import "zxing/common/HybridBinarizer.h"
#import "zxing/ReaderException.h"

static const NSTimeInterval BarcodeScanningPeriod = 1.0;
static const NSTimeInterval PresentationTimeDistantPast = -DBL_MAX;

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
    int _wellRadiusHint;
    NSTimeInterval _firstWellFrameTime;
    NSTimeInterval _lastBarcodeScanTime;
    
    PlateData *_plateData;
    IplImageObject *_lastFrame;     // when tracking
    std::vector<Circle> _trackingWellCircles;    // circles used for tracking
    std::vector<Circle> _lastCircles;   // for debugging
    NSString *_lastBarcodeThisProcessor;
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
        _queue = dispatch_queue_create("edu.ucsf.chrismarcellino.wormassay.videoprocessor", NULL);
        _debugFrameCallbackQueue = dispatch_queue_create("edu.ucsf.chrismarcellino.wormassay.callback", NULL);
        _processingState = ProcessingStateNoPlate;
    }
    return self;
}

- (void)dealloc
{
    [_sourceIdentifier release];
    dispatch_release(_queue);
    dispatch_release(_debugFrameCallbackQueue);
    [_plateData release];
    [_lastFrame release];
    [_lastBarcodeThisProcessor release];
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
        if (_plateData) {
            [_plateData incrementTotalFrameCount];
        }
        
        // If we're not already processing an image for wells, and no other processor has a plate, schedule an async processing
        if (!_scanningForWells && _shouldScanForWells) {
            [self performWellDeterminationCalculationAsyncWithFrame:videoFrame presentationTime:presentationTime];
        }
        
        // Always look for barcodes since another camera might have a plate
        if (!_scanningForBarcodes && _lastBarcodeScanTime < presentationTime - BarcodeScanningPeriod) {
            [self performBarcodeReadingAsyncWithFrame:videoFrame presentationTime:presentationTime];
        }
        
        // Create a copy of the frame to draw debugging info on, which we will send back
        IplImageObject *debugImage = [videoFrame copy];
        
        // First, draw debugging well circles and labels on each frame so that they appear underneath other drawing
        if (_shouldScanForWells) {
            CvScalar circleColor = _processingState == ProcessingStateNoPlate ? CV_RGBA(255, 0, 0, 255) :
            (_processingState == ProcessingStatePlateFirstFrameIdentified ? CV_RGBA(255, 255, 0, 255) : CV_RGBA(0, 255, 0, 255));
            drawWellCirclesAndLabelsOnDebugImage(_processingState == ProcessingStateNoPlate ? _lastCircles : _trackingWellCircles,
                                                 circleColor,
                                                 _processingState == ProcessingStateTrackingMotion,
                                                 [debugImage image]);
        }
        
        // If this processor detected a barcode, draw it on the debug image
        if (_lastBarcodeThisProcessor) {
            // Draw the movement text
            CvFont wellFont = fontForNormalizedScale(3.5, [debugImage image]);
            CvPoint point = cvPoint(10, [debugImage image]->height - 10);
            cvPutText([debugImage image], [_lastBarcodeThisProcessor UTF8String], point, &wellFont, CV_RGBA(232, 0, 217, 255));
        }
        
        // Record statistics on the tracked image synchronously (at frame rate), so that we drop frames if we can't keep up.
        // It is important to base all statistics on the elapsed time so that the results are independent of hardware
        // performance.
        if (_processingState == ProcessingStateTrackingMotion) {
            if (_lastFrame) {
                // Calculate and store the data
                std::vector<double> occupancyFractions = calculateCannyEdgePixelProportionForWellsFromImages([videoFrame image],
                                                                                                             _trackingWellCircles,
                                                                                                             [debugImage image]);
                std::vector<double> normalizedMovedFractions = calculateMovedWellFractionPerSecondForWellsFromImages([_lastFrame image],
                                                                                                                     [videoFrame image],
                                                                                                                     presentationTime - [_plateData lastPresentationTime],
                                                                                                                     _trackingWellCircles,
                                                                                                                     [debugImage image]);
                // If we were able to get stats, add them to the plate data
                if (normalizedMovedFractions.size() > 0) {
                    [_plateData addFrameOccupancyFractions:&*occupancyFractions.begin()
                                  normalizedMovedFractions:&*normalizedMovedFractions.begin()
                                        atPresentationTime:presentationTime];
                }
                
                // Print the stats in the wells averaged over the last 10 seconds to limit computational complexity
                CvFont wellFont = fontForNormalizedScale(0.75, [debugImage image]);
                for (size_t i = 0; i < _trackingWellCircles.size(); i++) {
                    double mean, stddev;
                    [_plateData normalizedMovedFractionMean:&mean stdDev:&stddev forWell:i inLastSeconds:10];
                    
                    float radius = _trackingWellCircles[i].radius;
                    CvPoint textPoint = cvPoint(_trackingWellCircles[i].center[0] - radius * 0.5, _trackingWellCircles[i].center[1]);
                    cvPutText([debugImage image],
                              [[NSString stringWithFormat:@"%.0f (SD: %.0f)", mean * 1000, stddev * 1000] UTF8String],
                              textPoint,
                              &wellFont,
                              CV_RGBA(0, 255, 255, 255));
                }
            }
            
            // Store the current image for the next pass
            [_lastFrame release];
            _lastFrame = [videoFrame retain];
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
    int wellRadiusHint = _wellRadiusHint;
    bool searchAllPlateSizes = _processingState == ProcessingStateNoPlate;
    
    // Perform the calculation on a concurrent queue so that we don't block the current thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Get wells in row major order
        std::vector<Circle> wellCircles;
        bool plateFound;
        if (searchAllPlateSizes) {
            plateFound = findWellCircles([videoFrame image], wellCircles, wellCountHint);
        } else {
            plateFound = findWellCirclesForPlateCount([videoFrame image], wellCountHint, wellCircles, wellRadiusHint);
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
                    _wellRadiusHint = wellCircles[0].radius;
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
                            // 250 ms, begin motion tracking and video recording
                            if (plateSequentialCirclesAppearSameAndStationary(_trackingWellCircles, wellCircles) &&
                                presentationTime - _firstWellFrameTime >= 0.250) {
                                _processingState = ProcessingStateTrackingMotion;
                                _trackingWellCircles = wellCircles; // store the second set as the baseline for all remaining sets
                                _lastBarcodeScanTime = PresentationTimeDistantPast;     // Now that plate is in place, immediately retry barcode capture
                                
                                // Create plate data and set start time
                                NSAssert(!_plateData, @"plate data already exists");
                                _plateData = [[PlateData alloc] initWithWellCount:wellCircles.size() startPresentationTime:presentationTime];
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
        });
    });
}

// requires _queue to be held
- (void)performBarcodeReadingAsyncWithFrame:(IplImageObject *)videoFrame presentationTime:(NSTimeInterval)presentationTime
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
            _scanningForBarcodes = NO;
            _lastBarcodeScanTime = presentationTime;
            [_lastBarcodeThisProcessor release];
            _lastBarcodeThisProcessor = [text retain];
            if (text) {
                [_delegate videoProcessor:self didCaptureBarcodeText:text atTime:presentationTime];
            }
        });
        
        [text release];
        cvReleaseImage(&grayscaleImage);
    });
}

// requires _queue to be held
- (void)resetCaptureStateAndReportResults
{
    // Send the stats unconditionally and let the controller sort it out
    [_delegate videoProcessor:self didFinishAcquiringPlateData:_plateData];
        // SAVE AND NAME VIDEO XXX DONT DEADLOCK WHEN GETTING RESULT NAME  (INSTEAD PASS TEMP FILE NAME TO VIDEO PROCESSOR
        //[self endRecordingVideoWithName];
        // ELSE IF TOO SHORT DELETE THE VIDEO
    
    _processingState = ProcessingStateNoPlate;
    [_plateData release];
    _plateData = nil;
    [_lastFrame release];
    _lastFrame = nil;
    
    _firstWellFrameTime = PresentationTimeDistantPast;
    _lastBarcodeScanTime = PresentationTimeDistantPast;
    _trackingWellCircles.clear();
    _lastCircles.clear();
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
