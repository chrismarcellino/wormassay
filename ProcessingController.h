//
//  ProcessingController.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

// Thread-safe.
@interface ProcessingController : NSObject {
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
}

+ (ProcessingController *)sharedInstance;

// Caller is responsible for calling cvReleaseImage() on debugFrame. Block will be called on an arbitrary thread. 
- (void)processVideoFrameTakingOwnership:(IplImage *)videoFrame
                    fromSourceIdentifier:(NSString *)sourceIdentifier
debugVideoFrameCompletionTakingOwnership:(void (^)(IplImage *debugFrame))block;

- (void)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
