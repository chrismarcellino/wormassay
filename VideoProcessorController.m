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
#import "Emailer.h"
#import "ArrayTableView.h"

static NSString *const AssayAnalyzerClassKey = @"AssayAnalyzerClass";
static NSString *const NotificationEmailRecipientsKey = @"NotificationEmailRecipients";
static NSString *const PlateOrientationKey = @"PlateOrientation";

static NSString *const RunOutputFolderPathKey = @"RunOutputFolderPath";
static NSString *const SortableLoggingDateFormat = @"yyyy-MM-dd HH:mm zzz";
static NSString *const SortableLoggingFilenameSafeDateFormat = @"yyyy-MM-dd HHmm zzz";
static NSString *const RunIDDateFormat = @"yyyyMMddHHmm";
static NSString *const UnlabeledPlateLabel = @"Unlabeled Plate";

// Logs are turned and results emailed after an idle period of this duration
static const NSTimeInterval LogTurnoverIdleInterval = 10 * 60.0;

@interface VideoProcessorController ()

- (void)emailRecentResults;

- (void)enqueueConversionJobForPath:(NSString *)sourceVideoPath;
- (void)dequeueNextConversionJobIfNecessary;
- (void)setConversionJobsPaused:(BOOL)paused;;
- (void)taskDidTerminate:(NSNotification *)note;
- (void)handleConversionTaskTermination;
- (void)updateEncodingTableView;

- (void)appendString:(NSString *)string toPath:(NSString *)path;

@end


@implementation VideoProcessorController

@synthesize runLogTextView;
@synthesize runLogScrollView;
@synthesize encodingTableView;

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
        _videoTempURLsToDestinationURLs = [[NSMutableDictionary alloc] init];
        _filesToEmail = [[NSMutableSet alloc] init];
        _pendingConversionPaths = [[NSMutableArray alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(taskDidTerminate:) name:NSTaskDidTerminateNotification object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSTaskDidTerminateNotification object:nil];
    
    [_videoProcessors release];
    [_currentlyTrackingProcessor release];
    [_barcodesSinceTrackingBegan release];
    [_videoTempURLsToDestinationURLs release];
    [_filesToEmail release];
    [_runStartDate release];
    [_currentOutputFilenamePrefix release];
    [_runLogTextAttributes release];
    [_pendingConversionPaths release];
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

- (PlateOrientation)plateOrientation
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:PlateOrientationKey];
}

- (void)setPlateOrientation:(PlateOrientation)plateOrietation
{
    if (plateOrietation != [self plateOrientation]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setInteger:plateOrietation forKey:PlateOrientationKey];
        [defaults synchronize];
        
        dispatch_async(_queue, ^{
            for (VideoProcessor *videoProcessor in _videoProcessors) {
                [videoProcessor setPlateOrientation:plateOrietation];
            }
        });
    }
}

- (NSString *)runOutputFolderPath
{
    NSString *path = [[[NSUserDefaults standardUserDefaults] stringForKey:RunOutputFolderPathKey] stringByExpandingTildeInPath];
    if (!path) {
        path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        path = [path stringByAppendingPathComponent:@"Worm Assay Data"];
    }
    return path;
}

- (void)setRunOutputFolderPath:(NSString *)path
{
    if (path) {
        path = [path stringByAbbreviatingWithTildeInPath];
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:path forKey:RunOutputFolderPathKey];
    [defaults synchronize];
}

static void createFolderIfNecessary(NSString *path)
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if (![fileManager fileExistsAtPath:path]) {
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    [fileManager release];
}

- (NSString *)runOutputFolderPathCreatingIfNecessary:(BOOL)create
{
    NSString *folder = [self runOutputFolderPath];
    if (create) {
        createFolderIfNecessary(folder);
    }
    return folder;
}

- (NSString *)videoFolderPathCreatingIfNecessary:(BOOL)create
{
    NSString *folder = [[self runOutputFolderPath] stringByAppendingPathComponent:@"Videos"];
    if (create) {
        createFolderIfNecessary(folder);
    }
    return folder;
}

- (NSString *)notificationEmailRecipients
{
    return [[NSUserDefaults standardUserDefaults] stringForKey:NotificationEmailRecipientsKey];
}

