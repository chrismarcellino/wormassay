//
//  VideoProcessorController.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/11/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VideoProcessor.h"


// Convienience macro
#define RunLog(format, args...) [[VideoProcessorController sharedInstance] appendToRunLog:format, ## args]


@interface VideoProcessorController : NSObject <VideoProcessorDelegate> {
    dispatch_queue_t _queue;     // protects all state and serializes
    NSMutableArray *_videoProcessors;
}

+ (VideoProcessorController *)sharedInstance;

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor;
- (void)removeVideoProcessor:(VideoProcessor *)videoProcessor;

- (void)appendToRunLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)appendToResultsLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
