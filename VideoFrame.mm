//
//  VideoFrame.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "VideoFrame.h"
#import "opencv2/opencv.hpp"

@implementation VideoFrame

@synthesize image = _image;
@synthesize presentationTime = _presentationTime;

- (id)initWithIplImageTakingOwnership:(IplImage *)image presentationTime:(NSTimeInterval)presentationTime
{
    if ((self = [super init])) {
        NSAssert(image, @"image is required");
        _image = image;
        _presentationTime = presentationTime;
    }
    return self;
}

- (void)dealloc
{
    cvReleaseImage(&_image);
}

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] alloc] initWithIplImageTakingOwnership:cvCloneImage(_image) presentationTime:_presentationTime];
}

- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer presentationTime:(NSTimeInterval)presentationTime
{
    CVPixelBufferLockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);    
    
    OSType formatType = CVPixelBufferGetPixelFormatType(cvPixelBuffer);
    // determine input buffer channels/bpp
    int inBufferChannels = 0;
    int conversionCode = -1;
    
    if (formatType == kCVPixelFormatType_8Indexed) {
        inBufferChannels = 1;
        conversionCode = CV_GRAY2BGRA;
    } else if (formatType == kCVPixelFormatType_24BGR) {
        inBufferChannels = 3;
        conversionCode = CV_BGR2BGRA;
    } else if (formatType == kCVPixelFormatType_32BGRA) {
        inBufferChannels = 4;
        conversionCode = -1;    // no conversion needed, already BGRA
    }
    NSAssert(inBufferChannels > 0, @"unsupported format");
    
    void *baseAddress = CVPixelBufferGetBaseAddress(cvPixelBuffer);
    size_t width = CVPixelBufferGetWidth(cvPixelBuffer);
    size_t height = CVPixelBufferGetHeight(cvPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer);
    
    IplImage *iplImage = NULL;
    
    // Create a header to hold the source image
    IplImage *iplImageHeader = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, inBufferChannels);
    iplImageHeader->widthStep = bytesPerRow;
    iplImageHeader->imageSize = bytesPerRow * height;
    iplImageHeader->imageData = iplImageHeader->imageDataOrigin = (char *)baseAddress;
    
    if (conversionCode == -1) {
        iplImage = cvCloneImage(iplImageHeader);
    } else {
        iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, 4);       // BGRA
        cvCvtColor(iplImageHeader, iplImage, conversionCode);
    }
    cvReleaseImageHeader(&iplImageHeader);
    
    CVPixelBufferUnlockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    return [self initWithIplImageTakingOwnership:iplImage presentationTime:presentationTime];
}

@end
