//
//  MotionAnalysis.cpp
//  WormAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "MotionAnalysis.hpp"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"
#import <math.h>
#import <dispatch/dispatch.h>

#define ABS(x) ((x) > 0 ? (x) : -(x)) 

static const double MovedPixelPlateMovingProportionThreshold = 0.02;
static const double WellEdgeFindingInsetProportion = 0.7;

static inline CvRect boundingSquareForCircle(Circle circle);

std::vector<double> calculateMovedWellFractionForWellsFromImages(IplImage* plateImagePrev,
                                                                 IplImage* plateImageCur,
                                                                 const std::vector<Circle> &circles,
                                                                 IplImage* debugImage)
{
    // If there was a resolution change, report that the frame moved
    if (plateImagePrev->width != plateImageCur->width || plateImagePrev->height != plateImageCur->height || circles.size() == 0) {
        return std::vector<double>();
    }
    
    // Subtrace the entire plate images channelwise
    IplImage* plateDelta = cvCreateImage(cvGetSize(plateImageCur), IPL_DEPTH_8U, 4);
    cvAbsDiff(plateImageCur, plateImagePrev, plateDelta);
    
    // Gaussian blur the delta in place
    cvSmooth(plateDelta, plateDelta, CV_GAUSSIAN, 7, 7, 3, 3);
    
    // Convert the delta to luminance
    IplImage* deltaLuminance = cvCreateImage(cvGetSize(plateDelta), IPL_DEPTH_8U, 1);
    cvCvtColor(plateDelta, deltaLuminance, CV_BGR2GRAY);
    cvReleaseImage(&plateDelta);
    
    // Threshold the image to isolate difference pixels corresponding to movement as opposed to noise
    IplImage* deltaThreshold = cvCreateImage(cvGetSize(deltaLuminance), IPL_DEPTH_8U, 1);
    cvThreshold(deltaLuminance, deltaThreshold, 15, 255, CV_THRESH_BINARY);
    cvReleaseImage(&deltaLuminance);
    
    // Calculate the average luminance delta across the entire plate image. If this is more than about 2%, the entire plate is likely moving.
    double proportionPlateMoved = (double)cvCountNonZero(deltaThreshold) / (plateImageCur->width * plateImagePrev->height);
    
    std::vector<double> movedPixelProportions;
    
    if (proportionPlateMoved < MovedPixelPlateMovingProportionThreshold) {      // Don't perform well calculations if the plate itself is moving
        movedPixelProportions.reserve(circles.size());
        
        // Create a circle mask with bits in the circle on
        float radius = circles[0].radius;
        IplImage* circleMask = cvCreateImage(cvSize(radius * 2, radius * 2), IPL_DEPTH_8U, 1);
        fastZeroImage(circleMask);
        cvCircle(circleMask, cvPoint(radius, radius), radius, cvRealScalar(255), CV_FILLED);
        
        // Iterate through each well and count the pixels that pass the threshold
        for (size_t i = 0; i < circles.size(); i++) {
            // Get the subimage of the thresholded delta image for the current well using the circle mask
            CvRect boundingSquare = boundingSquareForCircle(circles[i]);
            
            cvSetImageROI(deltaThreshold, boundingSquare);
            IplImage* subimage = cvCreateImage(cvGetSize(deltaThreshold), IPL_DEPTH_8U, 1);
            fastZeroImage(subimage);
            cvCopy(deltaThreshold, subimage, circleMask);
            cvResetImageROI(deltaThreshold);
            
            // Count pixels
            double proportion = (double)cvCountNonZero(subimage) / (M_PI * radius * radius);
            movedPixelProportions.push_back(proportion);
            
            // Draw onto the debugging image
            if (debugImage) {
                cvSetImageROI(debugImage, boundingSquare);
                cvSet(debugImage, CV_RGBA(255, 0, 0, 255), subimage);
                cvResetImageROI(debugImage);
            }
            
            cvReleaseImage(&subimage);
        }
        cvReleaseImage(&circleMask);
    } else {
        // Draw the movement text
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "CAMERA OR PLATE MOVING",
                  cvPoint(debugImage->width * 0.1, debugImage->height * 0.55),
                  &wellFont,
                  CV_RGBA(232, 0, 217, 255));

    }
    
    cvReleaseImage(&deltaThreshold);
    return movedPixelProportions;
}

