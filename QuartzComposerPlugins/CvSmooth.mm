//
//  CvSmooth.m
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "CvSmooth.h"
#import "opencv2/opencv.hpp"
#import "OpenCVOutputImage.h"

@implementation CvSmooth

@dynamic inputImage, inputRadius, outputImage;

+ (NSDictionary *)attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:@"CvSmooth", QCPlugInAttributeNameKey,
            @"Applies CvSmooth() to blur a grayscale image using an CV_BLUR_NO_SCALE.", QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    NSDictionary  *dictionary = nil;
    
    if ([key isEqual:@"inputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"inputRadius"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Radius", QCPortAttributeNameKey,
                      [NSNumber numberWithUnsignedInteger:20], QCPortAttributeMaximumValueKey,
                      nil];
    } else if ([key isEqual:@"outputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output", QCPortAttributeNameKey, nil];
    }
    
    return dictionary;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImage", @"inputRadius", @"outputImage", nil];
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
        NSUInteger radius = ([self inputRadius] & ~1) + 1;
        cvSmooth(grayInputImage, result, CV_BLUR_NO_SCALE, radius, radius);
        [self setOutputImage:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:result]];
        
        cvReleaseImageHeader(&iplImage);
        cvReleaseImage(&grayInputImage);
        [inputImage unlockBufferRepresentation];
    }
    CGColorSpaceRelease(colorSpace);
    
	return success;
}

@end