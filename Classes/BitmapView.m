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

@interface BitmapView ()

@property VideoFrame *image;

@end


@implementation BitmapView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if ((self = [super initWithFrame:frameRect])) {
        [self setCanDrawConcurrently:YES];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect      // will be called on an arbitrary thread
{
    VideoFrame *image = [self image];
    
    if (image) {
        CGContextRef context = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        CGImageRef cgImage =  [image createCGImage];
        // Draw the image into the graphics context
        CGContextDrawImage(context, [self bounds], cgImage);
        CGImageRelease(cgImage);
    } else {
        // Draw black
        [[NSColor blackColor] setFill];
        NSRectFill(dirtyRect);
    }
}

- (void)renderImage:(VideoFrame *)image
{
    [self setImage:image];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay:YES];
    });
}

@end
