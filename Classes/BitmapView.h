//
//  BitmapView.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <AppKit/AppKit.h>

@class VideoFrame;

@interface BitmapView : NSView {
    VideoFrame *_image;
}

- (void)renderImage:(VideoFrame *)image;    // thread-safe

@end
