//
//  CvChannelSplitterQcPlugin.mm
//  TextAssist
//
//  Created by Chris Marcellino on 1/4/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "CvChannelSplitterQcPlugin.h"
#import "opencv2/opencv.hpp"
#import "OpenCVOutputImage.h"

@implementation CvChannelSplitterQcPlugin

@dynamic inputImage, outputImageR, outputImageG, outputImageB, outputImageA;

+ (NSDictionary *)attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:@"Channel Splitter", QCPlugInAttributeNameKey,
            @"Splits an image into R, G, B and A channels using cvSetImageCOI() and cvCopy()", QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary *)attributesForPropertyPortWithKey:(NSString *)key
{
    NSDictionary  *dictionary = nil;
    
    if ([key isEqual:@"inputImage"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Input", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImageR"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output R", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImageG"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output G", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImageB"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output B", QCPortAttributeNameKey, nil];
    } else if ([key isEqual:@"outputImageA"]) {
        dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Output A", QCPortAttributeNameKey, nil];
    }
    
    return dictionary;
}

+ (NSArray *)sortedPropertyPortKeys
{
    return [NSArray arrayWithObjects:@"inputImage", @"outputImageR", @"outputImageG", @"outputImageB", @"outputImageA", nil];
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
        // Create the OpenCV image
        IplImage *iplInputImage = cvCreateImageHeader(cvSize([inputImage bufferPixelsWide], [inputImage bufferPixelsHigh]),
                                                      IPL_DEPTH_8U,
                                                      4);
        iplInputImage->widthStep = [inputImage bufferBytesPerRow];
        iplInputImage->imageSize = [inputImage bufferBytesPerRow] * [inputImage bufferPixelsHigh];
        iplInputImage->imageData = iplInputImage->imageDataOrigin = (char *)[inputImage bufferBaseAddress];
        
        // Perform the operation
        IplImage* channelImages[4];
        for (int i = 0; i < 4; i++) {
            channelImages[i] = cvCreateImage(cvGetSize(iplInputImage), iplInputImage->depth, 1);
            cvSetImageCOI(iplInputImage, i + 1);
            cvCopy(iplInputImage, channelImages[i]);
            cvResetImageROI(iplInputImage);
        }
        
        [self setOutputImageB:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:channelImages[0]]];
        [self setOutputImageG:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:channelImages[1]]];
        [self setOutputImageR:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:channelImages[2]]];
        [self setOutputImageA:[OpenCVOutputImage outputImageWithIplImageAssumingOwnership:channelImages[3]]];
        
        cvReleaseImageHeader(&iplInputImage);
        [inputImage unlockBufferRepresentation];
    }
    CGColorSpaceRelease(colorSpace);
		
	return success;
}

@end