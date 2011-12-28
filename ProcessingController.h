//
//  ProcessingController.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

// Convienience macro
#define ProcessLog(format, args...) [[ProcessingController sharedInstance] logFormat:format, ## args]

typedef enum {
    ProcessingStateNoPlate,
    ProcessingStatePlateFirstFrameIdentified,
    ProcessingStateTrackingMotion
} ProcessingState;


// Thread-safe.
@interface ProcessingController : NSObject {
    dispatch_queue_t _queue;        // protects all state and serializes
    dispatch_queue_t _debugFrameCallbackQueue;
    CvFont debugImageFont;
    
    ProcessingState _state;
    NSString *_wellCameraSourceIdentifier;
    int _wellCountHint;
#if __cplusplus     // hide C++ ivars from non C++ clients. This is only safe to do on the 64-bit Objective-C ABI, which this app requires.
    std::vector<cv::Vec3f> _cicrles;
#endif
}

+ (ProcessingController *)sharedInstance;

// Caller is responsible for calling cvReleaseImage() on debugFrame. Block will be called on an arbitrary thread. 
- (void)processVideoFrame:(IplImage *)videoFrame
     fromSourceIdentifier:(NSString *)sourceIdentifier
        frameAbsoluteTime:(NSTimeInterval)frameAbsoluteTime
debugVideoFrameCompletionTakingOwnership:(void (^)(IplImage *debugFrame))callback;

- (void)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
