//
//  ImageProcessing.cpp
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ImageProcessing.hpp"
#import "opencv2/opencv.hpp"

std::vector<cv::Vec3f> findWellCircles(IplImage *inputImage, int numberOfWellsInPlate)
{
    // Conver the input image to grayscale
    IplImage *grayInputImage = cvCreateImage(cvGetSize(inputImage), IPL_DEPTH_8U, 1);
    cvCvtColor(inputImage, grayInputImage, CV_BGRA2GRAY);
    
    int smallerDimensionNumberOfWellsAcross = -1;
    switch (numberOfWellsInPlate) {
        case 6:
            smallerDimensionNumberOfWellsAcross = 2;
            break;
        case 12:
            smallerDimensionNumberOfWellsAcross = 3;
            break;
        case 24:
        default:
            smallerDimensionNumberOfWellsAcross = 4;
            break;
        case 48:
            smallerDimensionNumberOfWellsAcross = 6;            
            break;
        case 96:
            smallerDimensionNumberOfWellsAcross = 8;
            break;
    }
    int largerDimensionNumberOfWellsAcross = numberOfWellsInPlate / smallerDimensionNumberOfWellsAcross;
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
    // leaves 14% dead space on the longer axis. (A few specialty high-budget filmmaking cameras use 1:85:1 or 2.39:1,
    // but those are unlikely to be encountered and would likely work well anyhow given our large error tolerances.)
    //
    // This means that when considering maximum well dimensions, if we assume 100% coverage of the plate with wells 
    // (which is impossibly conservative), we can assume that the smaller plate dimension can fit
    // <smallerDimensionNumberOfWellsAcross> diameters of wells, or twice as many radii. Hence we have:
    // well maximum radius = <smallerImageDimension> / (2 * <smallerDimensionNumberOfWellsAcross>) * (1 + <error tolerance>),
    // where the error tolerance is at least 9%. 
    //
    // The minimum well radius can be similarly calculated, by assuming that at least half of the plates diameter correspond to
    // wells (which is a very conservative assumption for all standard plates):
    // well minimum radius = 0.5 * <largerImageDimension> / (2 * <largerDimensionNumberOfWellsAcross>) / (1 + <error tolerance>)
    // where the error tolerance is at least 14%.
    //
    // The minimum distance between well centers is just double the minimum radius calculated above, since wells cannot overlap.
    
    int maxRadius = smallerImageDimension / (2 * smallerDimensionNumberOfWellsAcross) * (1 + errorTolerance);
    int minRadius = 0.5 * largerImageDimension / (2 * largerDimensionNumberOfWellsAcross) / (1 + errorTolerance);
    
    // Find all circles using the Hough transform
    CvMemStorage* storage = cvCreateMemStorage();
    CvSeq* seq = cvHoughCircles(grayInputImage,
                                storage,
                                CV_HOUGH_GRADIENT,
                                2,      // inverse accumulator resolution ratio
                                minRadius * 2,  // min dist between centers
                                100,    // Canny high threshold
                                200,    // Accumulator threshold
                                minRadius, // min radius
                                maxRadius); // max radius
    
    vector<cv::Vec3f> circles;
    cv::Seq<cv::Vec3f>(seq).copyTo(circles);
    cvReleaseMemStorage(&storage);
    
    // XXX
    
    return circles;
}