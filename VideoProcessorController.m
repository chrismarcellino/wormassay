//
//  VideoProcessorController.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/11/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "VideoProcessorController.h"
#import <objc/runtime.h>
#import "AssayAnalyzer.h"
#import "PlateData.h"

static NSString *const AssayAnalyzerClassKey = @"AssayAnalyzerClass";
static NSString *const RunOutputFolderPathKey = @"RunOutputFolderPath";
static NSString *const SortableLoggingDateFormat = @"yyyy-MM-dd HH:mm zzz";
static NSString *const SortableLoggingFilenameSafeDateFormat = @"yyyy-MM-dd HHmm zzz";

static const NSTimeInterval logTurnoverIdleInterval = 10 * 60.0;

@interface VideoProcessorController ()

- (void)appendString:(NSString *)string toPath:(NSString *)path;

@end


@implementation VideoProcessorController

@synthesize runLogTextView;
@synthesize runLogScrollView;

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
        _queue = dispatch_queue_create("video-processor-controller", NULL);
        _videoProcessors = [[NSMutableArray alloc] init];
        _barcodesSinceTrackingBegan = [[NSCountedSet alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [_videoProcessors release];
    [_runLogTextAttributes release];
    [super dealloc];
}

- (NSArray *)assayAnalyzerClasses
{
    NSMutableArray *assayAnalyzerClasses = [NSMutableArray array];
    
    int	numberOfClasses = objc_getClassList(NULL, 0);
	Class *classes = calloc(numberOfClasses * 2, sizeof(Class));
    numberOfClasses = objc_getClassList(classes, numberOfClasses);
    for (int i = 0; i < numberOfClasses; i++) {
        // use this runtime method instead of messaging the class to avoid +loading all classes in memory
        if (class_conformsToProtocol(classes[i], @protocol(AssayAnalyzer))) {
            [assayAnalyzerClasses addObject:classes[i]];
        }
    }
    free(classes);
    
    // Sort by display name
    [assayAnalyzerClasses sortUsingSelector:@selector(analyzerName)];
    
    return assayAnalyzerClasses;
}

- (Class)currentAssayAnalyzerClass
{
    NSString *string = [[NSUserDefaults standardUserDefaults] stringForKey:AssayAnalyzerClassKey];
    Class class = Nil;
    if (string) {
        class = NSClassFromString(string);
    }
    
    if (!class) {
        class = NSClassFromString(@"ConsensusLuminanceMotionAnalyzer");
    }
    if (!class) {
        class = [[self assayAnalyzerClasses] objectAtIndex:0];
    }
    
    return class;
}

- (void)setCurrentAssayAnalyzerClass:(Class)assayAnalyzerClass
{
    if (assayAnalyzerClass != [self currentAssayAnalyzerClass]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:NSStringFromClass(assayAnalyzerClass) forKey:AssayAnalyzerClassKey];
        [defaults synchronize];
        
        dispatch_async(_queue, ^{
            for (VideoProcessor *videoProcessor in _videoProcessors) {
                [videoProcessor setAssayAnalyzerClass:assayAnalyzerClass];
            }
        });
    }
}

- (NSString *)runOutputFolderPath
{
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:RunOutputFolderPathKey];
    if (!path) {
        path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        path = [path stringByAppendingPathComponent:@"Worm Assay Data"];
    }
    return path;
}

- (void)setRunOutputFolderPath:(NSString *)path
{
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:RunOutputFolderPathKey];
}

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [_videoProcessors addObject:videoProcessor];
        [videoProcessor setDelegate:self];
        [videoProcessor setAssayAnalyzerClass:[self currentAssayAnalyzerClass]];
        [videoProcessor setShouldScanForWells:YES];
    });
}

- (void)removeVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [videoProcessor reportFinalResultsBeforeRemoval];
        [_videoProcessors removeObject:videoProcessor];
    });    
}

