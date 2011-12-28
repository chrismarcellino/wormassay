//
//  ImageDrawingOpenGLView.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "ImageDrawingOpenGLView.h"


@implementation ImageDrawingOpenGLView

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat*)format
{
    if ((self = [super initWithFrame:frameRect pixelFormat:format])) {
        pthread_mutex_init(&mutex, NULL);
    }
    
    return self;
}

- (void)dealloc
{
    pthread_mutex_destroy(&mutex);
    [super dealloc];
}

- (void)lock
{
    pthread_mutex_lock(&mutex);
}

- (void)unlock
{
    pthread_mutex_unlock(&mutex);
}

- (void)update
{
    [self lock];
    [super update];
    [self unlock];
}

@end
