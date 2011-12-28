//
//  BitmapOpenGLView.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "BitmapOpenGLView.h"


@implementation BitmapOpenGLView

// PERF DIFFERENCE??????
/*+ (NSOpenGLPixelFormat *)defaultPixelFormat
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
}*/

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
    if ((self = [super initWithFrame:frameRect pixelFormat:format])) {
        [self setCanDrawConcurrently:YES];
    }
    
    return self;
}

- (void)dealloc
{

    [super dealloc];
}

- (void)prepareOpenGL
{
    GLint value = 1;
    [[self openGLContext] setValues:&value forParameter:NSOpenGLCPSwapInterval];
    
    // Enable non-POT textures
    glEnable(GL_TEXTURE_RECTANGLE_ARB);
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"Error: failed to enable GL_TEXTURE_RECTANGLE_ARB (%i)", error);
    }
    
    // Create the texture
    glGenTextures(1, &_imageTexture);
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _imageTexture);     // XXX ONE OF THESE CALLS ISNT NEEDED????
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
    glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
}

- (void)drawBitmapTexture:(BitmapDrawingData *)drawingData
{
    if (!drawingData) {
        drawingData = &_lastDrawingData;
    }
    
    NSOpenGLContext *context = [self openGLContext];
    CGLContextObj glContext = [context CGLContextObj];
    CGLLockContext(glContext);
    
    [context makeCurrentContext];
    
    glBindTexture(GL_TEXTURE_RECTANGLE_ARB, _imageTexture);
    
    if (drawingData->width != _lastDrawingData.width ||
        drawingData->height != _lastDrawingData.height ||
        drawingData->glPixelFormat != _lastDrawingData.glPixelFormat) {
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
    
    glOrtho(0, drawingData->width, drawingData->height, 0, -1, 1);
    glViewport(0, 0, drawingData->width, drawingData->height);
//    glRotatef(angle * 180.0 / M_PI, 0, 0, -1);
//    glScalef(scale, scale, 0);
    
    glBegin(GL_POLYGON);
    
    glTexCoord2d(0, 0);
    glVertex2f(0, 0);
    
    glTexCoord2d(drawingData->width, 0);
    glVertex2f(drawingData->height, 0);
    
    glTexCoord2d(drawingData->width, drawingData->height);
    glVertex2f(drawingData->width, drawingData->height);
    
    glTexCoord2d(0, drawingData->height);
    glVertex2f(0, drawingData->height);
    
    glPopMatrix();
    glMatrixMode(GL_MODELVIEW);
    
    glEnd();
    glFlush();
    
    // Save the image for redrawing if necessary and release the previous, unless we are internally performing a re-draw
    if (drawingData != &_lastDrawingData) {
        if (drawingData->freeCallback) {
            drawingData->freeCallback(drawingData->baseAddress, drawingData->context);
        }
        _lastDrawingData = *drawingData;
    }
    
    CGLUnlockContext(glContext);
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
    [super reshape];
}



@end
