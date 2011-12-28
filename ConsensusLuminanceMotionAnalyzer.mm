//
//  ConsensusLuminanceMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "ConsensusLuminanceMotionAnalyzer.h"
#import "PlateData.h"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"

static const double PlateMovingProportionAboveThresholdLimit = 0.02;
static const double WellEdgeFindingInsetProportion = 0.7;
static const double EvaluateFramesAmongLastSeconds = 2.0;

static const char* WellOccupancyID = "WellOccupancy";

@implementation ConsensusLuminanceMotionAnalyzer

- (void)dealloc
{
    [_lastFrames release];
    if (_insetInvertedCircleMask) {
        cvReleaseImage(&_insetInvertedCircleMask);
    }
    if (_invertedCircleMask) {
        cvReleaseImage(&_invertedCircleMask);
    }
    if (_deltaThresholded) {
        cvReleaseImage(&_deltaThresholded);
    }
    [super dealloc];
}

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Consensus Voting Luminance Difference", nil);
}

- (BOOL)canProcessInParallel
{
    return YES;
}

- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData
{
    _lastFrames = [[NSMutableArray alloc] init];
    [plateData setReportingStyle:ReportingStyleMeanAndStdDev forDataColumnID:WellOccupancyID];
}

- (BOOL)willBeginFrameProcessing:(VideoFrame *)videoFrame debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData
{
    // Remove frames that are too old to consider
    while ([_lastFrames count] > 0) {
        VideoFrame *pastFrame = [_lastFrames objectAtIndex:0];
        if ([pastFrame presentationTime] < [VideoFrame presentationTime] - EvaluateFramesAmongLastSeconds) {
            [_lastFrames removeObjectAtIndex:0];
        }
    }
    
    if ([_lastFrames count] == 0) {
        if (_hadEnoughFramesAtLeastOnce) {
            cvPutText(debugImage,
                      "TOO MANY DROPPED FRAMES",
                      cvPoint(debugImage->width * 0.1, debugImage->height * 0.55),
                      &wellFont,
                      CV_RGBA(232, 0, 217, 255));
        }
        return NO;
    }
   _hadEnoughFramesAtLeastOnce = YES;
    
    // Randomly choose a subset of FRAME_MAX_SAMPLE_SIZE recent images
    NSMutableArray *frameSet = [_lastFrames copy];
    NSMutableArray *randomlyChosenFrames = [[NSMutableArray alloc] init];
    for (int i = 0; i < FRAME_MAX_SAMPLE_SIZE && [frameSet count] > 0; i++) {
        NSUInteger randomIndex = random() % [frameSet count];
        VideoFrame *frame = [frameSet objectAtIndex:randomIndex];
        [randomlyChosenFrames addObject:frame];
        [frameSet removeObjectAtIndex:randomIndex];
    }
    
    // ===== Plate movement and illumination change detection =====
    
    BOOL plateMovedOrIlluminationChanged = NO;
    
    dispatch_apply([randomlyChosenFrames count], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){
        VideoFrame *pastFrame = [randomlyChosenFrames objectAtIndex:i];
        // Subtract the entire plate images channelwise
        IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
        cvAbsDiff([videoFrame image], [pastFrame image], plateDelta);
        
        // Gaussian blur the delta in place
        cvSmooth(plateDelta, plateDelta, CV_GAUSSIAN, 7, 7, 3, 3);
        
        // Convert the delta to luminance
        IplImage* deltaLuminance = cvCreateImage(cvGetSize(plateDelta), IPL_DEPTH_8U, 1);
        cvCvtColor(plateDelta, deltaLuminance, CV_BGR2GRAY);
        cvReleaseImage(&plateDelta);
        
        // Threshold the image to isolate difference pixels corresponding to movement as opposed to noise
        NSAssert(!_deltaThresholded[i], @"_deltaThresholded[i] image already exists");
        _deltaThresholded[i] = cvCreateImage(cvGetSize(deltaLuminance), IPL_DEPTH_8U, 1);
        cvThreshold(deltaLuminance, _deltaThresholded[i], 15, 255, CV_THRESH_BINARY);
        cvReleaseImage(&deltaLuminance);
        
        double proportionPlateMoved = (double)cvCountNonZero(_deltaThresholded[i]) / (_deltaThresholded->width * _deltaThresholded->height);
        if (proportionPlateMoved > PlateMovingProportionAboveThresholdLimit) {
            plateMovedOrIlluminationChanged = YES;
        }
    });
    
    [randomlyChosenFrames release];
    [frameSet release];
    
    // Calculate the average luminance delta across the entire plate image. If this is more than about 2%, the entire plate is likely moving.
    if (plateMovedOrIlluminationChanged) {
        // Draw the movement text
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "CAMERA OR PLATE MOVING",
                  cvPoint(debugImage->width * 0.1, debugImage->height * 0.55),
                  &wellFont,
                  CV_RGBA(232, 0, 217, 255));
        return NO;
    }
        
    return YES;
}

