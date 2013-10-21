//
//  BitmapOpenGLView.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/3/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "BitmapOpenGLView.h"
#import <OpenGL/glu.h>
#import "opencv2/core/core_c.h"
#import "VideoFrame.h"


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
        (NSOpenGLPixelFormatAttribute)NULL
    };
    return [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
}

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
    if ((self = [super initWithFrame:frameRect pixelFormat:format])) {
        [self setCanDrawConcurrently:YES];
    }
    
    return self;
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
    // Enable DMA'ing of the pixel buffers, which requires that we keep the buffer around until the texture is overwritten
    glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_STORAGE_HINT_APPLE, GL_STORAGE_CACHED_APPLE);
    glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
    
    CGLUnlockContext(glContext);
}

- (void)renderImage:(VideoFrame *)image
{
    CGLContextObj glContext = [[self openGLContext] CGLContextObj];
    CGLLockContext(glContext);
    CGLSetCurrentContext(glContext);
 
    IplImage *iplImage = image ? [image image] : [_lastImage image];
    if (iplImage) {
        NSAssert(iplImage->widthStep == iplImage->width * iplImage->nChannels, @"image not byte packed");
        NSAssert(iplImage->nChannels == 4, @"image not 4 channel");
        // Set the texture image
        glTexImage2D(GL_TEXTURE_RECTANGLE_ARB,
                     0,
                     4,
                     iplImage->width,
                     iplImage->height,
                     0,
                     GL_BGRA,
                     GL_UNSIGNED_BYTE,
                     iplImage->imageData);
        
        glMatrixMode(GL_PROJECTION);
        glPushMatrix();
        glLoadIdentity();
        
        // Invert the image
        glOrtho(0, iplImage->width, iplImage->height, 0, -1, 1);
        // Set the viewport
        glViewport(_viewport.origin.x, _viewport.origin.y, _viewport.size.width, _viewport.size.height);
        
        glBegin(GL_POLYGON);
        
        glTexCoord2d(0, 0);
        glVertex2f(0, 0);
        glTexCoord2d(iplImage->width, 0);
        glVertex2f(iplImage->width, 0);
        glTexCoord2d(iplImage->width, iplImage->height);
        glVertex2f(iplImage->width, iplImage->height);
        glTexCoord2d(0, iplImage->height);
        glVertex2f(0, iplImage->height);
        
        glEnd();
        
        glPopMatrix();
    } else {
        // Clear the bit plane
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    // Exchange the back buffer for the front buffer
    CGLFlushDrawable(glContext);
    
    // Save the image for redrawing if necessary and release the previous, unless we are internally performing a re-draw.
    // We get rid of the previous data after uploading the new texture so that we don't incur a copy of the pixels that we
    // may have DMA'd. 
    if (image) {
        _lastImage = image;
    }
    
    GLenum error = glGetError();
    if (error != GL_NO_ERROR) {
        NSLog(@"Error: %@ drawing error (%s)", [self class], gluErrorString(error));
    }
    
    CGLSetCurrentContext(NULL);
    CGLUnlockContext(glContext);
}

- (void)drawRect:(NSRect)dirtyRect
{
    [self renderImage:nil];
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