- (void)setNotificationEmailRecipients:(NSString *)recipients
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:recipients forKey:NotificationEmailRecipientsKey];
    [defaults synchronize];
}

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [_videoProcessors addObject:videoProcessor];
        [videoProcessor setDelegate:self];
        [videoProcessor setAssayAnalyzerClass:[self currentAssayAnalyzerClass]];
        [videoProcessor setPlateOrientation:[self plateOrientation]];
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

- (BOOL)isTracking
{
    __block BOOL isTracking = NO;
    dispatch_sync(_queue, ^{
        isTracking = _currentlyTrackingProcessor != nil;
    });
    return isTracking;
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
            
            [self setConversionJobsPaused:YES];
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp shouldBeginRecordingWithCaptureFileOutput:(QTCaptureFileOutput *)captureFileOutput
{    
    dispatch_async(_queue, ^{
        if ([captureFileOutput delegate] != self) {
            [captureFileOutput setDelegate:self];
        }
        
        // Use a generic container extension at this point since we don't know if this is an MPEG stream yet
        NSString *filename = [NSString stringWithFormat:@"%@ %llu (%x).mov", UnlabeledPlateLabel, _plateInRunNumber, arc4random()];
        NSString *path = [[self videoFolderPathCreatingIfNecessary:YES] stringByAppendingPathComponent:filename];
        [captureFileOutput recordToOutputFileURL:[NSURL fileURLWithPath:path]];
        RunLog(@"Began recording video to disk.");
    });
}

- (void)videoProcessor:(VideoProcessor *)vp
didFinishAcquiringPlateData:(PlateData *)plateData
          successfully:(BOOL)successfully
stopRecordingWithCaptureFileOutput:(QTCaptureFileOutput *)captureFileOutput
{
    dispatch_async(_queue, ^{
        if (_currentlyTrackingProcessor == vp) {        // may have already been removed from _videoProcessors if device was unplugged/file closed
            for (VideoProcessor *processor in _videoProcessors) {
                [processor setShouldScanForWells:YES];
            }
            [self setConversionJobsPaused:NO];
            
            // Determine the filename prefix to log to. Rotate the log files if we've been idle for a time and update the run date if necessary
            if (!_currentOutputFilenamePrefix || _currentOutputLastWriteTime + LogTurnoverIdleInterval < CACurrentMediaTime()) {
                // Store the run start date
                [_runStartDate release];
                _runStartDate = [[NSDate alloc] init];
                
                // Create the output filename prefix for this run
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:SortableLoggingFilenameSafeDateFormat];
                [_currentOutputFilenamePrefix release];
                _currentOutputFilenamePrefix = [[dateFormatter stringFromDate:_runStartDate] retain];
                _currentOutputLastWriteTime = CACurrentMediaTime();
                
                // Create the run ID for thisInfo run
                [dateFormatter setDateFormat:RunIDDateFormat];
                [_runID release];
                _runID = [[dateFormatter stringFromDate:_runStartDate] retain];
                [dateFormatter release];
                
                // Reset the plate counter
                _plateInRunNumber = 1;
            }
            
            // Write the results to disk and the run log if successful
            if (successfully) {
                // Find the likely barcode corresponding to this plate or use a placeholder if there isn't one
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
                    NSString *fileSourceFilename = [vp fileSourceFilename];
                    plateID = fileSourceFilename ? fileSourceFilename : UnlabeledPlateLabel;
                }
                
                // Generate the scan ID
                NSString *scanID = [NSString stringWithFormat:@"%@-%llu", _runID, _plateInRunNumber++];
                
                RunLog(@"Writing results for plate \"%@\" to disk.", plateID);
                
                // Get the run CSV data and log it out to disk
                NSMutableDictionary *rawOutputDictionary = [[NSMutableDictionary alloc] init];
                NSString *runOutput = [plateData csvOutputForPlateID:plateID scanID:scanID withAdditionalRawDataOutput:rawOutputDictionary];
                
                NSString *folder = [self runOutputFolderPath];
                NSString *runOutputPath = [folder stringByAppendingPathComponent:
                                           [_currentOutputFilenamePrefix stringByAppendingString:@" Run Output.csv"]];
                [self appendString:runOutput toPath:runOutputPath];
                [_filesToEmail addObject:runOutputPath];
                
                for (NSString *columnID in rawOutputDictionary) {
                    NSString *rawDataCSVOutput = [rawOutputDictionary objectForKey:columnID];
                    NSString *rawOutputPath = [folder stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"%@ Raw %@ Values.csv", _currentOutputFilenamePrefix, columnID]];
                    [self appendString:rawDataCSVOutput toPath:rawOutputPath];
                    [_filesToEmail addObject:rawOutputPath];
                }
                [rawOutputDictionary release];
                
                // Mark the recording URL for moving once it is finalized
                if (captureFileOutput && [captureFileOutput outputFileURL]) {
                    BOOL isTransportStream = NO;
                    for (QTCaptureConnection *connection in [captureFileOutput connections]) {
                        if ([[connection formatDescription] formatType] == 'mp2v') {
                            isTransportStream = YES;
                        }
                    }
                    
                    NSString *extension = isTransportStream ? @"ts" : @"mov";
                    NSString *filename = [NSString stringWithFormat:@"%@ %@ Video.%@", plateID, scanID, extension];                    
                    NSString *destinationPath = [[self videoFolderPathCreatingIfNecessary:YES] stringByAppendingPathComponent:filename];
                    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
                    // Store the temporary URL and destination URL so we can move it into place once the file is finalized
                    [_videoTempURLsToDestinationURLs setObject:destinationURL forKey:[captureFileOutput outputFileURL]];
                }
            }
            
            [_currentlyTrackingProcessor release];
            _currentlyTrackingProcessor = nil;
        }
        
        // Stop recording unconditionally
        if (captureFileOutput) {
            [captureFileOutput recordToOutputFileURL:nil];
            NSAssert([captureFileOutput delegate] == self, @"recordingCaptureOutput not VideoProcessorController");
        }
        
        // Reset log emailing timer
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(emailRecentResults) object:nil];
            [self performSelector:@selector(emailRecentResults) withObject:nil afterDelay:LogTurnoverIdleInterval];
        });
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

