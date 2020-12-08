//
//  BitmapView.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "BitmapView.h"
#import <CoreGraphics/CoreGraphics.h>
#import <opencv2/core/core_c.h>
#import "VideoFrame.h"


@implementation BitmapView

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    
    if (_image) {
        IplImage *iplImage = [_image image];
        
        // Generate the bitmap info:
        // OpenCV uses BGRA, so tell CG to use XRGB in little endian mode to reverse it
        CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little;
        if (iplImage->nChannels == 4) {
            bitmapInfo |= kCGImageAlphaNoneSkipFirst; // can ignore the alpha channel when present since it is not used here
        } else {
            bitmapInfo |= kCGImageAlphaNone;
        }
        
        // Create the data provider (this does not retain the VideoFrame so must only be local in scope)
        CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL,
                                                                      iplImage->imageData,
                                                                      iplImage->imageSize,
                                                                      NULL);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGImageRef cgImage = CGImageCreate(iplImage->width,
                                           iplImage->height,
                                           iplImage->depth,
                                           iplImage->depth * iplImage->nChannels,
                                           iplImage->widthStep,
                                           colorSpace,
                                           bitmapInfo,
                                           dataProvider,
                                           NULL,
                                           false,
                                           kCGRenderingIntentDefault);
        
        // Draw the image into the graphics context
        CGContextDrawImage((CGContextRef)[[NSGraphicsContext currentContext] graphicsPort],
                           CGRectMake(0, 0, iplImage->width, iplImage->height),
                           cgImage);
        
        CGImageRelease(cgImage);
        CGColorSpaceRelease(colorSpace);
        CGDataProviderRelease(dataProvider);
    
    } else {
        // Draw black
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
    }
}

- (void)renderImage:(VideoFrame *)image
{
    _image = image;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay:YES];
    });
}

@end