- (void)videoProcessor:(VideoProcessor *)vp didBeginTrackingPlateAtPresentationTime:(NSTimeInterval)presentationTime
{
    dispatch_async(_queue, ^{
        if ([_videoProcessors containsObject:vp] && !_currentlyTrackingProcessor) {
            _currentlyTrackingProcessor = [vp retain];
            _trackingBeginTime = presentationTime;
            
            // Clear the past barcodes
            [_barcodesSinceTrackingBegan removeAllObjects];
            
            for (VideoProcessor *processor in _videoProcessors) {
                // Prevent all other processors from scanning for wells to conserve CPU time and avoid tracking more than one plate
                if (vp != processor) {
                    [processor setShouldScanForWells:NO];
                }
            }
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp
didFinishAcquiringPlateData:(PlateData *)plateData
          successfully:(BOOL)successfully
{
    dispatch_async(_queue, ^{
        BOOL movieRecordingMoved = NO;
        
        if (_currentlyTrackingProcessor == vp) {        // may have already been removed from _videoProcessors if device was unplugged/file closed
            for (VideoProcessor *processor in _videoProcessors) {
                [processor setShouldScanForWells:YES];
            }
            
            // Find the likely barcode corresponding to this plate or make one up
            NSString *plateID = nil;
            NSUInteger count = 0;
            for (NSString *barcode in _barcodesSinceTrackingBegan) {
                NSUInteger barcodeCount = [_barcodesSinceTrackingBegan countForObject:barcode];
                if (barcodeCount > count) {
                    count = barcodeCount;
                    plateID = barcode;
                }
            }
            if (!plateID) {
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:SortableLoggingDateFormat];
                plateID = [NSString stringWithFormat:@"Unlabeled Plate %@", [dateFormatter stringFromDate:[NSDate date]]];
                [dateFormatter release];
            }
            
            // Write the results to disk and the run log if successful
            if (successfully) {
                RunLog(@"Writing results for plate \"%@\" to disk.", plateID);
                
                // Determine the filename prefix to log to. Rotate the log files if we've been idle for a time
                if (!_currentOutputFilenamePrefix || _currentOutputLastWriteTime + logTurnoverIdleInterval < CACurrentMediaTime()) {
                    [_currentOutputFilenamePrefix release];
                    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateFormat:SortableLoggingFilenameSafeDateFormat];
                    _currentOutputFilenamePrefix = [[dateFormatter stringFromDate:[NSDate date]] retain];
                    _currentOutputLastWriteTime = CACurrentMediaTime();
                    [dateFormatter release];
                }
                
                // Get the run CSV data and log it out to disk
                NSMutableDictionary *rawOutputDictionary = [[NSMutableDictionary alloc] init];
                NSString *runOutput = [plateData csvOutputForPlateID:plateID withAdditionalRawDataOutput:rawOutputDictionary];
                
                NSString *folder = [self runOutputFolderPath];
                NSString *runOutputPath = [folder stringByAppendingPathComponent:
                                           [_currentOutputFilenamePrefix stringByAppendingString:@" Run Output.csv"]];
                [self appendString:runOutput toPath:runOutputPath];
                
                for (NSString *columnID in rawOutputDictionary) {
                    NSString *rawDataCSVOutput = [rawOutputDictionary objectForKey:columnID];
                    NSString *rawOutputPath = [folder stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"%@ Raw %@ Values.csv", _currentOutputFilenamePrefix, columnID]];
                    [self appendString:rawDataCSVOutput toPath:rawOutputPath];
                }
                [rawOutputDictionary release];
                
                // Move the video to its destination if necessary. It is safe to move() the file while it may still be open.
                if (recordingTempFilePath) {
                    NSFileManager *fileManager = [[NSFileManager alloc] init];
                    NSString *videoFolder = [folder stringByAppendingPathComponent:@"Videos"];
                    if (![fileManager fileExistsAtPath:videoFolder]) {
                        [fileManager createDirectoryAtPath:videoFolder withIntermediateDirectories:YES attributes:nil error:NULL];
                    }
                    
                    NSString *destinationPath = [videoFolder stringByAppendingPathComponent:
                                                 [_currentOutputFilenamePrefix stringByAppendingString:@" Video.ts"]];
                    
                    NSError *error = nil;
                    movieRecordingMoved = [fileManager moveItemAtPath:recordingTempFilePath toPath:destinationPath error:&error];
                    if (!movieRecordingMoved) {
                        RunLog(@"Unable to move recording at \"%@\" to \"%@\": %@", recordingTempFilePath, destinationPath, error);
                    }
                    [fileManager release];
                }
            }
            
            [_currentlyTrackingProcessor release];
            _currentlyTrackingProcessor = nil;
        }
        
        if (!movieRecordingMoved && recordingTempFilePath) {
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            NSError *error = nil;
            [fileManager removeItemAtPath:recordingTempFilePath error:&error];
            if (error) {
                RunLog(@"Unable to delete recording at \"%@\": %@", recordingTempFilePath, error);
            }
            [fileManager release];
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcodeText:(NSString *)text atTime:(NSTimeInterval)presentationTime
{
    dispatch_async(_queue, ^{
        if ([_videoProcessors containsObject:vp] && presentationTime >= _trackingBeginTime) {
            [_barcodesSinceTrackingBegan addObject:text];
        }
    });
}

- (void)appendToRunLog:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSMutableString *string = [[NSMutableString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [string appendString:@"\n"];        // Append a newline
    
    // Nested these blocks to preserve ordering between the disk file and log window
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTextView *textView = [self runLogTextView];
        NSScrollView *scrollView = [self runLogScrollView];
        BOOL wasAtBottom = ![scrollView hasVerticalScroller] || 
        [textView frame].size.height <= [scrollView frame].size.height ||
        [[scrollView verticalScroller] floatValue] >= 1.0;
        
        if (!_runLogTextAttributes) {
            _runLogTextAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                     [NSFont fontWithName:@"Menlo Regular" size:12], NSFontAttributeName, nil];
        }
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:_runLogTextAttributes];
        NSTextStorage *textStorage = [textView textStorage];
        [textStorage beginEditing];
        [textStorage appendAttributedString:attributedString];
        [textStorage endEditing];
        [attributedString release];
        
        if (wasAtBottom) {
            [textView scrollRangeToVisible:NSMakeRange([textStorage length], 0)];
        }
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

// QTCaptureFileOutput delegate methods

- (void)captureOutput:(QTCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL forConnections:(NSArray *)connections
{
    
}

// "This method is called when the file recorder reaches a soft limit, i.e. the set maximum file size or duration.
// If the delegate returns NO, the file writer will continue writing the same file. If the delegate returns YES and
// doesn't set a new output file, captureOutput:mustChangeOutputFileAtURL:forConnections:dueToError: will be called.
// If the delegate returns YES and sets a new output file, recording will continue on the new file."
- (BOOL)captureOutput:(QTCaptureFileOutput *)captureOutput shouldChangeOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // XXXXXXXXXX SHOW ALERTS
        
        // XXXXXXXXXXX SET LIMITS (***NOT HERE****) BASED ON FREE SPACE (e.g. 1GB or 1%, whichever is less). 
        // PREVENT RECORDING IN FIRST PLACE IF THAT IS THE CASE.
    });
    return YES;
}

// "This method is called when the file writer reaches a hard limit, such as space running out on the current disk,
// or the stream format of the incoming media changing. If the delegate does nothing, the current output file will
// be set to nil. If the delegate sets a new output file (on a different disk in the case of hitting a disk space limit)
// recording will continue on the new file."
- (void)captureOutput:(QTCaptureFileOutput *)captureOutput mustChangeOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    
}

// "This method is called whenever a file will be finished, either because recordToFile:/recordToFile:bufferDestination:
// was called. or an error forced the file to be finished. If the file was forced to be finished due to an error, the error
// is described in the error parameter. Otherwise, the error parameter equals nil."
- (void)captureOutput:(QTCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    
}

// "This method is called whenever a file is finished successfully. If the file was forced to be finished due to an error
// (including errors that resulted in either of the above two methods being called), the error is described in the error
// parameter. Otherwise, the error parameter equals nil."
- (void)captureOutput:(QTCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    
}

@end
