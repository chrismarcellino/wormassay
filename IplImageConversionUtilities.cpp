//
//  IplImageConversionUtilities.cpp
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "IplImageConversionUtilities.hpp"

static void releaseImage(void *info, const void *data, size_t size);


IplImage *CreateIplImageFromCVPixelBuffer(CVPixelBufferRef cvImageBuffer, int outChannels)
{
    CVPixelBufferLockBaseAddress(cvImageBuffer, kCVPixelBufferLock_ReadOnly);    
    
    OSType formatType = CVPixelBufferGetPixelFormatType(cvImageBuffer);
    int bufferChannels = 0;
    if (formatType == kCVPixelFormatType_8Indexed) {
        bufferChannels = 1;
    } else if (formatType == kCVPixelFormatType_24BGR) {
        bufferChannels = 3;
    } else if (formatType == kCVPixelFormatType_32BGRA) {
        bufferChannels = 4;
    }
    assert(bufferChannels > 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(cvImageBuffer);
    size_t width = CVPixelBufferGetWidth(cvImageBuffer);
    size_t height = CVPixelBufferGetHeight(cvImageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvImageBuffer);
    
    IplImage *iplImageHeader = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, bufferChannels);
    iplImageHeader->widthStep = bytesPerRow;
    iplImageHeader->imageSize = bytesPerRow * height;
    iplImageHeader->imageData = iplImage->imageDataOrigin = (char *)baseAddress;
    
    IplImage *iplImage = NULL;
    if (outChannels == bufferChannels) {
        iplImage = cvCloneImage(iplImageHeader);
    } else if (outChannels == 1 && bufferChannels == 3) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 1);
        cvCvtColor(iplImageHeader, iplImage, CV_BGR2GRAY);
    } else if (outChannels == 1 && bufferChannels == 4) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 1);
        cvCvtColor(iplImageHeader, iplImage, CV_BGRA2GRAY);
    } else if (outChannels == 3 && bufferChannels == 1) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 3);
        cvCvtColor(iplImageHeader, iplImage, CV_GRAY2BGR);
    } else if (outChannels == 3 && bufferChannels == 4) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 3);
        cvCvtColor(iplImageHeader, iplImage, CV_BGRA2BGR);
    } else if (outChannels == 4 && bufferChannels == 1) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 4);
        cvCvtColor(iplImageHeader, iplImage, CV_GRAY2BGRA);
    } else if (outChannels == 4 && bufferChannels == 3) {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 4);
        cvCvtColor(iplImageHeader, iplImage, CV_BGRA2BGR);
    }
    cvReleaseImageHeader(iplImageHeader);
    
    CVPixelBufferUnlockBaseAddress(cvImageBuffer, kCVPixelBufferLock_ReadOnly);
    
    return iplImage;
}

CGImageRef CreateCGImageFromIplImage(IplImage *iplImage)
{
    return CreateCGImageFromIplImagePassingOwnership(iplImage, false);
}

CGImageRef CreateCGImageFromIplImagePassingOwnership(IplImage *iplImage, bool passOwnership)
{
    if (!passOwnership) {
        iplImage = cvCloneImage(iplImage);
    }
    
    CGDataProviderRef provider = CGDataProviderCreateWithData(iplImage, iplImage->imageData, iplImage->imageSize, releaseImage);
    
    CGBitmapInfo bitmapInfo = (iplImage->nChannels == 4) ? (kCGImageAlphaFirst | kCGBitmapByteOrder32Little) : kCGImageAlphaNone;
    CGColorSpaceRef colorSpace = (iplImage->nChannels == 1) ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();    
    CGImageRef cgImage = CGImageCreate(iplImage->width,
                                       iplImage->height,
                                       iplImage->depth,
                                       iplImage->depth * iplImage->nChannels,
                                       iplImage->widthStep,
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       false,
                                       kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    return cgImage;
}

static void releaseImage(void *info, const void *data, size_t size)
{
    IplImage *image = (IplImage *)info;
    cvReleaseImage(&image);
}
