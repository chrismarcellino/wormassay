//
//  VideoProcessor.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/5/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "opencv2/core/core_c.h"

@class IplImageObject;

// Convienience macro
#define ProcessLog(format, args...) [[VideoProcessor sharedInstance] logFormat:format, ## args]

typedef enum {
    ProcessingStateNoPlate,
    ProcessingStatePlateFirstFrameIdentified,
    ProcessingStateTrackingMotion
} ProcessingState;


// Thread-safe.
@interface VideoProcessor : NSObject
// Instance variables are in the implementation file as they contain C++ objects

+ (VideoProcessor *)sharedInstance;

- (void)noteSourceIdentifierHasConnected:(NSString *)sourceIdentifier;
- (void)noteSourceIdentifierHasDisconnected:(NSString *)sourceIdentifier;

// Caller is responsible for calling cvReleaseImage() on debugFrame. Block will be called on an arbitrary thread. 
- (void)processVideoFrame:(IplImageObject *)videoFrame
     fromSourceIdentifier:(NSString *)sourceIdentifier
         presentationTime:(NSTimeInterval)presentationTime
debugVideoFrameCompletion:(void (^)(IplImageObject *image))callback;

- (void)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
//- (void)outputFormatToCurrentCSVFile:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
