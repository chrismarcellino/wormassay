//
//  ConsensusLuminanceMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "ConsensusLuminanceMotionAnalyzer.h"
#import "PlateData.h"
#import "VideoFrame.h"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"

static const double PlateMovingProportionAboveThresholdLimit = 0.01;
static const double WellEdgeFindingInsetProportion = 0.7;
static const double EvaluateFramesAmongAtLeastLastSeconds = 2.0;        // exactly this value, except if there aren't _numberOfVotingFrames in that period

static const char* WellOccupancyID = "WellOccupancy";

@implementation ConsensusLuminanceMotionAnalyzer

@synthesize numberOfVotingFrames = _numberOfVotingFrames;
@synthesize quorum = _quorum;

- (id)init
{
    if ((self = [super init])) {
        _numberOfVotingFrames = 5;
        _quorum = 2;
    }
    return self;
}

- (void)dealloc
{
    [_lastFrames release];
    [_deltaThresholded release];
    if (_insetInvertedCircleMask) {
        cvReleaseImage(&_insetInvertedCircleMask);
    }
    if (_circleMask) {
        cvReleaseImage(&_circleMask);
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
    if ([_lastFrames count] < _numberOfVotingFrames) {
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "ACQUIRING IMAGES",
                  cvPoint(debugImage->width * 0.2, debugImage->height * 0.55),
                  &wellFont,
                  CV_RGBA(232, 0, 217, 255));
        return NO;
    }
    
    // Remove frames that are too old to consider
    while ([_lastFrames count] > _numberOfVotingFrames) {
        VideoFrame *oldestFrame = [_lastFrames objectAtIndex:0];
        if ([oldestFrame presentationTime] < [videoFrame presentationTime] - EvaluateFramesAmongAtLeastLastSeconds) {
            [_lastFrames removeObjectAtIndex:0];
        } else {
            break;
        }
    }
    
    // Randomly choose a subset of _numberOfVotingFrames recent images. We choose the subset once per place to minimize inter-well noise.
    NSMutableArray *frameSet = [_lastFrames mutableCopy];
    NSMutableArray *randomlyChosenFrames = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < _numberOfVotingFrames && [frameSet count] > 0; i++) {
        NSUInteger randomIndex = random() % [frameSet count];
        VideoFrame *frame = [frameSet objectAtIndex:randomIndex];
        [randomlyChosenFrames addObject:frame];
        [frameSet removeObjectAtIndex:randomIndex];
    }
    
    // ===== Plate movement and illumination change detection =====
    
    __block double meanProportionPlateMoved = 0.0;
    
    NSAssert(!_deltaThresholded, @"_deltaThresholded array already exists");
    _deltaThresholded = [[NSMutableArray alloc] init];
    dispatch_queue_t criticalSection = dispatch_queue_create(NULL, NULL);
    dispatch_apply([randomlyChosenFrames count], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){
        VideoFrame *pastFrame = [randomlyChosenFrames objectAtIndex:i];
        // Subtract the entire plate images channelwise
        IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
        cvAbsDiff([videoFrame image], [pastFrame image], plateDelta);
        
        // Gaussian blur the delta in place
        cvSmooth(plateDelta, plateDelta, CV_GAUSSIAN, 0, 0, 2, 2);
        
        // Convert the delta to luminance
        IplImage* deltaLuminance = cvCreateImage(cvGetSize(plateDelta), IPL_DEPTH_8U, 1);
        cvCvtColor(plateDelta, deltaLuminance, CV_BGR2GRAY);
        cvReleaseImage(&plateDelta);
        
        // Threshold the image to isolate difference pixels corresponding to movement as opposed to noise,
        // setting each pixel that passes the threshold to 1 (for ease in summing later.)
        IplImage *deltaThresholdedImage = cvCreateImage(cvGetSize(deltaLuminance), IPL_DEPTH_8U, 1);
        cvThreshold(deltaLuminance, deltaThresholdedImage, 15, 1, CV_THRESH_BINARY);
        cvReleaseImage(&deltaLuminance);
        
        VideoFrame *deltaThresholdedImageFrame = [[VideoFrame alloc] initWithIplImageTakingOwnership:deltaThresholdedImage
                                                                                    presentationTime:[videoFrame presentationTime]];
        dispatch_sync(criticalSection, ^{
            [_deltaThresholded addObject:deltaThresholdedImageFrame];
            meanProportionPlateMoved += (double)cvCountNonZero(deltaThresholdedImage) / (deltaThresholdedImage->width * deltaThresholdedImage->height);
        });
        [deltaThresholdedImageFrame release];
    });
    dispatch_release(criticalSection);
    
    meanProportionPlateMoved /= [randomlyChosenFrames count];
    [randomlyChosenFrames release];
    [frameSet release];
    
    // If the average luminance delta across the set of entire plate images is more than about 2%, the entire plate is likely moving.
    if (meanProportionPlateMoved > PlateMovingProportionAboveThresholdLimit) {
        // Draw the movement text
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "SUBJECT OR LIGHTING MOVING",
                  cvPoint(debugImage->width * 0.05, debugImage->height * 0.55),
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
    
    // If we haven't already, create an circle mask with all bits on in the circle (but not inset)
    if (!_circleMask || !sizeEqualsSize(cvGetSize(_circleMask), cvGetSize(wellImage))) {
        if (_circleMask) {
            cvReleaseImage(&_circleMask);
        }
        _circleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
        fastZeroImage(_circleMask);
        cvCircle(_circleMask, cvPoint(radius, radius), radius, cvRealScalar(255), CV_FILLED);
    }
    
    // Sum the threshold subimages from the random set delta from the current frame (using a local stack copy of the header for threadsafety).
    // The luminance sum at each pixel will equal the number of votes, since we set the pixels that passed the threshold to 1.
    IplImage *pixelwiseSum = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    fastZeroImage(pixelwiseSum);
    for (VideoFrame *deltaThresholdedImage in _deltaThresholded) {
        IplImage wellDeltaThresholded = *[deltaThresholdedImage image];
        cvSetImageROI(&wellDeltaThresholded, cvGetImageROI(wellImage));
        cvAdd(pixelwiseSum, &wellDeltaThresholded, pixelwiseSum, _circleMask);
    }
    
    // Keep the pixels that have a quorum
    IplImage *quorumPixels = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    cvThreshold(pixelwiseSum, quorumPixels, _quorum - 0.5, 255, CV_THRESH_BINARY);
    double movedFraction = (double)cvCountNonZero(quorumPixels) / (M_PI * radius * radius);
    
    // Count pixels and draw onto the debugging image
    [plateData appendMovementUnit:movedFraction atPresentationTime:presentationTime forWell:well];
    cvSet(debugImage, CV_RGBA(255, 0, 0, 255), quorumPixels);
    
    cvReleaseImage(&pixelwiseSum);
    cvReleaseImage(&quorumPixels);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrames addObject:videoFrame];
    [_deltaThresholded release];
    _deltaThresholded = nil;
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

@end