std::vector<double> calculateCannyEdgePixelProportionForWellsFromImages(IplImage* plateImage, const std::vector<Circle> &circles, IplImage* debugImage)
{
    if (circles.size() == 0) {
        return std::vector<double>();
    }
    
    // Create an inverted circle mask with 0's in the circle. Use only a portion of the circle to conservatively avoid taking the well walls.
    float radius = circles[0].radius;
    IplImage* invertedCircleMask = cvCreateImage(cvSize(radius * 2, radius * 2), IPL_DEPTH_8U, 1);
    fastFillImage(invertedCircleMask, 255);
    cvCircle(invertedCircleMask, cvPoint(radius, radius), radius * WellEdgeFindingInsetProportion, cvRealScalar(0), CV_FILLED);
    
    // Iterate through each well and get edge images for each serially
    IplImage *subimages = (IplImage*)malloc(circles.size() * sizeof(IplImage));
    for (size_t i = 0; i < circles.size(); i++) {
        std::memcpy(&subimages[i], plateImage, sizeof(IplImage));
    }
    
    // Iterare through each well subimage in parallel
    double* edgePixelPorportions = (double*)malloc(circles.size() * sizeof(double));
    dispatch_apply(circles.size(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){
        // Get grayscale subimages for the well
        CvRect boundingSquare = boundingSquareForCircle(circles[i]);
        cvSetImageROI(&subimages[i], boundingSquare);
        IplImage* grayscaleImage = cvCreateImage(cvGetSize(&subimages[i]), IPL_DEPTH_8U, 1);
        cvCvtColor(&subimages[i], grayscaleImage, CV_BGRA2GRAY);
        
        // Find edges in the image
        IplImage* cannyEdges = cvCreateImage(cvGetSize(grayscaleImage), IPL_DEPTH_8U, 1);
        cvCanny(grayscaleImage, cannyEdges, 50, 150);
        
        // Mask off the edge pixels that correspond to the wells
        cvSet(cannyEdges, cvRealScalar(0), invertedCircleMask);
        
        // Dilate the edge image
        IplImage* dialtedEdges = cvCreateImage(cvGetSize(grayscaleImage), IPL_DEPTH_8U, 1);
        cvDilate(cannyEdges, dialtedEdges);
        
        // Store the pixel counts
        edgePixelPorportions[i] = (double)cvCountNonZero(dialtedEdges) / (dialtedEdges->width * dialtedEdges->height);
        
        // Draw debugging images and free images. If the edge pixel count is less than 0.5%, don't draw the noise.
        if (debugImage && edgePixelPorportions[i] > 0.005) {
            IplImage debugImageHeaderCopy;
            std::memcpy(&debugImageHeaderCopy, debugImage, sizeof(IplImage));
            CvRect boundingSquare = boundingSquareForCircle(circles[i]);
            cvSetImageROI(&debugImageHeaderCopy, boundingSquare);
            cvSet(&debugImageHeaderCopy, CV_RGBA(0, 0, 255, 255), dialtedEdges);
        }
        
        cvReleaseImage(&dialtedEdges);
        cvReleaseImage(&cannyEdges);
        cvReleaseImage(&grayscaleImage);
    });
    
    std::vector<double> vector = std::vector<double>(edgePixelPorportions, edgePixelPorportions + circles.size());
    
    free(edgePixelPorportions);
    free(subimages);
    cvReleaseImage(&invertedCircleMask);
    
    return vector;
}

static inline CvRect boundingSquareForCircle(Circle circle)
{
    float radius = circle.radius;
    return cvRect(circle.center[0] - radius, circle.center[1] - radius, 2 * radius, 2 * radius);
}
