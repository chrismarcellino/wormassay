//
//  ImageProcessing.cpp
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ImageProcessing.hpp"
#import "opencv2/opencv.hpp"
#import <math.h>

static int sortCircleCentersByAxis(const void* a, const void* b, void* userdata);
static int sortCirclesInRowMajorOrder(const void* a, const void* b, void* userdata);

// Sorted by prevalence, so that we try more common configurations first to speed detection
static int knownPlateWellCounts[] = { 24, 96, 48, 12, 6, 0 };     // zero terminated

bool getPlateConfigurationForWellCount(int wellCount, int &rows, int &columns)
{
    bool valid = true;
    switch (wellCount) {
        case 6:
            rows = 2;
            break;
        case 12:
            rows = 3;
            break;
        case 24:
            rows = 4;
            break;
        case 48:
            rows = 6;            
            break;
        case 96:
            rows = 8;
            break;
        default:
            valid = false;
            break;
    }
    
    if (valid) {
        columns = wellCount / rows;
    }
    return valid;
}

bool findWellCircles(IplImage *inputImage, int &wellCount, std::vector<cv::Vec3f> &circles)
{
    float bestScore = -1.0;
    float score;
    std::vector<cv::Vec3f> bestCircles;
    
    int *currentCount = knownPlateWellCounts;
    while (*currentCount != 0) {
        if (findWellCirclesForPlateCount(inputImage, *currentCount, circles, score)) {
            return true;
        }
        
        // Save the best scoring circles for debugging purposes
        if (score > bestScore) {
            bestScore = score;
            bestCircles = circles;
        }
        
        // Clear to try again
        circles.clear();
        currentCount++;
    }
    
    // Return the best circles on failure
    circles = bestCircles;
    return false;
}

