//
//  ImageProcessing.cpp
//  WormAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ImageProcessing.hpp"
#import "opencv2/opencv.hpp"
#import "CvRectUtilities.hpp"
#import <math.h>
#import <dispatch/dispatch.h>

#define ABS(x) ((x) > 0 ? (x) : -(x)) 

static const double MovedPixelPlateMovingProportionThreshold = 0.02;
static const double WellEdgeFindingInsetProportion = 0.7;

static const double WellFindingUnsharpMaskRadius = 6.88;
static const double WellFindingUnsharpMaskAmount = 2.812;

static bool _findWellCirclesForPlateCountUsingGrayscaleImage(IplImage* grayInputImage,
                                                             int wellCount,
                                                             std::vector<Circle> &circlesVec,
                                                             double& score,
                                                             int expectedRadius = -1);
static int meanRadiusForCvVec3fCircleSeq(CvSeq *seq);
static std::vector<Circle> convertCvVec3fSeqToCircleVector(CvSeq *seq);
static int sortCircleCentersByAxis(const void* a, const void* b, void* userdata);
static int sortCirclesInRowMajorOrder(const void* a, const void* b, void* userdata);
static inline CvRect boundingSquareForCircle(Circle circle);

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
    
    // Convert the input image to grayscale
    IplImage* grayInputImage = cvCreateImage(cvGetSize(inputImage), IPL_DEPTH_8U, 1);
    cvCvtColor(inputImage, grayInputImage, CV_BGRA2GRAY);
    
    // Iterate through all well count values
    double score = 0.0;
    bool success = false;
    IplImage *grayUnsharpMask = NULL;
    for (size_t i = 0; i < wellCounts.size(); i++) {
        if (_findWellCirclesForPlateCountUsingGrayscaleImage(grayInputImage, wellCounts[i], circles, score)) {
            success = true;
            break;
        }
        if (!grayUnsharpMask) {
            // Try again with the unsharp masked image
            IplImage *unsharpMask = createUnsharpMaskImage(inputImage, WellFindingUnsharpMaskRadius, WellFindingUnsharpMaskAmount);
            grayUnsharpMask = cvCreateImage(cvGetSize(unsharpMask), IPL_DEPTH_8U, 1);
            cvCvtColor(unsharpMask, grayUnsharpMask, CV_BGRA2GRAY);
            cvReleaseImage(&unsharpMask);
        }
        if (_findWellCirclesForPlateCountUsingGrayscaleImage(grayUnsharpMask, wellCounts[i], circles, score)) {
            success = true;
            break;
        }
    }
    
    if (grayUnsharpMask) {
        cvReleaseImage(&grayUnsharpMask);
    }
    cvReleaseImage(&grayInputImage);
    
    // Return the best circles on failure
    if (!success && score < 0.5) {
        circles.clear();
    }
    return success;
}

bool findWellCirclesForPlateCount(IplImage* inputImage, int wellCount, std::vector<Circle> &circlesVec, int expectedRadius)
{
    // Convert the input image to grayscale
    IplImage* grayInputImage = cvCreateImage(cvGetSize(inputImage), IPL_DEPTH_8U, 1);
    cvCvtColor(inputImage, grayInputImage, CV_BGRA2GRAY);
    
    double score = -1.0;
    bool result = _findWellCirclesForPlateCountUsingGrayscaleImage(grayInputImage, wellCount, circlesVec, score, expectedRadius);
    cvReleaseImage(&grayInputImage);
    
    if (!result) {
        // Try again with the unsharp masked image
        IplImage *unsharpMask = createUnsharpMaskImage(inputImage, WellFindingUnsharpMaskRadius, WellFindingUnsharpMaskAmount);
        IplImage* grayUnsharpMask = cvCreateImage(cvGetSize(unsharpMask), IPL_DEPTH_8U, 1);
        cvCvtColor(unsharpMask, grayUnsharpMask, CV_BGRA2GRAY);
        cvReleaseImage(&unsharpMask);
        
        result = _findWellCirclesForPlateCountUsingGrayscaleImage(grayUnsharpMask, wellCount, circlesVec, score, expectedRadius);
        cvReleaseImage(&grayUnsharpMask);
    }
    
    return result;
}

