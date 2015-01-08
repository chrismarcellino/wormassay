//
//  VideoFrame.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "VideoFrame.h"
#import "opencv2/opencv.hpp"

static void YpCbCr422toBGRA8(uint8_t *src, uint8_t *dest, uint32_t width, uint32_t height);

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

- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer naturalSize:(NSSize)naturalSize presentationTime:(NSTimeInterval)presentationTime
{
    CVPixelBufferLockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);    
    
    OSType formatType = CVPixelBufferGetPixelFormatType(cvPixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(cvPixelBuffer);
    size_t width = CVPixelBufferGetWidth(cvPixelBuffer);
    size_t height = CVPixelBufferGetHeight(cvPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer);
    
    IplImage *iplImage = NULL;
    
    if (formatType == kCVPixelFormatType_422YpCbCr8) {
        iplImage = cvCreateImage(cvSize(width, height), IPL_DEPTH_8U, 4);   // BGRA
        YpCbCr422toBGRA8((uint8_t *)baseAddress, (uint8_t *)iplImage->imageData, width, height);
    } else if (formatType == kCVPixelFormatType_32BGRA) {
        // Create a header to hold the source image
        IplImage *iplImageHeader = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, 4);
        iplImageHeader->widthStep = bytesPerRow;
        iplImageHeader->imageSize = bytesPerRow * height;
        iplImageHeader->imageData = iplImageHeader->imageDataOrigin = (char *)baseAddress;
        
        iplImage = cvCloneImage(iplImageHeader);
        
        cvReleaseImageHeader(&iplImageHeader);
    }
    NSAssert(iplImage, @"invalid format");
    
    CVPixelBufferUnlockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Rescale the image if necessary
    if (naturalSize.width > 0 && (width != (size_t)naturalSize.width || height != (size_t)naturalSize.height)) {
        IplImage *resizedImage = cvCreateImage(cvSize(naturalSize.width, naturalSize.height), iplImage->depth, iplImage->nChannels);
        cvResize(iplImage, resizedImage, CV_INTER_AREA);
        cvReleaseImage(&iplImage);
        iplImage = resizedImage;
    }
    
    return [self initWithIplImageTakingOwnership:iplImage presentationTime:presentationTime];
}

@end


// cb and cr are - 128 here
#define YpCbCr2RGB(y, cb, cr, r, g, b)\
r = y + ((cr * 1404) >> 10);\
g = y - ((cr * 715 + cb * 344) >> 10);\
b = y + ((cb * 1774) >> 10);\
r = r < 0 ? 0 : r;\
g = g < 0 ? 0 : g;\
b = b < 0 ? 0 : b;\
r = r > 255 ? 255 : r;\
g = g > 255 ? 255 : g;\
b = b > 255 ? 255 : b

static void YpCbCr422toBGRA8(uint8_t *src, uint8_t *dest, uint32_t width, uint32_t height) {
    // Byte order UYVY
    int j = 0, i = 0;
    const int srcMax = (width * height) * 2;
    while (i < srcMax) {
        int cb = (uint8_t)src[i++] - 128;
        int y0 = (uint8_t)src[i++];
        int cr = (uint8_t)src[i++] - 128;
        int y1 = (uint8_t)src[i++];
        int r, g, b;
        YpCbCr2RGB(y1, cb, cr, r, g, b);
        dest[j++] = b;
        dest[j++] = g;
        dest[j++] = r;
        dest[j++] = 255;        // a
        YpCbCr2RGB(y0, cb, cr, r, g, b);
        dest[j++] = b;
        dest[j++] = g;
        dest[j++] = r;
        dest[j++] = 255;        // a
    }
}
