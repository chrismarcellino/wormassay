//
//  WellFinding.cpp
//  WormAssay
//
//  Created by Chris Marcellino on 4/18/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "WellFinding.hpp"
#import "MotionAnalysis.hpp"
#import "opencv2/opencv.hpp"
#import "CvUtilities.hpp"
#import <math.h>
#import <dispatch/dispatch.h>


static bool findWellCirclesForWellCounts(IplImage* inputImage,
                                         std::vector<int> wellCounts,
                                         std::vector<Circle> &circles,
                                         int expectedRadius = -1);

static bool findWellCirclesForWellCountsUsingImage(IplImage* image,
                                                   const std::vector<int> &wellCounts,
                                                   std::vector<Circle> *circles,
                                                   double *score,
                                                   int expectedRadius);

static bool findWellCirclesForWellCountUsingImage(IplImage* image,
                                                  int wellCount,
                                                  std::vector<Circle> &circlesVec,
                                                  double& score,
                                                  int expectedRadius);

static std::vector<Circle> convertCvVec3fSeqToCircleVector(CvSeq *seq);
static int sortCircleCentersByAxis(const void* a, const void* b, void* userdata);
static int sortCirclesInRowMajorOrder(const void* a, const void* b, void* userdata);
static float meanRadiusForCircles(const std::vector<Circle> &circles);

static IplImage* createUnsharpMaskImage(IplImage* image, float radius, float amount, float threshold = 0.0);

