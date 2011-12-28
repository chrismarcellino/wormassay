//
//  ImageProcessing.cpp
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ImageProcessing.hpp"
#import "opencv2/opencv.hpp"
#import "CvRectUtilities.hpp"
#import <math.h>

static int sortCircleCentersByAxis(const void* a, const void* b, void* userdata);
static int sortCirclesInRowMajorOrder(const void* a, const void* b, void* userdata);

// Sorted by prevalence
std::vector<int> knownPlateWellCounts()
{
    int counts[] = { 96, 24, 48, 12, 6 };
    return std::vector<int>(counts, counts + sizeof(counts)/sizeof(*counts));
}

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

std::string wellIdentifierStringForIndex(int index, int wellCount)
{
    int rows, columns;
    getPlateConfigurationForWellCount(wellCount, rows, columns);
    
    std::stringstream ss;
    ss << (char)('A' + index / columns);
    ss << 1 + index % columns;
    
    std::string str;
    ss >> str;
    return str;
}

bool findWellCircles(IplImage *inputImage, std::vector<cv::Vec3f> &circles, int wellCountHint)
{
    std::vector<int> wellCounts = knownPlateWellCounts();
    if (wellCountHint > 0) {
        for (int i = 0; i < wellCounts.size(); i++) {
            if (wellCounts[i] == wellCountHint) {
                wellCounts.erase(wellCounts.begin() + i);
                break;
            }
        }
        wellCounts.insert(wellCounts.begin(), wellCountHint);
    }
    
    float bestScore = -1.0;
    float score;
    std::vector<cv::Vec3f> bestCircles;
    
    for (int i = 0; i < wellCounts.size(); i++) {
        if (findWellCirclesForPlateCount(inputImage, wellCounts[i], circles, score)) {
            return true;
        }
        
        // Save the best scoring circles for debugging purposes
        if (score > bestScore) {
            bestScore = score;
            bestCircles = circles;
        }
        
        // Clear to try again
        circles.clear();
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
    bool allColinearCirclesFound = true;
    
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
                allColinearCirclesFound = false;
            }
        }
        
        circles = colinearCircles;
    }
    
    // Sort the circles in row major order
    cvSeqSort(circles, sortCirclesInRowMajorOrder, &colinearityThreshold);
    
    cv::Seq<cv::Vec3f>(circles).copyTo(circlesVec);
    cvReleaseMemStorage(&storage);
    
    // Determine if this is a valid plate and provide scores for debugging
    bool success = circles->total == wellCount && allColinearCirclesFound;
    score = MAX(1.0 - (float)abs(circles->total - wellCount) / wellCount, 0.0) - (allColinearCirclesFound ? 0.0 : 1.0);
    
    if (success) {
    // Set the wells' area to be the mean under the assumption that there is no perspective distortion
        int sum = 0;
        for (int i = 0; i < circlesVec.size(); i++) {
            sum += circlesVec[i][2];
        }
        sum /= wellCount;
        for (int i = 0; i < circlesVec.size(); i++) {
            circlesVec[i][2] = sum;
        }
    }
        
    return success;
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

CvPoint plateCenterForWellCircles(const std::vector<cv::Vec3f> &circles)
{
    CvPoint average = cvPoint(0,0);
    for (int i = 0; i < circles.size(); i++) {
        average.x += circles[i][0];
        average.y += circles[i][1];
    }
    
    if (circles.size() > 0) {
        average.x /= circles.size();
        average.y /= circles.size();
    }
    return average;
}

bool plateSequentialCirclesAppearSameAndStationary(const std::vector<cv::Vec3f> &circlesPrevious,
                                                   const std::vector<cv::Vec3f> &circlesCurrent)
{
    // Return false if the number of circles have changed
    if (circlesPrevious.size() != circlesCurrent.size() || circlesPrevious.size() == 0 || circlesCurrent.size() == 0) {
        return false;
    }
    
    // Return false if the radius has changed signifigantly
    float radiusPrevious = circlesPrevious[0][2];
    float radiusCurrent = circlesCurrent[0][2];
    float radiusRatio = radiusPrevious / radiusCurrent;
    if (radiusRatio > 1.25 || radiusRatio < 0.8) {
        return false;
    }
    
    // Return false if the center of the plate has moved more than the (mean radius) / 10 pxiels.
    // This is a useful comparison as the average position of all circles have relatively little variance, as where each
    // individual well has much more noise.
    CvPoint centerPrevious = plateCenterForWellCircles(circlesPrevious);
    CvPoint centerCurrent = plateCenterForWellCircles(circlesCurrent);
    float deltaX = centerPrevious.x - centerCurrent.x;
    float deltaY = centerPrevious.y - centerCurrent.y;
    float distance = sqrtf(deltaX * deltaX + deltaY * deltaY);
    return distance < (radiusPrevious + radiusCurrent) / 2.0 / 10.0;
}

IplImage *createEdgeImageForWellImageFromImage(IplImage *plateImage, cv::Vec3f wellCircle, float &filledArea, IplImage *debugImage)
{
    // Copy the grayscale subimage corresponding to the circle's bounding square
    float radius = wellCircle[2];
    CvRect boundingSquare = cvRect(wellCircle[0] - radius, wellCircle[1] - radius, 2 * radius, 2 * radius);
    
    cvSetImageROI(plateImage, boundingSquare);
    IplImage* graySubimage = cvCreateImage(cvGetSize(plateImage), IPL_DEPTH_8U, 1);
    cvCvtColor(plateImage, graySubimage, (plateImage->nChannels == 3) ? CV_BGR2GRAY : CV_BGRA2GRAY);
    cvResetImageROI(plateImage);
    
    // Create a circle mask with 255's in the circle
    IplImage *circleMask = cvCreateImage(cvGetSize(graySubimage), IPL_DEPTH_8U, 1);
    fastFillImage(circleMask, 255);
    cvCircle(circleMask, cvPoint(radius, radius), radius, cvRealScalar(0), CV_FILLED);
    
    // Mask the plate image, turning pixels outside the circle black
    cvSet(graySubimage, cvRealScalar(0), circleMask);
    
    // Find edges in the image
    IplImage* edges = cvCreateImage(cvGetSize(graySubimage), IPL_DEPTH_8U, 1);
    cvCanny(graySubimage, edges, 50, 100);
    
    /// XXXX FIND CONNECTED IMAGES
    
    // Draw onto the debugging image
    cvSetImageROI(debugImage, boundingSquare);
    cvCvtColor(edges, debugImage, CV_GRAY2BGRA);
    cvResetImageROI(debugImage);
    
    
//    cvReleaseImage(&edges);
    cvReleaseImage(&circleMask);
    cvReleaseImage(&graySubimage);
    
    return edges;
}

float getMotionDeltaBetweenEdgeFrames(IplImage *previousFrame, IplImage *currentFrame)
{
    return 0.0;     ///XXXXXXXXXXXXXXXX TODO
}