bool findWellCirclesForPlateCount(IplImage *inputImage, int wellCount, std::vector<cv::Vec3f> &circlesVec, float &score)
{
    // Conver the input image to grayscale
    IplImage *grayInputImage = cvCreateImage(cvGetSize(inputImage), IPL_DEPTH_8U, 1);
    cvCvtColor(inputImage, grayInputImage, CV_BGRA2GRAY);
    
    // Determine well metrics for this plate type
    int rows, columns;
    getPlateConfigurationForWellCount(wellCount, rows, columns);
    int smallerImageDimension = MIN(inputImage->width, inputImage->height);
    int largerImageDimension = MAX(inputImage->width, inputImage->height);
    int errorTolerance = 0.20;      // 20%, see below
    
    // Notes on assumptions made for well dimensions:
    // Microtiter plates are 120 mm x 80 mm, which is a 3:2 ratio. We assume that the plate will
    // approximately fill the camera's field of view, with considerable room for error. 
    // On one end of the specturm are standard definition NTSC/PAL cameras with 4:3 aspect ratios. For these cameras, the longer
    // dimension of the plate will fill the frame, but the shorter end will have 9% dead space. 
    // Some obscure 3:2 cameras will yield no signifigant dead space. 
    // Modern HD cameras use a 16:9 aspect ratio which when filling the frame with the smaller dimension of the plate,
    // leaves 14% dead space on the longer dimension. (A few specialty high-budget filmmaking cameras use 1:85:1 or 2.39:1,
    // but those are unlikely to be encountered and would likely work well anyhow given our large error tolerances.)
    //
    // This means that when considering maximum well dimensions, if we assume 100% coverage of the plate with wells 
    // (which is impossibly conservative), we can assume that the smaller plate dimension can fit
    // <rows> diameters of wells, or twice as many radii. Hence we have:
    // well maximum radius = <smallerImageDimension> / (2 * <rows>) * (1 + <error tolerance>),
    // where the error tolerance is at least 9%. 
    //
    // The minimum well radius can be similarly calculated, by assuming that at least half of the plates diameter correspond to
    // wells (which is a very conservative assumption for all standard plates):
    // well minimum radius = 0.5 * <largerImageDimension> / (2 * <columns>) / (1 + <error tolerance>)
    // where the error tolerance is at least 14%.
    //
    // The minimum distance between well centers is just double the minimum radius calculated above, since wells cannot overlap.
    
    int maxRadius = smallerImageDimension / (2.0 * rows) * (1.0 + errorTolerance);
    int minRadius = 0.5 * largerImageDimension / (2.0 * columns) / (1.0 + errorTolerance);
    
    // Find all circles using the Hough transform. The seq returns contains Vec3fs, whose elements are (x-center, y-center, radius) triples.
    CvMemStorage* storage = cvCreateMemStorage();
    CvSeq* circles = cvHoughCircles(grayInputImage,
                                    storage,
                                    CV_HOUGH_GRADIENT,
                                    2,      // inverse accumulator resolution ratio
                                    minRadius * 2,  // min dist between centers
                                    100,    // Canny high threshold
                                    200,    // Accumulator threshold
                                    minRadius, // min radius
                                    maxRadius); // max radius
    
    // Take the set of all circles whose centers are approximately colinear with other circles along axis aligned lines
    // in both dimensions. Discard all others.
    int colinearityThreshold = maxRadius / 2;
    
    // First sort the centers by X value so that lines vertically colinear are adjacent in the seq. On the second pass, do the opposite. 
    bool expectedNumbersOfColinearCirclesFoundEverywhere = true;
    
    for (int axis = 0; axis <= 1; axis++) {
        cvSeqSort(circles, sortCircleCentersByAxis, &axis);
        
        // Iterate through list and move circles colinear along Y lines to a new seq, and hence have similar X values (and then vice versa)
        CvSeq* colinearCircles = cvCreateSeq(CV_32FC3, sizeof(CvSeq), 3 * sizeof(float), storage);
        
        for (int i = 0; i < circles->total; i++) {
            float* current = (float*)cvGetSeqElem(circles, i);
            
            int numberOfColinearCircles = 0;
            int j;
            for (j = i + 1; j < circles->total; j++) {
                float *partner = (float*)cvGetSeqElem(circles, j);
                if (fabsf(current[axis] - partner[axis]) <= colinearityThreshold) {
                    if (numberOfColinearCircles == 0) {
                        // Push the 'current' element
                        cvSeqPush(colinearCircles, current);
                        numberOfColinearCircles++;
                    }
                    
                    // Push each partner and advance i so these matching partners aren't unnecessarily reconsidered
                    cvSeqPush(colinearCircles, partner);
                    numberOfColinearCircles++;
                    i++;
                } else {
                    break;
                }
            }
            // Determine if we saw as many colinear circles as we expected
            int expectedNumberOfColinearCircles = (axis == 1) ? columns : rows;
            if (numberOfColinearCircles != expectedNumberOfColinearCircles) {
                expectedNumbersOfColinearCirclesFoundEverywhere = false;
            }
        }
        
        circles = colinearCircles;
    }
    
    // Sort the circles in row major order
    cvSeqSort(circles, sortCirclesInRowMajorOrder, &colinearityThreshold);
    
    vector<cv::Vec3f> circleVec;
    cv::Seq<cv::Vec3f>(circles).copyTo(circleVec);
    cvReleaseMemStorage(&storage);
    
    // Provide scores for debugging
    score = MAX(0.9 - (float)abs(circles->total - wellCount) / wellCount, 0.0);
    return circles->total == wellCount && expectedNumbersOfColinearCirclesFoundEverywhere;
}

static int sortCircleCentersByAxis(const void* a, const void* b, void* userdata)        // userdata is pointer to axis
{
    bool sortAlongYAxis = (*(int*)userdata == 1);
    float *aVec = (float*)a;
    float *bVec = (float*)b;
    return sortAlongYAxis ? (aVec[1] - bVec[1]) : (aVec[0] - bVec[0]);
}

static int sortCirclesInRowMajorOrder(const void* a, const void* b, void* userdata)     // userdata is pointer to colinearity threshold
{
    float *aVec = (float*)a;
    float *bVec = (float*)b;
    // If the Y values are approximately equal, then the wells are in the same column, so sort by x value. 
    // Otherwise we are differentiating rows. 
    return (fabsf(aVec[1] - bVec[1]) <= *(int*)userdata) ? (aVec[0] - bVec[0]) : (aVec[1] - bVec[1]);
}
