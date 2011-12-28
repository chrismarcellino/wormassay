//
//  CvCannyQcPlugin.m
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "CvCannyQcPlugin.h"
#import "opencv2/opencv.hpp"
#import "OpenCVOutputImage.h"

@implementation CvCannyQcPlugin

@dynamic inputImage, inputLowThreshold, inputHighThreshold, inputApertureSizeIndex, inputLevel2Gradient, outputImage;

+ (NSDictionary *)attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:@"cvCanny", QCPlugInAttributeNameKey,
            @"Performs Canny Edge Filtering on a grayscale image using cvCanny()", QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    NSDictionary  *dictionary = nil;
    
    if ([key isEqual:@"inputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"inputLowThreshold"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Low Threshold", QCPortAttributeNameKey,
                      [NSNumber numberWithDouble:0.0], QCPortAttributeMinimumValueKey,
                      [NSNumber numberWithDouble:500.0], QCPortAttributeMaximumValueKey,
                      [NSNumber numberWithDouble:50.0], QCPortAttributeDefaultValueKey,
                      nil];
    } else if ([key isEqual:@"inputHighThreshold"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"High Threshold", QCPortAttributeNameKey,
                      [NSNumber numberWithDouble:0.0], QCPortAttributeMinimumValueKey,
                      [NSNumber numberWithDouble:500.0], QCPortAttributeMaximumValueKey,
                      [NSNumber numberWithDouble:100.0], QCPortAttributeDefaultValueKey,
                      nil];
    } else if ([key isEqual:@"inputApertureSizeIndex"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Aperture size", QCPortAttributeNameKey,
                      [NSNumber numberWithUnsignedInteger:2], QCPortAttributeMaximumValueKey,
                      [NSArray arrayWithObjects:@"3", @"5", @"7", nil], QCPortAttributeMenuItemsKey,
                      [NSNumber numberWithUnsignedInteger:0], QCPortAttributeDefaultValueKey,
                      nil];
    } else if ([key isEqual:@"inputLevel2Gradient"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Level 2 Gradient", QCPortAttributeNameKey,
                      [NSNumber numberWithBool:YES], QCPortAttributeDefaultValueKey,
                      nil];
    } else if ([key isEqual:@"outputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output", QCPortAttributeNameKey, nil];
    }
    
    return dictionary;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImage", @"inputLowThreshold", @"inputHighThreshold", @"inputApertureSizeIndex",
            @"inputLevel2Gradient", @"outputImage", nil];
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
        IplImage *iplInputImage = cvCreateImageHeader(cvSize([inputImage bufferPixelsWide], [inputImage bufferPixelsHigh]),
                                                      IPL_DEPTH_8U,
                                                      4);
        iplInputImage->widthStep = [inputImage bufferBytesPerRow];
        iplInputImage->imageSize = [inputImage bufferBytesPerRow] * [inputImage bufferPixelsHigh];
        iplInputImage->imageData = iplInputImage->imageDataOrigin = (char *)[inputImage bufferBaseAddress];
        
        // Convert to grayscale
        IplImage *grayInputImage = cvCreateImage(cvGetSize(iplInputImage), IPL_DEPTH_8U, 1);
        cvCvtColor(iplInputImage, grayInputImage, CV_BGRA2GRAY);
        
        // Perform the operation
        IplImage *edgeImage = cvCreateImage(cvGetSize(iplInputImage), iplInputImage->depth, 1);
        NSUInteger apertureSize = ([self inputApertureSizeIndex] * 2 + 3);
        if ([self inputLevel2Gradient]) {
            apertureSize |= CV_CANNY_L2_GRADIENT;
        }
        cvCanny(grayInputImage, edgeImage, [self inputLowThreshold], [self inputHighThreshold], apertureSize);
        [self setOutputImage:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:edgeImage]];
        
        cvReleaseImageHeader(&iplInputImage);
        cvReleaseImage(&grayInputImage);
        [inputImage unlockBufferRepresentation];
    }
    CGColorSpaceRelease(colorSpace);
		
	return success;
}

@end