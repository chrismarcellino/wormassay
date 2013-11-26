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


@implementation VideoProcessorController

@synthesize runLogTextView = _runLogTextView;
@synthesize runLogScrollView = _runLogScrollView;

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
    }
    
    return self;
}

- (NSArray *)assayAnalyzerClasses
{
    NSMutableArray *assayAnalyzerClasses = [NSMutableArray array];
    
    int	numberOfClasses = objc_getClassList(NULL, 0);
	Class *classes = (Class *)calloc(numberOfClasses * 2, sizeof(Class));
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
        if (![class conformsToProtocol:@protocol(AssayAnalyzer)]) {
            class = nil;
        }
    }
    
    if (!class) {
        class = NSClassFromString(@"OpticalFlowMotionAnalyzer");
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
        path = [path stringByAppendingPathComponent:@"WormAssay Data"];
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

- (void)manuallyReportResultsForCurrentProcessor
{
    if (_currentlyTrackingProcessor) {
        [_currentlyTrackingProcessor manuallyReportResultsAndReset];
    }
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

- (BOOL)isProcessingVideo
{
    __block BOOL isProcessingVideo = NO;
    dispatch_sync(_queue, ^{
        isProcessingVideo = [_videoProcessors count] > 0;
    });
    return isProcessingVideo;
}

- (BOOL)isTracking
{
    __block BOOL isTracking = NO;
    dispatch_sync(_queue, ^{
        isTracking = _currentlyTrackingProcessor != nil;
    });
    return isTracking;
}

- (BOOL)hasEncodingJobsRunning
{
    __block BOOL hasEncodingJobsRunning = NO;
    dispatch_sync(_queue, ^{
        hasEncodingJobsRunning = [_videoTempURLsToDestinationURLs count] > 0;
    });
    return hasEncodingJobsRunning;
}

- (void)videoProcessor:(VideoProcessor *)vp didBeginTrackingPlateAtPresentationTime:(NSTimeInterval)presentationTime
{
    dispatch_async(_queue, ^{
        if ([_videoProcessors containsObject:vp] && !_currentlyTrackingProcessor) {
            _currentlyTrackingProcessor = vp;
            _trackingBeginTime = presentationTime;
            
            // Ensure that the plate tracking processor has the intended orientation
            [vp setPlateOrientation:[self plateOrientation]];
            
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

- (NSURL *)outputFileURLForVideoProcessor:(VideoProcessor *)vp
{
    __block NSURL *url = nil;
    dispatch_sync(_queue, ^{
        NSString *filename = [NSString stringWithFormat:@"%@ %llu (%x).mp4", UnlabeledPlateLabel, _plateInRunNumber, arc4random()];
        NSString *path = [[self videoFolderPathCreatingIfNecessary:YES] stringByAppendingPathComponent:filename];
        url = [NSURL fileURLWithPath:path];
    });
    return url;
}

- (void)videoProcessor:(VideoProcessor *)vp
didFinishAcquiringPlateData:(PlateData *)plateData
          successfully:(BOOL)successfully
willStopRecordingToOutputFileURL:(NSURL *)outputFileURL     // nil if not recording
{
    dispatch_async(_queue, ^{
        if (_currentlyTrackingProcessor == vp) {        // may have already been removed from _videoProcessors if device was unplugged/file closed
            for (VideoProcessor *processor in _videoProcessors) {
                [processor setShouldScanForWells:YES];
            }
            
            // Determine the filename prefix to log to. Rotate the log files if we've been idle for a time and update the run date if necessary
            if (!_currentOutputFilenamePrefix || _currentOutputLastWriteTime + LogTurnoverIdleInterval < CACurrentMediaTime()) {
                // Store the run start date
                _runStartDate = [[NSDate alloc] init];
                
                // Create the output filename prefix for this run
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                [dateFormatter setDateFormat:SortableLoggingFilenameSafeDateFormat];
                _currentOutputFilenamePrefix = [dateFormatter stringFromDate:_runStartDate];
                
                // Create the run ID for thisInfo run
                [dateFormatter setDateFormat:RunIDDateFormat];
                _runID = [dateFormatter stringFromDate:_runStartDate];
                
                // Reset the plate counter
                _plateInRunNumber = 1;
            }
            _currentOutputLastWriteTime = CACurrentMediaTime();     // update the time uncondtionally since we're interested in the idle period
            
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
                    NSString *fileSourceDisplayName = [vp fileSourceDisplayName];
                    plateID = fileSourceDisplayName ? fileSourceDisplayName : UnlabeledPlateLabel;
                }
                
                // Generate the scan ID
                NSString *scanID = [NSString stringWithFormat:@"%@-%llu", _runID, _plateInRunNumber++];
                
                RunLog(@"Writing results for plate \"%@\" to disk.", plateID);
                
                // Get the run CSV data and log it out to disk
                NSMutableDictionary *rawOutputDictionary = [[NSMutableDictionary alloc] init];
                NSString *runOutput = [plateData csvOutputForPlateID:plateID
                                                              scanID:scanID
                                         withAdditionalRawDataOutput:rawOutputDictionary
                                                        analyzerName:[[self currentAssayAnalyzerClass] analyzerName]
                                                    columnMajorOrder:[[NSUserDefaults standardUserDefaults] boolForKey:@"OutputInColumnMajorOrder"]];
                
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
                
                // Mark the recording URL for moving once it is finalized
                if (outputFileURL) {
                    NSString *filename = [NSString stringWithFormat:@"%@ %@ Video.mp4", plateID, scanID];
                    NSString *destinationPath = [[self videoFolderPathCreatingIfNecessary:YES] stringByAppendingPathComponent:filename];
                    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
                    // Store the temporary URL and destination URL so we can move it into place once the file is finalized
                    [_videoTempURLsToDestinationURLs setObject:destinationURL forKey:outputFileURL];
                }
            }
            
            _currentlyTrackingProcessor = nil;
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
        // If we have a barcode on a camera that isn't the tracking camera, don't rotate the image		
        if (vp != _currentlyTrackingProcessor && [_videoProcessors count] > 1) {		
            [vp setPlateOrientation:PlateOrientationTopRead];		
        }
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

- (void)videoProcessorDidFinishRecordingToFileURL:(NSURL *)outputFileURL error:(NSError *)error      // error is nil upon success
{
    dispatch_async(_queue, ^{
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [NSAlert alertWithError:error];
                [alert beginSheetModalForWindow:nil
                                  modalDelegate:nil
                                 didEndSelector:nil
                                    contextInfo:NULL];
            });
        }
        
        NSURL *destinationURL = [_videoTempURLsToDestinationURLs objectForKey:outputFileURL];
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        NSError *fileManagerError = nil;
        if (destinationURL) {
            // Move the file into place
            if ([fileManager moveItemAtURL:outputFileURL toURL:destinationURL error:&fileManagerError]) {
                RunLog(@"Wrote video at \"%@\" to disk.", [destinationURL path]);
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
    });
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
        
        if (wasAtBottom) {
            [textView scrollRangeToVisible:NSMakeRange([textStorage length], 0)];
        }
    });
}

- (void)appendString:(NSString *)string toPath:(NSString *)path
{
    @synchronized(self) {
        bool success = false;
        
        for (int i = 0; i < 2 && !success; i++) {
            int fd = open([path fileSystemRepresentation], O_WRONLY | O_CREAT, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
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
            }
        }
    }
}

@end