- (void)processVideoFrameWellSynchronously:(IplImage*)wellImage
                                   forWell:(int)well
                                debugImage:(IplImage*)debugImage
                          presentationTime:(NSTimeInterval)presentationTime
                                 plateData:(PlateData *)plateData
{
    // ======= Contour finding ========
    
    // If we haven't already, create an inverted circle mask with 0's in the circle.
    // We use only a portion of the circle to conservatively avoid taking the well walls.
    int radius = cvGetSize(wellImage).width / 2;
    if (!_insetInvertedCircleMask || !sizeEqualsSize(cvGetSize(_insetInvertedCircleMask), cvGetSize(wellImage))) {
        if (_insetInvertedCircleMask) {
            cvReleaseImage(&_insetInvertedCircleMask);
        }
        _insetInvertedCircleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
        fastFillImage(_insetInvertedCircleMask, 255);
        cvCircle(_insetInvertedCircleMask, cvPoint(radius, radius), radius * WellEdgeFindingInsetProportion, cvRealScalar(0), CV_FILLED);
    }
    
    // Get grayscale subimages for the well
    IplImage* grayscaleImage = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    cvCvtColor(wellImage, grayscaleImage, CV_BGRA2GRAY);
    
    // Find edges in the grayscale image
    IplImage* cannyEdges = cvCreateImage(cvGetSize(grayscaleImage), IPL_DEPTH_8U, 1);
    cvCanny(grayscaleImage, cannyEdges, 50, 150);
    cvReleaseImage(&grayscaleImage);
    
    // Mask off the edge pixels that correspond to the wells
    cvSet(cannyEdges, cvRealScalar(0), _insetInvertedCircleMask);
    
    // Dilate the edge image
    IplImage* dialtedEdges = cvCreateImage(cvGetSize(cannyEdges), IPL_DEPTH_8U, 1);
    cvDilate(cannyEdges, dialtedEdges);
    cvReleaseImage(&cannyEdges);
    
    // Store the pixel counts and draw debugging images
    double occupancyFraction = (double)cvCountNonZero(dialtedEdges) / (dialtedEdges->width * dialtedEdges->height);
    [plateData appendResult:occupancyFraction toDataColumnID:WellOccupancyID forWell:well];
    cvSet(debugImage, CV_RGBA(0, 0, 255, 255), dialtedEdges);
    cvReleaseImage(&dialtedEdges);
    
    // ======== Motion measurement =========
    
    // If we haven't already, create an inverted circle mask with all bits on in the circle (but not inset)
    if (!_invertedCircleMask || !sizeEqualsSize(cvGetSize(_invertedCircleMask), cvGetSize(wellImage))) {
        if (_invertedCircleMask) {
            cvReleaseImage(&_invertedCircleMask);
        }
        _invertedCircleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
        fastFillImage(_invertedCircleMask, 255);
        cvCircle(_invertedCircleMask, cvPoint(radius, radius), radius, cvRealScalar(0), CV_FILLED);
    }
    
    // Mask the threshold subimages (using a local stack copy of the header for threadsafety)
    IplImage wellDeltaThresholded[FRAME_MAX_SAMPLE_SIZE];
    for (int i = 0; i < FRAME_MAX_SAMPLE_SIZE; i++) {
        wellDeltaThresholded[i] = *_deltaThresholded[i];
        cvSetImageROI(&wellDeltaThresholded[i], cvGetImageROI(wellImage));
        cvSet(&wellDeltaThresholded[i], cvRealScalar(0), _invertedCircleMask);
    }
    
    // Count pixels and draw onto the debugging image
    double movedFraction = (double)cvCountNonZero(&wellDeltaThresholded) / (M_PI * radius * radius);
    [plateData appendMovementUnit:movedFraction atPresentationTime:presentationTime forWell:well];
    cvSet(debugImage, CV_RGBA(255, 0, 0, 255), &wellDeltaThresholded);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrames addObject:videoFrame];
    for (int i = 0; i < FRAME_MAX_SAMPLE_SIZE; i++) {
        if (_deltaThresholded[i]) {
            cvReleaseImage(&_deltaThresholded[i]);
        }
    }
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

@end