// Sorted by prevalence
std::vector<int> knownPlateWellCounts()
{
    int counts[] = { 96, 48, 24, 12, 6 };
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

bool findWellCircles(IplImage* inputImage, std::vector<Circle> &circles, int wellCountHint)
{
    // Create the array of counts that we will try in order, but move the hinted value to the front
    std::vector<int> wellCounts = knownPlateWellCounts();
    if (wellCountHint > 0) {
        for (size_t i = 0; i < wellCounts.size(); i++) {
            if (wellCounts[i] == wellCountHint) {
                wellCounts.erase(wellCounts.begin() + i);
                break;
            }
        }
        wellCounts.insert(wellCounts.begin(), wellCountHint);
    }
    
    return findWellCirclesForWellCounts(inputImage, wellCounts, circles);
}

bool findWellCirclesForWellCount(IplImage* inputImage, int wellCount, std::vector<Circle> &circlesVec, int expectedRadius)
{
    return findWellCirclesForWellCounts(inputImage, std::vector<int>(1, wellCount), circlesVec, expectedRadius);
}

static bool findWellCirclesForWellCounts(IplImage* inputImage,
                                  std::vector<int> wellCounts,
                                  std::vector<Circle> &circles,
                                  int expectedRadius)
{
    // Only report failed circle sets if they are not too noisy
    double score = 0.5;
    
    // Convert the input image to grayscale
    IplImage* grayscaleImage = cvCreateImage(cvGetSize(inputImage), IPL_DEPTH_8U, 1);
    cvCvtColor(inputImage, grayscaleImage, CV_BGRA2GRAY);
    bool success = findWellCirclesForWellCountsUsingImage(grayscaleImage, wellCounts, &circles, &score, expectedRadius);
    
    // If not found and we didn't have an expected radius, try again but seed with the mean radius of the wells that were found.
    if (!success && expectedRadius == 0) {
        int meanRadiusFound = (int)meanRadiusForCircles(circles);
        if (meanRadiusFound > 0) {
            success = findWellCirclesForWellCountsUsingImage(grayscaleImage, wellCounts, &circles, &score, meanRadiusFound);
        }
    }
    cvReleaseImage(&grayscaleImage);
    
    // If not found, try again with the unsharp masked image, creating it if necessary. The caller will free the image.
    if (!success) {
        IplImage* unsharpMask = createUnsharpMaskImage(inputImage, 7.0, 3.0);
        IplImage* grayscaleUnsharpMaskImage = cvCreateImage(cvGetSize(unsharpMask), IPL_DEPTH_8U, 1);
        cvCvtColor(unsharpMask, grayscaleUnsharpMaskImage, CV_BGRA2GRAY);
        cvReleaseImage(&unsharpMask);
        
        success = findWellCirclesForWellCountsUsingImage(grayscaleUnsharpMaskImage, wellCounts, &circles, &score, expectedRadius);
        if (!success && expectedRadius == 0) {
            int meanRadiusFound = (int)meanRadiusForCircles(circles);
            if (meanRadiusFound > 0) {
                success = findWellCirclesForWellCountsUsingImage(grayscaleUnsharpMaskImage, wellCounts, &circles, &score, meanRadiusFound);
            }
        }
        cvReleaseImage(&grayscaleUnsharpMaskImage);
    }
    
    return success;
}

static bool findWellCirclesForWellCountsUsingImage(IplImage* image,
                                                   const std::vector<int> &wellCounts,
                                                   std::vector<Circle> *circles,
                                                   double *score,           // reads and writes
                                                   int expectedRadius)
{
    __block bool success = false;
    
    // Execute searches for different plate sizes in parallel
    dispatch_queue_t criticalSection = dispatch_queue_create(NULL, NULL);
    dispatch_apply(wellCounts.size(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){
        std::vector<Circle> currentCircles;
        double currentScore;
        bool currentSuccess = findWellCirclesForWellCountUsingImage(image, wellCounts[i], currentCircles, currentScore, expectedRadius);
        
        dispatch_sync(criticalSection, ^{
            if (!success && (currentSuccess || currentScore > *score)) {
                success = currentSuccess;
                *score = currentScore;
                *circles = currentCircles;
            }
        });
    });
    dispatch_release(criticalSection);
    
    return success;
}

static bool findWellCirclesForWellCountUsingImage(IplImage* image,
                                                  int wellCount,
                                                  std::vector<Circle> &circlesVec,
                                                  double& score,
                                                  int expectedRadius)
{
    // Determine well metrics for this plate type
    int rows, columns;
    getPlateConfigurationForWellCount(wellCount, rows, columns);
    int smallerImageDimension = MIN(image->width, image->height);
    int largerImageDimension = MAX(image->width, image->height);
    
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
    // The minimum well radius can be similarly calculated, by assuming that at least 50% of the plates diameter correspond to
    // wells (which is a very conservative assumption for all standard plates), and that a plate fills half the frame:
    // well minimum radius = 0.5 * <largerImageDimension> / (2 * <columns>) / (1 + <error tolerance>)
    // where the error tolerance is at least 14%.
    //
    // The minimum distance between well centers is just double the minimum radius calculated above, since wells cannot overlap.
    double errorTolerance = 0.20;      // 20%, see above
    int maxRadius = smallerImageDimension / (2.0 * rows) * (1.0 + errorTolerance);
    int minRadius = 0.5 * largerImageDimension / (2.0 * columns) / (1.0 + errorTolerance);
    
    // If provided an expected radius, use it to constrain the radius size
    if (expectedRadius > 0) {
        maxRadius = MIN(expectedRadius * 1.25, maxRadius);
        minRadius = MAX(expectedRadius / 1.25, minRadius);
    }
    
    // Find all circles using the Hough transform. The seq returns contains Vec3fs, whose elements are (x-center, y-center, radius) triples.
    CvMemStorage* storage = cvCreateMemStorage();
    CvSeq* circles = cvHoughCircles(image,
                                    storage,
                                    CV_HOUGH_GRADIENT,
                                    2,      // inverse accumulator resolution ratio
                                    minRadius * 2,  // min dist between centers
                                    200,    // Canny high threshold
                                    200,    // Accumulator threshold
                                    minRadius, // min radius
                                    maxRadius); // max radius
    CvSeq* unfilteredCircles = circles;
    
    // Take the set of all circles whose centers are approximately colinear with other circles along axis aligned lines
    // in both dimensions. Discard all others.
    int colinearityThreshold = maxRadius / 2;
    
    // Do two passes so that we only start filtering entire rows once we've filtered out spurious circles
    for (int pass = 0; pass < 2; pass++) {
        // First sort the centers by X value so that lines vertically colinear are adjacent in the seq. Next do the opposite. 
        for (int axis = 0; axis <= 1; axis++) {
            cvSeqSort(circles, sortCircleCentersByAxis, &axis);
            
            // Iterate through list and move circles colinear along Y lines to a new seq, and hence have similar X values (and then vice versa)
            CvSeq* colinearCircles = cvCreateSeq(CV_32FC3, sizeof(CvSeq), 3 * sizeof(float), storage);
            
            // Iterate through the current list
            for (int i = 0; i < circles->total; i++) {
                float* current = (float*)cvGetSeqElem(circles, i);
                
                // Iterate along a colinear line
                int numberOfColinearCircles = 0;
                for (int j = i + 1; j < circles->total; j++) {
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
                        // Advanced current so we tolerate plates that are not perfectly axis alligned
                        current = partner;
                    } else {
                        break;
                    }
                }
                
                // On the second pass, determine if we saw as many colinear circles as we expected and if not, pop what we just pushed
                if (pass >= 1 && numberOfColinearCircles != (axis == 1 ? columns : rows)) {
                    cvSeqPopMulti(colinearCircles, NULL, numberOfColinearCircles);
                }
            }
            
            circles = colinearCircles;
        }
    }
    
    // Determine if this is a valid plate
    bool success = circles->total == wellCount;
    if (success) {
        // If successful, sort the circles in row major order
        cvSeqSort(circles, sortCirclesInRowMajorOrder, &colinearityThreshold);        
        circlesVec = convertCvVec3fSeqToCircleVector(circles);
        
        // Set the wells' area to be the mean under the assumption that there is no perspective distortion
        int meanRadius = (int)meanRadiusForCircles(circlesVec);
        for (size_t i = 0; i < circlesVec.size(); i++) {
            circlesVec[i].radius = meanRadius;
        }
    } else {
        // Otherwise return all of the detected circles at this plate size for debugging
        score = MAX(1.0 - (double)abs(unfilteredCircles->total - wellCount) / wellCount, 0.0);
        circlesVec = convertCvVec3fSeqToCircleVector(unfilteredCircles);
    }
    cvReleaseMemStorage(&storage);
    
    return success;
}

