//
//  CvOrQcPlugin.m
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "CvOrQcPlugin.h"
#import "opencv2/opencv.hpp"
#import "OpenCVOutputImage.h"

@implementation CvOrQcPlugin

@dynamic inputImageA, inputImageB, outputImage;

+ (NSDictionary *)attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:@"cvOr", QCPlugInAttributeNameKey,
            @"Logically ORs two images using cvOr()", QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    NSDictionary  *dictionary = nil;
    
    if ([key isEqual:@"inputImageA"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input A", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"inputImageB"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input B", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output", QCPortAttributeNameKey, nil];
    }
    
    return dictionary;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImageA", @"inputImageB", @"outputImage", nil];
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
    id<QCPlugInInputImageSource> inputImageA = [self inputImageA];
    id<QCPlugInInputImageSource> inputImageB = [self inputImageB];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    BOOL success = [inputImageA lockBufferRepresentationWithPixelFormat:QCPlugInPixelFormatBGRA8
                                                             colorSpace:colorSpace
                                                              forBounds:[inputImageA imageBounds]];
    if (success) {
        // Create the OpenCV images
        IplImage *iplInputImageA = cvCreateImageHeader(cvSize([inputImageA bufferPixelsWide], [inputImageA bufferPixelsHigh]),
                                                       IPL_DEPTH_8U,
                                                       4);
        iplInputImageA->widthStep = [inputImageA bufferBytesPerRow];
        iplInputImageA->imageSize = [inputImageA bufferBytesPerRow] * [inputImageA bufferPixelsHigh];
        iplInputImageA->imageData = iplInputImageA->imageDataOrigin = (char *)[inputImageA bufferBaseAddress];
        
        success = [inputImageB lockBufferRepresentationWithPixelFormat:QCPlugInPixelFormatBGRA8
                                                            colorSpace:colorSpace
                                                             forBounds:[inputImageB imageBounds]];
        if (success) {
            IplImage *iplInputImageB = cvCreateImageHeader(cvSize([inputImageB bufferPixelsWide], [inputImageB bufferPixelsHigh]),
                                                           IPL_DEPTH_8U,
                                                           4);
            iplInputImageB->widthStep = [inputImageB bufferBytesPerRow];
            iplInputImageB->imageSize = [inputImageB bufferBytesPerRow] * [inputImageB bufferPixelsHigh];
            iplInputImageB->imageData = iplInputImageB->imageDataOrigin = (char *)[inputImageB bufferBaseAddress];
            
            // Perform the operation
            IplImage *product = cvCreateImage(cvGetSize(iplInputImageA), iplInputImageA->depth, iplInputImageA->nChannels);
            cvOr(iplInputImageA, iplInputImageB, product);
            [self setOutputImage:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:product]];
            
            cvReleaseImageHeader(&iplInputImageB);
            [inputImageB unlockBufferRepresentation];
        }
        
        cvReleaseImageHeader(&iplInputImageA);
        [inputImageA unlockBufferRepresentation];
    }
    CGColorSpaceRelease(colorSpace);
		
	return success;
}

@end