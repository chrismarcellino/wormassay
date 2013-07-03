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

static const double WellEdgeFindingInsetProportion = 0.7;
static const double PlateMovingProportionAboveThresholdLimit = 0.06;
static const double PlateMovingProportionAboveThresholdLimitFullPlate = 0.20;
static const char* WellOccupancyID = "Well Occupancy";

@implementation ConsensusLuminanceMotionAnalyzer

@synthesize numberOfVotingFrames = _numberOfVotingFrames;
@synthesize quorum = _quorum;
@synthesize evaluateFramesAmongLastSeconds = _evaluateFramesAmongLastSeconds;
@synthesize deltaThresholdCutoff = _deltaThresholdCutoff;

- (id)init
{
    if ((self = [super init])) {
        _numberOfVotingFrames = 5;
        _quorum = 3;
        _evaluateFramesAmongLastSeconds = 1.0;
        _deltaThresholdCutoff = 10;

        _lastFrames = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    if (_pixelwiseVotes) {
        cvReleaseImage(&_pixelwiseVotes);
    }
}

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Consensus Voting Luminance Difference (dArea)", nil);
}

- (BOOL)canProcessInParallel
{
    return YES;
}

- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData
{
    [plateData setReportingStyle:(ReportingStyleMean | ReportingStyleStdDev | ReportingStylePercent) forDataColumnID:WellOccupancyID];
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
        if ([oldestFrame presentationTime] < [videoFrame presentationTime] - _evaluateFramesAmongLastSeconds) {
            [_lastFrames removeObjectAtIndex:0];
        } else {
            break;
        }
    }
    
    // Randomly choose a subset of _numberOfVotingFrames recent images. We choose the subset once per place to minimize inter-well noise.
    NSMutableArray *frameChoices = [_lastFrames mutableCopy];
    NSMutableArray *randomlyChosenFrames = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < _numberOfVotingFrames && [frameChoices count] > 0; i++) {
        NSUInteger randomIndex = random() % [frameChoices count];
        VideoFrame *frame = [frameChoices objectAtIndex:randomIndex];
        [randomlyChosenFrames addObject:frame];
        [frameChoices removeObjectAtIndex:randomIndex];
    }
    
    // ===== Plate movement and illumination change detection =====
    
    __block double meanProportionPlateMoved = 0.0;
    
    NSAssert(!_pixelwiseVotes, @"_pixelwiseVotes already exists");
    _pixelwiseVotes = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 1);
    fastZeroImage(_pixelwiseVotes);
    
    dispatch_queue_t criticalSection = dispatch_queue_create(NULL, NULL);
    dispatch_apply([randomlyChosenFrames count], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){
        VideoFrame *pastFrame = [randomlyChosenFrames objectAtIndex:i];
        // Subtract the entire plate images channelwise
        IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
        cvAbsDiff([videoFrame image], [pastFrame image], plateDelta);
        
        // Gaussian blur the delta
        cvSmooth(plateDelta, plateDelta, CV_GAUSSIAN, 0, 0, 3, 3);
        
        // Convert the delta to luminance
        IplImage* deltaLuminance = cvCreateImage(cvGetSize(plateDelta), IPL_DEPTH_8U, 1);
        cvCvtColor(plateDelta, deltaLuminance, CV_BGR2GRAY);
        cvReleaseImage(&plateDelta);
        
        // Threshold the image to isolate difference pixels corresponding to movement as opposed to noise,
        // setting each pixel that passes the threshold to 1 (for ease in summing below)
        IplImage* deltaThresholdedImage = cvCreateImage(cvGetSize(deltaLuminance), IPL_DEPTH_8U, 1);
        cvThreshold(deltaLuminance, deltaThresholdedImage, _deltaThresholdCutoff, 1, CV_THRESH_BINARY);
        cvReleaseImage(&deltaLuminance);
        
        dispatch_sync(criticalSection, ^{
            // Sum the threshold subimages from the random set delta from the current frame. The luminance sum at each
            // pixel will equal the number of votes, since we set the pixels that passed the threshold to 1.
            cvAdd(_pixelwiseVotes, deltaThresholdedImage, _pixelwiseVotes);
            // Calculate the mean for plate movement/lighting change determination
            meanProportionPlateMoved += (double)cvCountNonZero(deltaThresholdedImage) / (deltaThresholdedImage->width * deltaThresholdedImage->height);
        });
        cvReleaseImage(&deltaThresholdedImage);
    });
    dispatch_release(criticalSection);
    
    meanProportionPlateMoved /= [randomlyChosenFrames count];
    
    // If the average luminance delta across the set of entire plate images is more than about 6% (20% in full plate/single well), the entire plate is likely moving.
    BOOL fullPlate = [plateData wellCount] <= 1;
    BOOL overThreshold = meanProportionPlateMoved > (fullPlate ? PlateMovingProportionAboveThresholdLimitFullPlate : PlateMovingProportionAboveThresholdLimit);
    if (overThreshold || _lastMovementThresholdPresentationTime == 0) {     // start in moved mode
        _lastMovementThresholdPresentationTime = [videoFrame presentationTime];
    }
    
    if (overThreshold || _lastMovementThresholdPresentationTime + IgnoreFramesPostMovementTimeInterval() > [videoFrame presentationTime]) {
        // Draw the movement text
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "PLATE OR LIGHTING MOVING",
                  cvPoint(debugImage->width * 0.075, debugImage->height * 0.55),
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
    
    // Create a circle mask with all bits on in the circle using only a portion of the circle to conservatively avoid taking the well walls.
    int radius = cvGetSize(wellImage).width / 2;
    IplImage *insetCircleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    fastZeroImage(insetCircleMask);
    cvCircle(insetCircleMask, cvPoint(insetCircleMask->width / 2, insetCircleMask->height / 2), radius * WellEdgeFindingInsetProportion, cvRealScalar(255), CV_FILLED);
    
    // Get grayscale subimages for the well
    IplImage* grayscaleImage = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    cvCvtColor(wellImage, grayscaleImage, CV_BGRA2GRAY);
    
    // Find edges in the grayscale image
    IplImage* cannyEdges = cvCreateImage(cvGetSize(grayscaleImage), IPL_DEPTH_8U, 1);
    cvCanny(grayscaleImage, cannyEdges, 50, 150);
    cvReleaseImage(&grayscaleImage);
    
    // Mask off the edge pixels that correspond to the wells
    cvAnd(cannyEdges, insetCircleMask, cannyEdges);
    
    // Dilate the edge image
    IplImage* dialtedEdges = cvCreateImage(cvGetSize(cannyEdges), IPL_DEPTH_8U, 1);
    cvDilate(cannyEdges, dialtedEdges);
    cvReleaseImage(&cannyEdges);
    
    // Store the pixel counts and draw debugging images
    double occupancyFraction = (double)cvCountNonZero(dialtedEdges) / (dialtedEdges->width * dialtedEdges->height);
    [plateData appendResult:occupancyFraction toDataColumnID:WellOccupancyID forWell:well];
    cvSet(debugImage, CV_RGBA(0, 0, 255, 255), dialtedEdges);
    cvReleaseImage(&dialtedEdges);
    cvReleaseImage(&insetCircleMask);
    
    // ======== Motion measurement =========
    
    // Create an circle mask with all bits on in the circle (but not inset)
    IplImage *circleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    fastZeroImage(circleMask);
    cvCircle(circleMask, cvPoint(circleMask->width / 2, circleMask->height / 2), radius, cvRealScalar(255), CV_FILLED);
    
    // Mask the pixelwise votes (using a local stack copy of the header for threadsafety)
    IplImage wellPixelwiseVotes = *_pixelwiseVotes;
    cvSetImageROI(&wellPixelwiseVotes, cvGetImageROI(wellImage));
    cvAnd(&wellPixelwiseVotes, circleMask, &wellPixelwiseVotes);
    
    // Keep the pixels that have a quorum
    IplImage *quorumPixels = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    cvThreshold(&wellPixelwiseVotes, quorumPixels, _quorum - 0.5, 255, CV_THRESH_BINARY);
    cvResetImageROI(&wellPixelwiseVotes);
    double movedFraction = (double)cvCountNonZero(quorumPixels) / (M_PI * radius * radius) * 1000.0;  // use milli-fractions for readability
    
    // Count pixels and draw onto the debugging image
    [plateData appendMovementUnit:movedFraction atPresentationTime:presentationTime forWell:well];
    cvSet(debugImage, CV_RGBA(255, 0, 0, 255), quorumPixels);
    
    cvReleaseImage(&quorumPixels);
    cvReleaseImage(&circleMask);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrames addObject:videoFrame];
    if (_pixelwiseVotes) {
        cvReleaseImage(&_pixelwiseVotes);
    }
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

- (NSTimeInterval)minimumTimeIntervalProcessedToReportData
{
    return 5.0;
}

- (NSUInteger)minimumSamplesProcessedToReportData
{
    return 5;
}

@end