static std::vector<Circle> convertCvVec3fSeqToCircleVector(CvSeq *seq)
{
    std::vector<Circle> vector;
    vector.reserve(seq->total);
    
    for (int i = 0; i < seq->total; i++) {
        float* current = (float*)cvGetSeqElem(seq, i);
        Circle circle = { { current[0], current[1] }, current[2] };
        vector.push_back(circle);
    }
    return vector;
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

static float meanRadiusForCircles(const std::vector<Circle> &circles)
{
    float meanRadius = 0;
    for (size_t i = 0; i < circles.size(); i++) {
        meanRadius += circles[i].radius;
    }
    if (circles.size() > 0) {
        meanRadius /= circles.size();
    }
    return meanRadius;
}

CvPoint plateCenterForWellCircles(const std::vector<Circle> &circles)
{
    CvPoint average = cvPoint(0,0);
    for (size_t i = 0; i < circles.size(); i++) {
        average.x += circles[i].center[0];
        average.y += circles[i].center[1];
    }
    
    if (circles.size() > 0) {
        average.x /= circles.size();
        average.y /= circles.size();
    }
    return average;
}

bool plateSequentialCirclesAppearSameAndStationary(const std::vector<Circle> &circlesPrevious,
                                                   const std::vector<Circle> &circlesCurrent)
{
    // Return false if the number of circles have changed
    if (circlesPrevious.size() != circlesCurrent.size() || circlesPrevious.size() == 0 || circlesCurrent.size() == 0) {
        return false;
    }
    
    // Return false if the radius has changed signifigantly
    float radiusPrevious = circlesPrevious[0].radius;
    float radiusCurrent = circlesCurrent[0].radius;
    float radiusRatio = radiusPrevious / radiusCurrent;
    if (radiusRatio > 1.1 || radiusRatio < 0.9) {
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

static IplImage* createUnsharpMaskImage(IplImage* image, float radius, float amount, float threshold)
{
    IplImage* source = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, image->nChannels);
    cvConvert(image, source);
    IplImage* gaussian = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, image->nChannels);
    
    int stddev = radius + 1.0;
    int kernelSize = lroundf(4 * (stddev + 1));
    if (kernelSize % 2 == 0) {
        kernelSize++;
    }
    cvSmooth(source, gaussian, CV_GAUSSIAN, kernelSize, kernelSize, stddev, stddev);
    
    IplImage* resultFloat = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, image->nChannels);
    cvAddWeighted(source, 1.0 + amount, gaussian, -amount, 0.0, resultFloat);
    
    cvReleaseImage(&gaussian);
    cvReleaseImage(&source);
    
    IplImage* result = cvCreateImage(cvGetSize(image), image->depth, image->nChannels);
    cvConvert(resultFloat, result);
    cvReleaseImage(&resultFloat);
    return result;
}

void drawWellCirclesAndLabelsOnDebugImage(std::vector<Circle> circles, CvScalar circleColor, bool drawLabels, IplImage* debugImage)
{
    CvFont wellFont = fontForNormalizedScale(1.0, debugImage);
    
    for (size_t i = 0; i < circles.size(); i++) {
        CvPoint center = cvPoint(circles[i].center[0], circles[i].center[1]);
        int radius = circles[i].radius;
        
        // Draw the circle outline
        cvCircle(debugImage, center, radius, circleColor, 3, 8, 0);
        
        // Draw the well labels
        if (drawLabels) {
            CvPoint textPoint = cvPoint(center.x - radius, center.y - 0.9 * radius);
            cvPutText(debugImage,
                      wellIdentifierStringForIndex(i, circles.size()).c_str(),
                      textPoint,
                      &wellFont,
                      CV_RGBA(0, 255, 255, 255));
        }
    }
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
