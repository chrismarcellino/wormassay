//
//  OpticalFlowMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 5/12/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "OpticalFlowMotionAnalyzer.h"
#import "PlateData.h"
#import "VideoFrame.h"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"

static const char* WellOccupancyID = "Well Occupancy";
static const double WellEdgeFindingInsetProportion = 0.8;
static const double MaximumNumberOfFeaturePointsToAreaRatio = 1.0 / 200.0;
static const double DeltaMeanMovementLimit = 20.0;
static const double DeltaStdDevMovementLimit = 10.0;
static const NSTimeInterval MinimumIntervalFrameInterval = 0.100;
static const double MinimumMovementMagnitude = 1.0;

@implementation OpticalFlowMotionAnalyzer

- (id)init
{
    if ((self = [super init])) {
        _lastFrames = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Lucas—Kanade Optical Flow (Velocity, 1 organism per well)", nil);
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
    // Find the most recent video frame that is at least 100 ms earlier than the current and discard older frames
    _prevFrame = nil;
    for (NSInteger i = (NSInteger)[_lastFrames count] - 1; i >= 0; i--) {
        VideoFrame *aFrame = [_lastFrames objectAtIndex:i];
        if ([videoFrame presentationTime] - [aFrame presentationTime] >= MinimumIntervalFrameInterval) {
            _prevFrame = aFrame;
            // use i, not "i + 1" so we don't delete the one we chose in case we don't get a better one next time
            [_lastFrames removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, i)]];
            break;
        }
    }
        
    if (!_prevFrame) {
        _lastMovementThresholdPresentationTime = -FLT_MAX;
        return NO;
    }
    
    // Calculate the mean inter-frame delta for plate movement/lighting change determination
    IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
    cvAbsDiff([videoFrame image], [_prevFrame image], plateDelta);
    CvScalar mean, stdDev;
    cvAvgSdv(plateDelta, &mean, &stdDev);
    double deltaMean = (mean.val[0] + mean.val[1] + mean.val[2]) / 3.0;
    double deltaStdDevAvg = (stdDev.val[0] + stdDev.val[1] + stdDev.val[2]) / 3.0;
    cvReleaseImage(&plateDelta);

    BOOL overThreshold = deltaMean > DeltaMeanMovementLimit || deltaStdDevAvg > DeltaStdDevMovementLimit;
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
    CvSize size = cvGetSize(wellImage);
    // Get the previous well (using a local stack copy of the header for threadsafety)
    IplImage prevWellImage = *[_prevFrame image];
    cvSetImageROI(&prevWellImage, cvGetImageROI(wellImage));
    
    // ======= Contour finding ========
    
    // Create a circle mask with all bits on in the circle using only a portion of the circle to avoid taking the well walls
    int radius = size.width / 2;
    IplImage *insetCircleMask = NULL;
    if (well >= 0) {
        insetCircleMask = cvCreateImage(size, IPL_DEPTH_8U, 1);
        fastZeroImage(insetCircleMask);
        cvCircle(insetCircleMask, cvPoint(insetCircleMask->width / 2, insetCircleMask->height / 2), radius * WellEdgeFindingInsetProportion, cvRealScalar(255), CV_FILLED);
    }
    
    // Find edges in the grayscale image
    IplImage* cannyEdges = cvCreateImage(size, IPL_DEPTH_8U, 1);
    cvCanny(wellImage, cannyEdges, 50, 150);
    
    // Mask off the edge pixels that correspond to the wells
    if (insetCircleMask) {
        cvAnd(cannyEdges, insetCircleMask, cannyEdges);
        cvReleaseImage(&insetCircleMask);
    }
    
    // Get the edge points
    std::vector<CvPoint2D32f> featuresCur;
    featuresCur.reserve(1024);
    assert(cannyEdges->depth == IPL_DEPTH_8U);
    uchar *row = (uchar *)cannyEdges->imageData;
    for (int i = 0; i < cannyEdges->height; i++) {
        for (int j = 0; j < cannyEdges->width; j++) {
            if (row[j]) {
                featuresCur.push_back(cvPoint2D32f(j, i));
            }
        }
        row += cannyEdges->widthStep;
    }
    // If we have too many points, randomly shuffle MaximumNumberOfFeaturePoints to the begining and keep that set
    size_t maxNumberOfFeatures = M_PI * radius * radius * MaximumNumberOfFeaturePointsToAreaRatio;
    if (featuresCur.size() > maxNumberOfFeatures) {
        for (size_t i = 0; i < maxNumberOfFeatures; i++) {
            size_t other = random() % featuresCur.size();
            std::swap(featuresCur[i], featuresCur[other]);
        }
        featuresCur.resize(maxNumberOfFeatures);
    }
    
    // Store the pixel counts and draw debugging images
    double occupancyFraction = (double)cvCountNonZero(cannyEdges) / (cannyEdges->width * cannyEdges->height);
    [plateData appendResult:occupancyFraction toDataColumnID:WellOccupancyID forWell:well];
    cvSet(debugImage, CV_RGBA(0, 0, 255, 255), cannyEdges);
    cvReleaseImage(&cannyEdges);
    
    // ======== Motion measurement =========
    
    CvSize pyrSize = cvSize(size.width + 8, size.height / 3);
	IplImage* curPyr = cvCreateImage(pyrSize, IPL_DEPTH_32F, 1);
    IplImage* prevPyr = cvCreateImage(pyrSize, IPL_DEPTH_32F, 1);
    
    CvPoint2D32f* featuresPrev = new CvPoint2D32f[featuresCur.size()];
    char *featuresPrevFound = new char[featuresCur.size()];
    
    cvCalcOpticalFlowPyrLK(wellImage,
                           &prevWellImage,
                           curPyr,
                           prevPyr,
                           &*featuresCur.begin(),
                           featuresPrev,
                           featuresCur.size(),
                           cvSize(15, 15),      // pyramid window size
                           5,                   // number of pyramid levels
                           featuresPrevFound,
                           NULL,
                           cvTermCriteria(CV_TERMCRIT_ITER | CV_TERMCRIT_EPS, 20, 0.3),
                           0);
    
    // Iterate through the feature points and get the average movement
    float averageMovement = 0.0;
    size_t countFound = 0;
    for (size_t i = 0; i < featuresCur.size(); i++) {
        if (featuresPrevFound[i]) {
            CvPoint2D32f delta = { featuresPrev[i].x - featuresCur[i].x, featuresPrev[i].y - featuresCur[i].y };
            float magnitude = sqrtf(delta.x * delta.x + delta.y * delta.y);
            if (magnitude > MinimumMovementMagnitude && magnitude < radius) {
                countFound++;
                averageMovement += magnitude;
                
                // Draw arrows on the debug image
                CvScalar lineColor = CV_RGBA(255, 0, 0, 255);
                const int lineWidth = 2;
                const int arrowLength = 5;
                CvPoint2D32f p = featuresPrev[i];
                CvPoint2D32f c = featuresCur[i];
                p.x += p.x - c.x;       // double the vector length for visibility
                p.y += p.y - c.y;
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
                double angle = atan2(p.y - c.y, p.x - c.x);
                p.x = c.x + arrowLength * cos(angle + M_PI_4);
                p.y = c.y + arrowLength * sin(angle + M_PI_4);
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
                p.x = c.x + arrowLength * cos(angle - M_PI_4);
                p.y = c.y + arrowLength * sin(angle - M_PI_4);
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
            }
        }
    }
    if (countFound > 0) {
        averageMovement /= countFound;
    }
    double averageMovementPerSecond = averageMovement / (presentationTime - [_prevFrame presentationTime]);
    [plateData appendMovementUnit:averageMovementPerSecond atPresentationTime:presentationTime forWell:well];
    
    cvReleaseImage(&curPyr);
    cvReleaseImage(&prevPyr);
    delete[] featuresPrevFound;
    delete[] featuresPrev;
    
    cvResetImageROI(&prevWellImage);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrames addObject:videoFrame];
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
