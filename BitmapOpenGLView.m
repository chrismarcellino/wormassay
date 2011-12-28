//
//  BitmapOpenGLView.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "BitmapOpenGLView.h"
#import <OpenGL/glu.h>

@interface BitmapOpenGLView ()

- (void)freeDrawingData;

@end


@implementation BitmapOpenGLView

+ (NSOpenGLPixelFormat *)defaultPixelFormat
{
    NSOpenGLPixelFormatAttribute attributes[] =  {
        NSOpenGLPFANoRecovery,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAColorSize, (NSOpenGLPixelFormatAttribute)24,
        NSOpenGLPFAAlphaSize, (NSOpenGLPixelFormatAttribute)8,
        NSOpenGLPFADepthSize, (NSOpenGLPixelFormatAttribute)0,
        NSOpenGLPFAStencilSize, (NSOpenGLPixelFormatAttribute)0,
        NSOpenGLPFAAccumSize, (NSOpenGLPixelFormatAttribute)0,
        NSOpenGLPFAWindow,
        (NSOpenGLPixelFormatAttribute)0
    };
    return [[[NSOpenGLPixelFormat alloc] initWithAttributes:attributes] autorelease];
}

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
    if ((self = [super initWithFrame:frameRect pixelFormat:format])) {
        [self setCanDrawConcurrently:YES];
    }
    
    return self;
}

- (void)dealloc
{
    [self freeDrawingData];
    [super dealloc];
}

- (void)prepareOpenGL
{
    CGLContextObj glContext = [[self openGLContext] CGLContextObj];
    CGLLockContext(glContext);
    
    // Turn on v-sync
    GLint value = 1;
    CGLSetParameter(glContext, kCGLCPSwapInterval, &value);
    
    // Enable non-power-of-two textures
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"Error: failed to enable GL_TEXTURE_RECTANGLE_ARB (%s)", gluErrorString(error));
    }
    
    // Create the texture
    glGenTextures(1, &_imageTexture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _imageTexture);
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
    glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
    
    CGLUnlockContext(glContext);
}

- (void)drawBitmapTexture:(BitmapDrawingData *)drawingData
{
    if (!drawingData) {
        drawingData = &_lastDrawingData;
    }
    
    CGLContextObj glContext = [[self openGLContext] CGLContextObj];
    CGLLockContext(glContext);
    CGLSetCurrentContext(glContext);
    
    if (drawingData->baseAddress) {
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _imageTexture);
        
        // If we're changing sizes or formats, we need to set the texture data anew
        if (drawingData->width != _lastDrawingData.width ||
            drawingData->height != _lastDrawingData.height ||
            drawingData->glPixelFormat != _lastDrawingData.glPixelFormat) {
            
            // Set the texture image
            glTexImage2D(GL_TEXTURE_RECTANGLE_ARB,
                         0,
                         GL_RGBA,
                         drawingData->width,
                         drawingData->height,
                         0,
                         drawingData->glPixelFormat,
                         GL_UNSIGNED_INT_8_8_8_8_REV,
                         drawingData->baseAddress);
        } else {
            // Update the existing texture image
            glTexSubImage2D(GL_TEXTURE_RECTANGLE_ARB,
                            0,
                            0,
                            0,
                            drawingData->width,
                            drawingData->height,
                            drawingData->glPixelFormat,
                            GL_UNSIGNED_INT_8_8_8_8_REV,
                            drawingData->baseAddress);
        }
        
        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();
        
        // Invert the image
        glOrtho(0, drawingData->width, drawingData->height, 0, -1, 1);
        // Set the viewport
        glViewport(_viewport.origin.x, _viewport.origin.y, _viewport.size.width, _viewport.size.height);
        
        glBegin(GL_POLYGON);
        
        glTexCoord2d(0, 0);
        glVertex2f(0, 0);
        glTexCoord2d(drawingData->width, 0);
        glVertex2f(drawingData->width, 0);
        glTexCoord2d(drawingData->width, drawingData->height);
        glVertex2f(drawingData->width, drawingData->height);
        glTexCoord2d(0, drawingData->height);
        glVertex2f(0, drawingData->height);
        
        glEnd();
        
        glPopMatrix();
        glMatrixMode(GL_MODELVIEW);
    } else {
        // Clear the framebuffer
        glClearColor(0, 0, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_ACCUM_BUFFER_BIT);
    }
    // Exchange the back buffer for the front buffer
    CGLFlushDrawable(glContext);
    
    // Save the image for redrawing if necessary and release the previous, unless we are internally performing a re-draw
    if (drawingData != &_lastDrawingData) {
        [self freeDrawingData];
        _lastDrawingData = *drawingData;
    }
    
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"Error: %@ drawing error (%s)", [self class], gluErrorString(error));
    }
    
    CGLSetCurrentContext(NULL);
    CGLUnlockContext(glContext);
}

// requires lock
- (void)freeDrawingData
{
    if (_lastDrawingData.freeCallback) {
        _lastDrawingData.freeCallback(_lastDrawingData.baseAddress, _lastDrawingData.context);
    }
    _lastDrawingData.baseAddress = _lastDrawingData.freeCallback = NULL;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [self drawBitmapTexture:NULL];
}

- (void)update
{
    CGLContextObj glContext = [[self openGLContext] CGLContextObj];
    CGLLockContext(glContext);
    
    [super update];
    
    CGLUnlockContext(glContext);
}

- (void)reshape
{
    NSOpenGLContext *context = [self openGLContext];
    CGLContextObj glContext = [context CGLContextObj];
    CGLLockContext(glContext);
    
    [super reshape];
    _viewport = [self bounds];
    [context update];
    
    CGLUnlockContext(glContext);
    
    [self setNeedsDisplay:YES];
}

@end
