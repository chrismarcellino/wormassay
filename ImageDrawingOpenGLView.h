//
//  ImageDrawingOpenGLView.h.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/2/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <pthread.h>

// Threadsafe
@interface ImageDrawingOpenGLView : NSOpenGLView {
    pthread_mutex_t mutex;
}

- (void)lock;
- (void)unlock;

@end
