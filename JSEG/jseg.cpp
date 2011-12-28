//
//  jseg.cpp
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/12/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "jseg.h"
#import "CvRectUtilities.hpp"

#import "segment.h"
#import "imgutil.h"
#import "quan.h"
#import "memutil.h"

// XXXXXXXXXXXXXXXXXXX COULD MAKE FASTER BY USING CHARS NOT FLOATS. ALSO MAKE MATRIX STUFF FAST

IplImage *createJSEGRegionMapFromImage(IplImage *image, int colorQuantizationThreshold, int numberOfScales, float regionMergeThreshold)
{
    int NX = image->width;
    int NY = image->height;
    int dim = 3;
    // Get a packed YUV 32F image
    IplImage *luvOrLumImage = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, image->nChannels == 1 ? 1 : 3);
    if (image->nChannels == 1) {
        cvConvertScale(image, luvOrLumImage);
        dim = 1;
    } else if (image->nChannels == 3) {
        IplImage *rgbFloatImage = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, 3);
        cvConvertScale(image, rgbFloatImage);
        cvCvtColor(rgbFloatImage, luvOrLumImage, CV_BGR2Luv);
        cvReleaseImage(&rgbFloatImage);
    } else {
        IplImage *rgbImage = cvCreateImage(cvGetSize(image), IPL_DEPTH_8U, 3);                              // XXXXXXXX 2nd conversion neeeded?
        cvCvtColor(image, rgbImage, CV_BGRA2BGR);
        IplImage *rgbFloatImage = cvCreateImage(cvGetSize(image), IPL_DEPTH_32F, 3);
        cvConvertScale(rgbImage, rgbFloatImage);
        cvCvtColor(rgbFloatImage, luvOrLumImage, CV_BGR2Luv);
        cvReleaseImage(&rgbFloatImage);
        cvReleaseImage(&rgbImage);
    }
    
    float **cb = (float **)fmatrix(256,dim);
    int N = quantize((float *)luvOrLumImage->imageData, cb, 1, NY, NX, dim, colorQuantizationThreshold);
    unsigned char *cmap = (unsigned char *)calloc(NY*NX, sizeof(unsigned char));
    getcmap((float *)luvOrLumImage->imageData, cmap, cb, NY*NX, dim, N);
    
    free_fmatrix(cb, 256);
    cvReleaseImage(&luvOrLumImage);
    
    IplImage *regionMap = cvCreateImage(cvGetSize(image), IPL_DEPTH_8U, 1);
    fastZeroImage(regionMap);
    int TR = segment((uint8_t *)regionMap->imageData,cmap,N,1,NY,NX,dim,numberOfScales,1);
    TR = merge1((uint8_t *)regionMap->imageData,cmap,N,1,NY,NX,TR,regionMergeThreshold);
    free(cmap);
    
    return regionMap;
}

IplImage *createSegmentEdgeMaskImageForRegionMap(IplImage *regionMap)
{
    IplImage* mask = cvCreateImage(cvGetSize(regionMap), IPL_DEPTH_8U, 1);
    fastZeroImage(mask);
    
    uint8_t* regionMapBytes = (uint8_t *)regionMap->imageData;
    uint8_t* maskBytes = (uint8_t *)mask->imageData;
    int width = regionMap->width;
    int height = regionMap->height;
    
    int l1 = 0;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width - 1; x++) {
            int l2 = l1+1;
            if (regionMapBytes[l1] != regionMapBytes[l2]) {
                maskBytes[l1] = maskBytes[l2] = 255;
            }
            l1++;
        }
        l1++;
    }
    l1 = 0;
    for (int y = 0; y < height - 1; y++) {
        for (int x = 0; x < width; x++) {
            int l2 = l1 + width;
            if (regionMapBytes[l1] != regionMapBytes[l2]) {
                maskBytes[l1] = maskBytes[l2] = 255;
            }
            l1++;
        }
    }
    
    for (int i = 0; i < height * width; i++) {
        if (regionMapBytes[i] == 0) {
            maskBytes[i] = 0;
        }
    }
    
    return mask;
}
