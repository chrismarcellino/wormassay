//
//  VideoProcessorController.h
//  WormAssay
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
    NSTextView *_runLogTextView;      // main thread only
    NSScrollView *_runLogTextScrollView; // main thread only
    NSDictionary *_runLogTextAttributes;
}

+ (VideoProcessorController *)sharedInstance;

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor;
- (void)removeVideoProcessor:(VideoProcessor *)videoProcessor;

@property(retain) NSTextStorage *runLogTextStorage;
@property(retain) NSScrollView *runLogTextScrollView;
- (void)appendToRunLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)appendToResultsCSVFile:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
