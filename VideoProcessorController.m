//
//  VideoProcessorController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/11/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoProcessorController.h"


@implementation VideoProcessorController

+ (VideoProcessorController *)sharedInstance
{
    static dispatch_once_t pred = 0;
    static VideoProcessorController *sharedInstance = nil;
    dispatch_once(&pred, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (id)init
{
    if ((self = [super init])) {
        _queue = dispatch_queue_create("edu.ucsf.chrismarcellino.nematodeassay.videoprocessorcontroller", NULL);
        _videoProcessors = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [_videoProcessors release];
    [super dealloc];
}

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [_videoProcessors addObject:videoProcessor];
        [videoProcessor setDelegate:self];
    });
}

- (void)removeVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [videoProcessor setShouldScanForWells:NO];
        [_videoProcessors removeObject:videoProcessor];
    });    
}

- (void)videoProcessorDidBeginTrackingPlate:(VideoProcessor *)vp
{
    dispatch_async(_queue, ^{
        for (VideoProcessor *processor in _videoProcessors) {
            // Prevent all other processors from scanning for wells to conserve CPU time and avoid tracking more than one plate
            if (vp != processor) {
                [processor setShouldScanForWells:NO];
            }
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp didFinishAcquiringPlateResults:(id)something
{
    dispatch_async(_queue, ^{
        for (VideoProcessor *processor in _videoProcessors) {
            [processor setShouldScanForWells:YES];
        }
        
        // XXX DO SOME STUFF WITH THE RESULTS
    });
}

- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcode:(NSString *)barcode atTime:(NSTimeInterval)presentationTime
{
    dispatch_async(_queue, ^{
        // XXX DO SOME STUFF WITH THE RESULTS
    });
}

- (void)appendToRunLog:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    dispatch_async(_queue, ^{
        // XXX: todo, write documents folder appropriately, and show on screen in a window.
        // for now, syslog.
        NSLog(@"%@", string);
    });
    [string release];
}

- (void)appendToResultsLog:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // XXX MIRROR TO RUN LOG
    dispatch_async(_queue, ^{
        /// XXX TODO
        NSLog(@"%@", string);
    });
    [string release];
}

- (void)appendString:(NSString *)string toPath:(NSString *)path
{
    bool success = false;
    
    for (int i = 0; i < 2 && !success; i++) {
        int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT | O_SHLOCK, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
        if (fd != -1) {
            NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
            @try {
                [handle seekToEndOfFile];
                [handle writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
                [handle closeFile];
                success = true;
            } @catch (NSException *e) {
                [self appendToRunLog:@"Unable to write to file '%@': %@", path, e];
            }
            [handle release];
        } else if (i > 0) {
            [self appendToRunLog:@"Unable to open file '%@': %s", path, strerror(errno)];
        }
        
        // Try creating the directory hiearchy if there was an issue and try again
        if (!success) {
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            NSString *directory = [path stringByDeletingLastPathComponent];
            if (![fileManager fileExistsAtPath:directory]) {
                [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
            }
            [fileManager release];
            
        }
    }
}

@end