- (void)emailRecentResults
{
    dispatch_async(_queue, ^{
        NSString *recipients = [self notificationEmailRecipients];
        recipients = [recipients stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([_filesToEmail count] > 0 && recipients && [recipients length] > 0) {
            NSBundle *mainBundle = [NSBundle mainBundle];
            NSString *subject = [NSString stringWithFormat:@"%@ email results", [mainBundle objectForInfoDictionaryKey:(id)kCFBundleNameKey]];
            NSString *body = [NSString stringWithFormat:@"Results from the run %@ starting %@ are attached.\n\nSent by %@ version %@ \n\n",
                              _runID,
                              _currentOutputFilenamePrefix,
                              [mainBundle objectForInfoDictionaryKey:(id)kCFBundleNameKey],
                              [mainBundle objectForInfoDictionaryKey:(id)kCFBundleVersionKey]];
            [Emailer sendMailMessageToRecipients:recipients subject:subject body:body attachmentPaths:[_filesToEmail allObjects]];
            RunLog(@"Sent email with results as attachments to: %@", recipients);
        }
        
        [_filesToEmail removeAllObjects];
    });
}

// QTCaptureFileOutput delegate methods

// "This method is called when the file recorder reaches a soft limit, i.e. the set maximum file size or duration.
// If the delegate returns NO, the file writer will continue writing the same file. If the delegate returns YES and
// doesn't set a new output file, captureOutput:mustChangeOutputFileAtURL:forConnections:dueToError: will be called.
// If the delegate returns YES and sets a new output file, recording will continue on the new file."
- (BOOL)captureOutput:(QTCaptureFileOutput *)captureOutput shouldChangeOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
            NSAlert *alert = [NSAlert alertWithError:error];
            [alert beginSheetModalForWindow:nil
                              modalDelegate:nil
                             didEndSelector:nil
                                contextInfo:NULL];
        }
    });
    return YES;
}

