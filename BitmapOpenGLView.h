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
    GLenum glPixelFormat;       // e.g. GL_BGRA
    void (*freeCallback)(void *baseAddress, void *context);     // May be NULL
    void *context;
} BitmapDrawingData;


// Methods are thread-safe (superclass methods are not necessarily)
@interface BitmapOpenGLView : NSOpenGLView {
    // All protected by the context lock
    GLuint _imageTexture;
    BitmapDrawingData _lastDrawingData;
}

- (void)drawBitmapTexture:(BitmapDrawingData *)drawingData;

@end
