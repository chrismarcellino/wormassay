//
//  BitmapOpenGLView.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

@class VideoFrame;

// Methods are thread-safe (AppKit superclass methods are not necessarily)
@interface BitmapOpenGLView : NSOpenGLView {
    // All protected by the context lock
    VideoFrame *_lastImage;
    GLuint _imageTexture;
    NSRect _viewport;
}

- (void)renderImage:(VideoFrame *)image;

@end