// "This method is called when the file writer reaches a hard limit, such as space running out on the current disk,
// or the stream format of the incoming media changing. If the delegate does nothing, the current output file will
// be set to nil. If the delegate sets a new output file (on a different disk in the case of hitting a disk space limit)
// recording will continue on the new file."
- (void)captureOutput:(QTCaptureFileOutput *)captureOutput mustChangeOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error) {
            NSAlert *alert = [NSAlert alertWithError:error];
            [alert beginSheetModalForWindow:nil
                              modalDelegate:nil
                             didEndSelector:nil
                                contextInfo:NULL];
        }
    });
}

// "This method is called whenever a file is finished successfully. If the file was forced to be finished due to an error
// (including errors that resulted in either of the above two methods being called), the error is described in the error
// parameter. Otherwise, the error parameter equals nil."
- (void)captureOutput:(QTCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL forConnections:(NSArray *)connections dueToError:(NSError *)error
{
    dispatch_async(_queue, ^{
        if (error) {
            RunLog(@"Error finishing recording to file \"%@\": %@", [outputFileURL path], error);
        }
        
        NSURL *destinationURL = [_videoTempURLsToDestinationURLs objectForKey:outputFileURL];
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        NSError *fileManagerError = nil;
        if (destinationURL) {
            // Move the file into place
            if ([fileManager moveItemAtURL:outputFileURL toURL:destinationURL error:&fileManagerError]) {
                RunLog(@"Wrote video at \"%@\" to disk.", [destinationURL path]);
                
                [self enqueueConversionJobForPath:[destinationURL path]];
            } else {
                RunLog(@"Unable to move recording at \"%@\" to \"%@\": %@", [outputFileURL path], [destinationURL path], fileManagerError);
            }
        } else {
            // Delete the file
            if (![fileManager removeItemAtURL:outputFileURL error:&fileManagerError] && !error) {
                RunLog(@"Unable to delete recording at \"%@\": %@", [outputFileURL path], fileManagerError);
            }
        }
        [_videoTempURLsToDestinationURLs removeObjectForKey:outputFileURL];
        [fileManager release];
    });
}

static inline BOOL isValidPath(NSString *path, NSFileManager *fileManager)
{
    return path && [fileManager fileExistsAtPath:path] && [fileManager isExecutableFileAtPath:path];
}

- (NSString *)conversionToolPath
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    NSString *path = [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"ffmpeg"];
    if (!isValidPath(path, fileManager)) {
        path = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"ffmpeg"];
    }
    if (!isValidPath(path, fileManager)) {
        path = [@"~/Applications/ffmpeg" stringByExpandingTildeInPath];
    }
    if (!isValidPath(path, fileManager)) {
        path = @"/Applications/ffmpeg";
    }
    if (!isValidPath(path, fileManager)) {
        path = @"/usr/bin/ffmpeg";
    }
    if (!isValidPath(path, fileManager)) {
        path = @"/usr/local/bin/ffmpeg";
    }
    [fileManager release];
    
    return path;
}

- (BOOL)supportsConversion
{
    return [self conversionToolPath] != nil;
}

- (void)enqueueConversionJobForPath:(NSString *)sourceVideoPath
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    if ([self supportsConversion] && [fileManager fileExistsAtPath:sourceVideoPath]) {
        // By convention, the first job in the queue is always running
        dispatch_async(_queue, ^{
            [_pendingConversionPaths addObject:sourceVideoPath];
            [self dequeueNextConversionJobIfNecessary];
            [self updateEncodingTableView];
        });
    }
    
    [fileManager release];
}

