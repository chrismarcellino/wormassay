//
//  OpenCVOutputImage.m
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "OpenCVOutputImage.h"


@implementation OpenCVOutputImage

+ (OpenCVOutputImage *)outputImageWithIplImageAssumingOwnership:(IplImage *)image
{
    return [[[self alloc] initWithIplImageAssumingOwnership:image] autorelease];
}

- (id)initWithIplImageAssumingOwnership:(IplImage *)image
{
    if ((self = [super init])) {
        iplImage = image;       // ownership assumed
    }
    return self;
}

- (void)dealloc
{
    cvReleaseImage(&iplImage);
    [super dealloc];
}

- (void)finalize
{
    cvReleaseImage(&iplImage);
    [super finalize];
}

- (NSRect)imageBounds
{
    return NSMakeRect(0.0, 0.0, iplImage->width, iplImage->height);
}

- (CGColorSpaceRef)imageColorSpace
{
    return (CGColorSpaceRef)[NSMakeCollectable(CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB)) autorelease];
}

- (NSArray *)supportedBufferPixelFormats
{
    return [NSArray arrayWithObjects:QCPlugInPixelFormatBGRA8, QCPlugInPixelFormatI8, nil];
}

- (BOOL)renderToBuffer:(void *)baseAddress withBytesPerRow:(NSUInteger)rowBytes pixelFormat:(NSString *)format forBounds:(NSRect)bounds
{
    BOOL success = YES;
    
    int imageChannels = iplImage->nChannels;
    int bufferChannels = [format isEqual:QCPlugInPixelFormatBGRA8] ? 4 : 1;
    cvSetImageROI(iplImage, cvRect(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height));
    IplImage *bufferHeader = cvCreateImageHeader(cvGetSize(iplImage), IPL_DEPTH_8U, bufferChannels);
    bufferHeader->widthStep = rowBytes;
    bufferHeader->imageSize = rowBytes * bounds.size.width;
    bufferHeader->imageData = bufferHeader->imageDataOrigin = (char *)baseAddress;
    
    if (imageChannels == bufferChannels) {
        cvCopy(iplImage, bufferHeader);
    } else if (imageChannels == 1 && bufferChannels == 3) {
        cvCvtColor(iplImage, bufferHeader, CV_GRAY2BGR);
    } else if (imageChannels == 1 && bufferChannels == 4) {
        cvCvtColor(iplImage, bufferHeader, CV_GRAY2BGRA);
    } else if (imageChannels == 3 && bufferChannels == 1) {
        cvCvtColor(iplImage, bufferHeader, CV_BGR2GRAY);
    } else if (imageChannels == 3 && bufferChannels == 4) {
        cvCvtColor(iplImage, bufferHeader, CV_BGR2BGRA);
    } else if (imageChannels == 4 && bufferChannels == 1) {
        cvCvtColor(iplImage, bufferHeader, CV_BGRA2GRAY);
    } else if (imageChannels == 4 && bufferChannels == 3) {
        cvCvtColor(iplImage, bufferHeader, CV_BGRA2BGR);
    } else {
        success = NO;
    }
    
    cvReleaseImageHeader(&bufferHeader);
    cvResetImageROI(iplImage);
    
    return success;
}

@end
