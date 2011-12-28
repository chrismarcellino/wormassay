//
//  IplImageObject.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/10/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "IplImageObject.h"
#import "opencv2/opencv.hpp"

#define MIN_VM_COPY_SIZE (16 * PAGE_SIZE)

static inline void premultiplyImage(IplImage *img, bool reverse);

@implementation IplImageObject

@synthesize image = _image;

- (id)initWithIplImageTakingOwnership:(IplImage *)image
{
    self = [super init];
    NSAssert(self, @"allocation failure");
    NSAssert(image, @"image is required");
    _image = image;    
    return self;
}

- (void)dealloc
{
    if (_dataIfVMCopiedAttempted) {
        cvReleaseImageHeader(&_image);
        [_dataIfVMCopiedAttempted release];
    } else {
        cvReleaseImage(&_image);
    }
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    // Don't VM copy since this method is onlyr reasonably used by clients that wish to modify the resulting copy (see comments in header)
    return [[[self class] alloc] initWithIplImageTakingOwnership:cvCloneImage(_image)];
}

- (id)initByCopyingCVPixelBuffer:(CVPixelBufferRef)cvPixelBuffer resultChannelCount:(int)outChannels vmCopyIfPossible:(BOOL)attemptVmCopy
{
    CVPixelBufferLockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);    
    
    OSType formatType = CVPixelBufferGetPixelFormatType(cvPixelBuffer);
    int bufferChannels = 0;
    if (formatType == kCVPixelFormatType_8Indexed) {
        bufferChannels = 1;
    } else if (formatType == kCVPixelFormatType_24BGR) {
        bufferChannels = 3;
    } else if (formatType == kCVPixelFormatType_32BGRA) {
        bufferChannels = 4;
    } else if (formatType == kCVPixelFormatType_32ARGB) {
        bufferChannels = 4;
    }
    assert(bufferChannels > 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(cvPixelBuffer);
    size_t width = CVPixelBufferGetWidth(cvPixelBuffer);
    size_t height = CVPixelBufferGetHeight(cvPixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(cvPixelBuffer);
    
    IplImage *iplImage = NULL;
    NSData *vmCopiedData = nil;
    
    if (attemptVmCopy && outChannels == bufferChannels && bytesPerRow * height > MIN_VM_COPY_SIZE) {
        iplImage = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, outChannels);
        iplImage->widthStep = bytesPerRow;
        iplImage->imageSize = bytesPerRow * height;
        // NSData will vm_copy when possible and handle deallocation correctly. See benchmark results in this class' header file.
        vmCopiedData = [[NSData alloc] initWithBytes:baseAddress length:bytesPerRow * height];              // XXXXXXX BENCHMARK AGAINST REGULAR COPY!
        iplImage->imageData = iplImage->imageDataOrigin = (char *)[vmCopiedData bytes];
    } else {
        // Create a header to hold the source image
        IplImage *iplImageHeader = cvCreateImageHeader(cvSize(width, height), IPL_DEPTH_8U, bufferChannels);
        iplImageHeader->widthStep = bytesPerRow;
        iplImageHeader->imageSize = bytesPerRow * height;
        iplImageHeader->imageData = iplImageHeader->imageDataOrigin = (char *)baseAddress;
        
        if (outChannels == bufferChannels) {
            iplImage = cvCloneImage(iplImageHeader);
        } else {
            int conversionCode = -1;
            if (outChannels == 1 && bufferChannels == 3) {
                conversionCode = CV_BGR2GRAY;
            } else if (outChannels == 1 && bufferChannels == 4) {
                conversionCode = CV_BGRA2GRAY;
            } else if (outChannels == 3 && bufferChannels == 1) {
                conversionCode = CV_GRAY2BGR;
            } else if (outChannels == 3 && bufferChannels == 4) {
                conversionCode = CV_BGRA2BGR;
            } else if (outChannels == 4 && bufferChannels == 1) {
                conversionCode = CV_GRAY2BGRA;
            } else if (outChannels == 4 && bufferChannels == 3) {
                conversionCode = CV_BGRA2BGR;
            }
            
            iplImage = cvCreateImage(cvGetSize(iplImageHeader), IPL_DEPTH_8U, outChannels);
            cvCvtColor(iplImageHeader, iplImage, conversionCode);
        }
        cvReleaseImageHeader(&iplImageHeader);
    }
    
    CVPixelBufferUnlockBaseAddress(cvPixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    self = [self initWithIplImageTakingOwnership:iplImage];
    _dataIfVMCopiedAttempted = vmCopiedData;
    return self;
}

- (id)initByCopyingCGImage:(CGImageRef)cgImage resultChannelCount:(int)outChannels
{
    CvSize size = cvSize(CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    // CG can only write into 4 byte aligned bitmaps. We'll convert it later for 3 channels.
    IplImage *iplImage = cvCreateImage(size, IPL_DEPTH_8U, (outChannels == 3) ? 4 : outChannels);
    
    CGBitmapInfo bitmapInfo = kCGImageAlphaNone;
    if (outChannels == 3) {
        bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little;        // BGRX. CV_BGRA2BGR will discard the uninitialized alpha channel data.
    } else if (outChannels == 4) {
        bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;   // BGRA. Must unpremultiply the image.
    }
    
    CGColorSpaceRef colorSpace = (outChannels == 1) ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(iplImage->imageData,
                                                       iplImage->width,
                                                       iplImage->height,
                                                       iplImage->depth,
                                                       iplImage->widthStep,
                                                       colorSpace,
                                                       bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    
    // Copy the source bitmap into the destination, ignoring any data in the uninitialized destination
    CGContextSetBlendMode(bitmapContext, kCGBlendModeCopy);
    
    // Drawing CGImage to CGContext
    CGRect rect = CGRectMake(0.0, 0.0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
    CGContextDrawImage(bitmapContext, rect, cgImage);
    CGContextRelease(bitmapContext);
    
    // Unpremultiply the alpha channel if the source image had one (since otherwise the alphas are 1)
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(cgImage);
    if (outChannels == 4 && (alphaInfo != kCGImageAlphaNone && alphaInfo != kCGImageAlphaNoneSkipFirst && alphaInfo != kCGImageAlphaNoneSkipLast)) {
        premultiplyImage(iplImage, true);
    }
    
    // Convert BGRA images to BGR
    if (outChannels == 3) {
        IplImage *temp = cvCreateImage(cvGetSize(iplImage), IPL_DEPTH_8U, outChannels);
        cvCvtColor(iplImage, temp, CV_BGRA2BGR);
        cvReleaseImage(&iplImage);
        iplImage = temp;
    }
    
    return [self initWithIplImageTakingOwnership:iplImage];
}

static inline void premultiplyImage(IplImage *img, bool reverse)
{
    assert(img->depth == IPL_DEPTH_8U);
    uchar *row = (uchar *)img->imageData;
    
    for (int i = 0; i < img->height; i++) {
        for (int j = 0; j < img->width; j+= img->nChannels) {
            uchar alpha = row[j + 3];
            if (alpha != UCHAR_MAX && (!reverse || alpha != 0)) {
                for (int k = 0; k < 3; k++) {
                    if (reverse) {
                        row[j + k] = ((int)row[j + k] * UCHAR_MAX + alpha / 2 - 1) / alpha;
                    } else {
                        row[j + k] = ((int)row[j + k] * alpha + UCHAR_MAX / 2 - 1) / UCHAR_MAX;
                    }
                }
            }
        }
        row += img->widthStep;
    }
}

@end