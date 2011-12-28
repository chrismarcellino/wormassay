//
//  BitmapOpenGLView.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <OpenGL/gl.h>

typedef struct {
    void *baseAddress;         // packed pixels
    size_t width;
    size_t height;
    GLenum glPixelFormat;       // e.g. GL_BGRA or GL_LUMINANCE
    GLenum glPixelType;         // e.g. GL_UNSIGNED_BYTE
    void (*freeCallback)(void *baseAddress, void *context);     // May be NULL. Will be called from any thread.
    void *context;
} BitmapDrawingData;


// Methods are thread-safe (AppKit superclass methods are not necessarily)
@interface BitmapOpenGLView : NSOpenGLView {
    // All protected by the context lock
    GLuint _imageTexture;
    BitmapDrawingData _lastDrawingData;
    NSRect _viewport;
}

- (void)drawBitmapTexture:(BitmapDrawingData *)drawingData;

@end
