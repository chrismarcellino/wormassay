//
//  VideoProcessorController.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/11/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VideoProcessor.h"


// Convienience macro
#define RunLog(format, args...) [[VideoProcessorController sharedInstance] appendToRunLog:format, ## args]


@interface VideoProcessorController : NSObject <VideoProcessorDelegate, NSTableViewDataSource> {
    dispatch_queue_t _queue;     // protects all state and serializes
    NSMutableArray *_videoProcessors;
    VideoProcessor *_currentlyTrackingProcessor;
    NSTimeInterval _trackingBeginTime;
    NSCountedSet *_barcodesSinceTrackingBegan;
    NSMutableDictionary *_videoTempURLsToDestinationURLs;
    NSMapTable *_captureDevicesToSessions;
    NSMutableSet *_filesToEmail;
    
    NSDate *_runStartDate;
    unsigned long long _plateInRunNumber;
    NSString *_currentOutputFilenamePrefix;
    NSString *_runID;
    NSTimeInterval _currentOutputLastWriteTime;      // in CPU time
    
    NSMutableArray *_pendingConversionPaths;
    NSTask *_conversionTask;
    BOOL _pauseJobs;
    BOOL _isAppTerminating;
    
    NSDictionary *_runLogTextAttributes;    // main thread only
}

+ (VideoProcessorController *)sharedInstance;

- (NSArray *)assayAnalyzerClasses;
@property(assign) Class currentAssayAnalyzerClass;
@property(copy) NSString *runOutputFolderPath;
- (NSString *)videoFolderPathCreatingIfNecessary:(BOOL)create;

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor;
- (void)removeVideoProcessor:(VideoProcessor *)videoProcessor;

- (BOOL)isTracking;
- (BOOL)supportsConversion;
- (BOOL)hasConversionJobsQueuedOrRunning;
- (void)terminateAllConversionJobsForAppTerminationSynchronously;

@property(retain) NSTextView *runLogTextView;
@property(retain) NSScrollView *runLogScrollView;
@property(retain) NSTableView *encodingTableView;
- (void)appendToRunLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end