static NSString *outputPathForInputJobPath(NSString *inputPath)
{
    return [[inputPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp4"];
}

- (void)dequeueNextConversionJobIfNecessary
{
    dispatch_async(_queue, ^{
        if (!_isAppTerminating && !_pauseJobs && !_conversionTask && [_pendingConversionPaths count] > 0) {
            NSString *inputPath = [_pendingConversionPaths objectAtIndex:0];
            NSString *outputPath = outputPathForInputJobPath(inputPath);
            
            if ([inputPath isEqual:outputPath]) {
                // Nothing to do, move on
                [_pendingConversionPaths removeObjectAtIndex:0];
                [self dequeueNextConversionJobIfNecessary];
            } else {
                _conversionTask = [[NSTask alloc] init];
                [_conversionTask setLaunchPath:[self conversionToolPath]];
                
                // Start a conversion job to convert H.264 using x264 into an MP4 container.
                // Use a ratefactor of 22 and multithread automatically.
                NSArray *arguments = [NSArray arrayWithObjects:@"-i", inputPath,
                                      @"-vcodec", @"libx264", @"-f", @"mp4", @"-crf", @"22", @"-threads", @"0", @"-y", outputPath, nil];
                [_conversionTask setArguments:arguments];
                // Must launch task on main thread to ensure that a thread is around to service the death notification
                dispatch_async(dispatch_get_main_queue(), ^{
                    // If possible and we haven't already, create a new session with us as the session leader and a new group with us as the group leader
                    pid_t group = setsid();
                    if (group == -1) {
                        group = getpgrp();
                    }
                    [_conversionTask launch];
                    // Place the launched process in our group if possible so that it is terminated if we crash
                    setpgid([_conversionTask processIdentifier], group);
                });
                RunLog(@"Started H.264 encoding job for \"%@\".", inputPath);
                
                [self updateEncodingTableView];
            }
        }
    });
}

- (void)taskDidTerminate:(NSNotification *)note
{
    dispatch_async(_queue, ^{
        if (_conversionTask == [note object]) {
            [self handleConversionTaskTermination];
        }
    });
}

// requires _queue to be held
- (void)handleConversionTaskTermination
{
    NSAssert(_conversionTask && ![_conversionTask isRunning], @"no terminated task");
    NSString *inputPath = [_pendingConversionPaths objectAtIndex:0];
    NSString *outputPath = outputPathForInputJobPath(inputPath);
    NSAssert([[_conversionTask arguments] containsObject:inputPath] && [[_conversionTask arguments] containsObject:outputPath],
             @"task doesn't match head of queue");
    
    [_pendingConversionPaths removeObjectAtIndex:0];
    
    // Delete the input file if the output file exists and the process exited without an error code or crashing
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([_conversionTask terminationReason] == NSTaskTerminationReasonExit &&
        [_conversionTask terminationStatus] == 0 &&
        [fileManager fileExistsAtPath:inputPath]) {
        RunLog(@"H.264 encoding completed successfully for \"%@\"", outputPath);
        [fileManager removeItemAtPath:inputPath error:NULL];
    } else {
        // Otherwise delete the output and leave the input file
        RunLog(@"H.264 encoding failed for \"%@\". See the Console application for more information. Leaving unencoded original file in place.", inputPath);
        [fileManager removeItemAtPath:outputPath error:NULL];
    }
    [fileManager release];
    
    [_conversionTask release];
    _conversionTask = nil;
    
    // Start the next job
    [self dequeueNextConversionJobIfNecessary];
    [self updateEncodingTableView];
}

- (void)setConversionJobsPaused:(BOOL)paused
{
    dispatch_async(_queue, ^{
        _pauseJobs = paused;
        
        if (_conversionTask) {
            if (paused) {
                [_conversionTask suspend];
            } else {
                [_conversionTask resume];
            }
        } else {
            [self dequeueNextConversionJobIfNecessary];
        }
        
        [self updateEncodingTableView];
    });
}

- (BOOL)hasConversionJobsQueuedOrRunning
{
    __block BOOL result;
    dispatch_sync(_queue, ^{
        result = [_pendingConversionPaths count] > 0;
    });
    return result;
}

- (void)terminateAllConversionJobsForAppTerminationSynchronously
{
    dispatch_sync(_queue, ^{
        if (_conversionTask) {
            [[_conversionTask retain] autorelease];
            [_conversionTask terminate];
            [_conversionTask waitUntilExit];
            [self handleConversionTaskTermination];
        }
        
        _isAppTerminating = YES;
    });
}

// requires _queue to be held
- (void)updateEncodingTableView
{
    NSMutableArray *array = [[NSMutableArray alloc] init];
    BOOL first = YES;
    for (NSString *path in _pendingConversionPaths) {
        NSString *value = [path lastPathComponent];
        if (first) {
            NSString *status = _pauseJobs ? NSLocalizedString(@" (paused)", nil) : NSLocalizedString(@" (processing…)", nil);
            value = [value stringByAppendingString:status];
            first = NO;
        }
        [array addObject:value];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self encodingTableView] setContents:array];
    });
    [array release];
}

// Logging

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

@end