static bool _findWellCirclesForPlateCountUsingGrayscaleImage(IplImage* grayInputImage,
                                                             int wellCount,
                                                             std::vector<Circle> &circlesVec,
                                                             double& score,
                                                             int expectedRadius)
{
    // Determine well metrics for this plate type
    int rows, columns;
    getPlateConfigurationForWellCount(wellCount, rows, columns);
    int smallerImageDimension = MIN(grayInputImage->width, grayInputImage->height);
    int largerImageDimension = MAX(grayInputImage->width, grayInputImage->height);
    
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
    int maxRadius, minRadius;
    if (expectedRadius <= 0) {
        maxRadius = smallerImageDimension / (2.0 * rows) * (1.0 + errorTolerance);
        minRadius = 0.5 * largerImageDimension / (2.0 * columns) / (1.0 + errorTolerance);    
    } else {
        maxRadius = expectedRadius * 1.25;
        minRadius = expectedRadius / 1.25;
    }
        
    // Find all circles using the Hough transform. The seq returns contains Vec3fs, whose elements are (x-center, y-center, radius) triples.
    CvMemStorage* storage = cvCreateMemStorage();
    CvSeq* circles = cvHoughCircles(grayInputImage,
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
        int meanRadius = meanRadiusForCvVec3fCircleSeq(circles);
        for (size_t i = 0; i < circlesVec.size(); i++) {
            circlesVec[i].radius = meanRadius;
        }
    } else {
        // Otherwise if this score is higher than the existing, return all of the detected circles at this plate size for debugging
        double currentScore = MAX(1.0 - (double)abs(unfilteredCircles->total - wellCount) / wellCount, 0.0);
        if (currentScore > score) {
            score = currentScore;
            circlesVec = convertCvVec3fSeqToCircleVector(unfilteredCircles);
        }
    }
    cvReleaseMemStorage(&storage);
    
    // If we had too many circles before filtering and were unable to unable a valid filtered set, try using a tighther fit 
    // for the radius based on the average if we haven't already done so.
    if (!success && expectedRadius <= 0 && unfilteredCircles->total > wellCount) {
        success = _findWellCirclesForPlateCountUsingGrayscaleImage(grayInputImage, wellCount, circlesVec, score, meanRadiusForCvVec3fCircleSeq(unfilteredCircles));
    }
    
    return success;
}

static int meanRadiusForCvVec3fCircleSeq(CvSeq *seq)
{
    float meanRadius = 0;
    for (int i = 0; i < seq->total; i++) {
        float* current = (float*)cvGetSeqElem(seq, i);
        meanRadius += current[2];
    }
    if (seq->total > 0) {
        meanRadius /= seq->total;
    }
    return (int)meanRadius;
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

std::vector<double> calculateMovedWellFractionPerSecondForWellsFromImages(IplImage* plateImagePrev,
                                                                          IplImage* plateImageCur,
                                                                          double timeDelta,
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
            double proportion = (double)cvCountNonZero(subimage) / (M_PI * radius * radius) / timeDelta;
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
    IplImage** subimages = (IplImage* *)malloc(circles.size() * sizeof(IplImage*));
    for (size_t i = 0; i < circles.size(); i++) {
        CvRect boundingSquare = boundingSquareForCircle(circles[i]);
        
        cvSetImageROI(plateImage, boundingSquare);
        subimages[i] = cvCreateImage(cvGetSize(plateImage), IPL_DEPTH_8U, 1);
        cvCvtColor(plateImage, subimages[i], CV_BGRA2GRAY);
        cvResetImageROI(plateImage);
    }
    
    // Iterare through each well subimage in parallel
    IplImage** edges = (IplImage* *)malloc(circles.size() * sizeof(IplImage*));
    double* edgePixelPorportions = (double*)malloc(circles.size() * sizeof(double));
    dispatch_apply(circles.size(), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i){ 
        // Find edges in the image
        IplImage* cannyEdges = cvCreateImage(cvGetSize(subimages[i]), IPL_DEPTH_8U, 1);
        cvCanny(subimages[i], cannyEdges, 50, 150);
        edges[i] = cvCreateImage(cvGetSize(subimages[i]), IPL_DEPTH_8U, 1);
        
        // Mask off the edge pixels that correspond to the wells
        cvSet(cannyEdges, cvRealScalar(0), invertedCircleMask);
        
        // Dilate the edge image
        cvDilate(cannyEdges, edges[i]);
        cvReleaseImage(&cannyEdges);
        
        // Store the pixel counts
        edgePixelPorportions[i] = (double)cvCountNonZero(edges[i]) / (edges[i]->width * edges[i]->height);
    });
    
    // Iterate over each well in serial, draw debugging images and free images
    for (size_t i = 0; i < circles.size(); i++) {
        // If the edge pixel count is less than 0.5%, don't draw the noise
        if (debugImage && edgePixelPorportions[i] > 0.005) {
            CvRect boundingSquare = boundingSquareForCircle(circles[i]);
            cvSetImageROI(debugImage, boundingSquare);
            cvSet(debugImage, CV_RGBA(0, 0, 255, 255), edges[i]);
            cvResetImageROI(debugImage);
        }
        
        cvReleaseImage(&subimages[i]);
        cvReleaseImage(&edges[i]);
    }
    
    std::vector<double> vector = std::vector<double>(edgePixelPorportions, edgePixelPorportions + circles.size());
    
    free(edgePixelPorportions);
    free(subimages);
    free(edges);
    cvReleaseImage(&invertedCircleMask);
    
    return vector;
}

static inline CvRect boundingSquareForCircle(Circle circle)
{
    float radius = circle.radius;
    return cvRect(circle.center[0] - radius, circle.center[1] - radius, 2 * radius, 2 * radius);
}

CvFont fontForNormalizedScale(double normalizedScale, IplImage* image)
{
    double fontScale = MIN(image->width, image->height) / 1080.0 * normalizedScale;
    CvFont font;
    cvInitFont(&font, CV_FONT_HERSHEY_DUPLEX, fontScale, fontScale, 0, fontScale);
    return font;
}

IplImage* createUnsharpMaskImage(IplImage* image, float radius, float amount, float threshold)
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
