//
//  LuminanceMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/19/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "LuminanceMotionAnalyzer.h"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"

static const double PixelDeltaMovingProportionThreshold = 0.02;
static const double WellEdgeFindingInsetProportion = 0.7;

static const char* WellOccupancyID = "WellOccupancy";

@implementation LuminanceMotionAnalyzer

- (void)dealloc
{
    [_lastFrame release];
    if (_insetInvertedCircleMask) {
        cvReleaseImage(&_insetInvertedCircleMask);
    }
    if (_invertedCircleMask) {
        cvReleaseImage(&_invertedCircleMask);
    }
    [super dealloc];
}

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Luminance", nil);
}

- (BOOL)canProcessInParallel
{
    return YES;
}

- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData
{
    [plateData setReportingStyle:ReportingStyleMeanAndStdDev forDataColumnID:WellOccupancyID];
}

- (BOOL)willBeginFrameProcessing:(VideoFrame *)videoFrame debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData
{
    // If this is the first frame, we bail and wait for the next
    if (!_lastFrame) {
        _lastFrame = [videoFrame retain];
        return NO;
    }
    
    // ===== Plate movement and illumination change detection =====
    
    // Subtract the entire plate images channelwise
    IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
    cvAbsDiff([videoFrame image], [_lastFrame image], plateDelta);
    
    // Determine the mean delta
    CvScalar channelMean, channelStdDev;
    cvAvgSdv(grayscalePlateDelta, &channelMean, &channelStdDev);   //  xxxxxxxxxxxxxxxxxxxxXXXXXXXXXXX CHANGE TO AVG
    double mean = (channelMean[0] + channelMean[1] + channelMean[2]) / 3;
    NSLog(@"###########  WHOLE PLATE MEAN %f SD: %f", mean, (channelStdDev[0] + channelStdDev[1] + channelStdDev[2]) / 3;
    
    cvReleaseImage(&plateDelta);
    
    // If the delta is more than about XXX%, the entire plate is likely moving, so don't perform any well calculations between these two plates
    if (proportionPlateMoved < PixelDeltaMovingProportionThreshold) {
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

- (void)processVideoFrameWellSynchronously:(IplImage*)wellImage forWell:(int)well debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData
{
    // ======= Contour finding ========
    
    // If we haven't already, create an inverted circle mask with 0's in the circle.
    // We use only a portion of the circle to conservatively avoid taking the well walls.
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
    [plateData appendResult:occupancyFraction toDataColumnID:occupancyFraction forWell:well];
    cvSet(debugImage, CV_RGBA(0, 0, 255, 255), dialtedEdges);
    cvReleaseImage(&dialtedEdges);
    
    // ======== Motion measurement =========
    
    // If we haven't already, create an inverted circle mask with all bits on in the circle (but not inset)
    if (!_invertedCircleMask || !sizeEqualsSize(cvGetSize(_circleMask), cvGetSize(wellImage))) {
        if (_invertedCircleMask) {
            cvReleaseImage(&_invertedCircleMask);
        }
        _invertedCircleMask = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
        fastFillImage(_invertedCircleMask, 255);
        cvCircle(_invertedCircleMask, cvPoint(radius, radius), radius, cvRealScalar(0), CV_FILLED);
    }
    
    // Subtract the well images channelwise
    IplImage previousWellImage;
    memcpy(&previousWellImage, [_lastFrame image], sizeof(IplImage));
    cvSetImageROI(&previousWellImage, cvGetImageROI(_lastFrame));
    IplImage* wellDelta = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 4);
    cvAbsDiff(wellImage, &previousWellImage, wellDelta);
    
    // Gaussian blur the delta in place
    cvSmooth(wellDelta, wellDelta, CV_GAUSSIAN, 7, 7, 3, 3);
    
    // Convert the delta to luminance
    IplImage* deltaLuminance = cvCreateImage(cvGetSize(wellDelta), IPL_DEPTH_8U, 1);
    cvCvtColor(wellDelta, deltaLuminance, CV_BGR2GRAY);
    cvReleaseImage(&wellDelta);
    
    // Threshold the image to isolate difference pixels corresponding to movement as opposed to noise
    IplImage* deltaThreshold = cvCreateImage(cvGetSize(deltaLuminance), IPL_DEPTH_8U, 1);
    cvThreshold(deltaLuminance, deltaThreshold, 15, 255, CV_THRESH_BINARY);
    cvReleaseImage(&deltaLuminance);
    
    // Mask the threshold subimage
    cvSet(deltaThreshold, cvRealScalar(0), _invertedCircleMask);
    
    // Count pixels and draw onto the debugging image
    double movedFraction = (double)cvCountNonZero(deltaThreshold) / (M_PI * radius * radius);
    [plateData appendMovementUnit:movedFraction atPresentationTime:presentationTime forWell:well];
    cvSet(debugImage, CV_RGBA(255, 0, 0, 255), deltaThreshold);
    
    cvReleaseImage(&deltaThreshold);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrame release];
    _lastFrame = [videoFrame retain];
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

@end
