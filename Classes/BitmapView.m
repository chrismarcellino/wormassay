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
    if (_image) {
        CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        CGImageRef cgImage =  [_image createCGImage];
        // Draw the image into the graphics context
        CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
        CGImageRelease(cgImage);
    } else {
        // Draw black
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
    }
}

- (void)renderImage:(VideoFrame *)image
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _image = image;
        [self setNeedsDisplay:YES];
    });
}

@end
