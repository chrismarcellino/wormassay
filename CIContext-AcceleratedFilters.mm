//
//  CIContext-AcceleratedFilters.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/23/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "opencv2/opencv.hpp"
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

@implementation CIContext (AcceleratedFilters)

+ (CIContext *)contextForAcceleratedBitmapImageFiltering
{
    return [CIContext contextWithCGLContext:NULL pixelFormat:NULL colorSpace:NULL options:nil];
}

- (CIImage *)createCIImageWithIplImage:(IplImage*)image
{
    NSCAssert(image->nChannels == 4 && image->depth == IPL_DEPTH_8U,  @"4 channel IPL_DEPTH_8U image required");
    NSCAssert(!image->roi, @"ROI not supported");
    
    NSData *data = [[NSData alloc] initWithBytesNoCopy:image->imageData
                                                length:image->widthStep * image->height
                                          freeWhenDone:NO];
    CIImage *ciImage = [[CIImage alloc] initWithBitmapData:data
                                               bytesPerRow:image->widthStep
                                                      size:CGSizeMake(image->width, image->height)
                                                    format:kCIFormatARGB8
                                                colorSpace:NULL];
    [data release];
    return ciImage;
}

- (IplImage*)createOutputImageFromIplImage:(IplImage*)image usingCIFilterWithName:(NSString *)filterName, ...
{
    CIImage *ciImage = [self createCIImageWithIplImage:image];
    CIFilter *filter = [CIFilter filterWithName:filterName];
    [filter setValue:ciImage forKey:@"inputImage"];
    va_list args;
    va_start(args, filterName);
    while (true) {
        NSString *key = va_arg(args, NSString *);
        if (!key) {
            break;
        }
        id value = va_arg(args, id);
        [filter setValue:value forKey:key];
    }
    va_end(args);
    [ciImage release];
    
    IplImage *outputImage = cvCreateImage(cvSize(image->width, image->height), image->depth, image->nChannels);
    [self render:[filter valueForKey:@"outputImage"]
        toBitmap:outputImage->imageData
        rowBytes:outputImage->widthStep
          bounds:CGRectMake(0.0, 0.0, outputImage->width, outputImage->height)
          format:kCIFormatARGB8
      colorSpace:NULL];
    
    return outputImage;
}

// Intended to be equivalent to: cvSmooth(inputImage, outputImage, CV_GAUSSIAN, 0, 0, stddev, stddev)
- (IplImage*)createGaussianImageFromImage:(IplImage*)inputImage withStdDev:(double)stddev
{
    return [self createOutputImageFromIplImage:inputImage
                         usingCIFilterWithName:@"CIGaussianBlur", @"inputRadius", [NSNumber numberWithDouble:stddev - 1], nil];
}

@end
