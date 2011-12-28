//
//  CvNot.m
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "CvNot.h"
#import "opencv2/opencv.hpp"
#import "OpenCVOutputImage.h"

@implementation CvNot

@dynamic inputImage, outputImage;

+ (NSDictionary *)attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:@"CvNot", QCPlugInAttributeNameKey,
            @"Applies CvNot() to invert a grayscale image.", QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    NSDictionary  *dictionary = nil;
    
    if ([key isEqual:@"inputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output", QCPortAttributeNameKey, nil];
    }
    
    return dictionary;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImage", @"outputImage", nil];
}

+ (QCPlugInExecutionMode)executionMode
{
	return kQCPlugInExecutionModeProcessor;
}

+ (QCPlugInTimeMode)timeMode
{
	return kQCPlugInTimeModeNone;
}

- (BOOL)execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary *)arguments
{
    id<QCPlugInInputImageSource> inputImage = [self inputImage];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    BOOL success = [inputImage lockBufferRepresentationWithPixelFormat:QCPlugInPixelFormatBGRA8
                                                            colorSpace:colorSpace
                                                             forBounds:[inputImage imageBounds]];
    if (success) {
        // Create the OpenCV BGRA image
        IplImage *iplImage = cvCreateImageHeader(cvSize([inputImage bufferPixelsWide], [inputImage bufferPixelsHigh]),
                                                 IPL_DEPTH_8U,
                                                 4);
        iplImage->widthStep = [inputImage bufferBytesPerRow];
        iplImage->imageSize = [inputImage bufferBytesPerRow] * [inputImage bufferPixelsHigh];
        iplImage->imageData = iplImage->imageDataOrigin = (char *)[inputImage bufferBaseAddress];
        
        // Convert to grayscale
        IplImage *grayInputImage = cvCreateImage(cvGetSize(iplImage), IPL_DEPTH_8U, 1);
        cvCvtColor(iplImage, grayInputImage, CV_BGRA2GRAY);
        
        // Perform the operation
        IplImage *result = cvCreateImage(cvGetSize(grayInputImage), IPL_DEPTH_8U, 1);
        cvNot(grayInputImage, result);
        [self setOutputImage:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:result]];
        
        cvReleaseImageHeader(&iplImage);
        cvReleaseImage(&grayInputImage);
        [inputImage unlockBufferRepresentation];
    }
    CGColorSpaceRelease(colorSpace);
    
	return success;
}

@end