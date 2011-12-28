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
        _queue = dispatch_queue_create("videoprocessorcontroller", NULL);
        _videoProcessors = [[NSMutableArray alloc] init];
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
	Class *classes = malloc(numberOfClasses * sizeof(Class));
    objc_getClassList(classes, numberOfClasses);
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

- (Class)assayAnalyzerClass
{
    NSString *string = [[NSUserDefaults standardUserDefaults] stringForKey:AssayAnalyzerClassKey];
    Class class = Nil;
    if (string) {
        class = NSClassFromString(string);
    }
    
    if (!class) {
        class = NSClassFromString(@"LuminanceMotionAnalyzer");
    }
    if (!class) {
        class = [[self assayAnalyzerClasses] objectAtIndex:0];
    }
    
    return class;
}

- (void)setAssayAnalyzerClass:(Class)assayAnalyzerClass
{
    if (assayAnalyzerClass != [self assayAnalyzerClass]) {
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

- (void)addVideoProcessor:(VideoProcessor *)videoProcessor
{
    dispatch_async(_queue, ^{
        [_videoProcessors addObject:videoProcessor];
        [videoProcessor setDelegate:self];
        [videoProcessor setAssayAnalyzerClass:[self assayAnalyzerClass]];
        [videoProcessor setShouldScanForWells:YES];
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
        if ([_videoProcessors containsObject:vp]) {
            for (VideoProcessor *processor in _videoProcessors) {
                // Prevent all other processors from scanning for wells to conserve CPU time and avoid tracking more than one plate
                if (vp != processor) {
                    [processor setShouldScanForWells:NO];
                }
            }
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp didFinishAcquiringPlateData:(PlateData *)plateData
{
    dispatch_async(_queue, ^{
        if ([_videoProcessors containsObject:vp]) {
            for (VideoProcessor *processor in _videoProcessors) {
                [processor setShouldScanForWells:YES];
            }
            
            // XXX DO SOME STUFF WITH THE RESULTS
        }
    });
}

- (void)videoProcessor:(VideoProcessor *)vp didCaptureBarcodeText:(NSString *)text atTime:(NSTimeInterval)presentationTime
{
    dispatch_async(_queue, ^{
        if ([_videoProcessors containsObject:vp]) {
            // XXX DO SOME STUFF WITH THE RESULTS
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
    
    dispatch_async(_queue, ^{
        // XXX: Write to disk
        
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
    });
    [string release];
}

- (void)appendToResultsCSVFile:(NSString *)format, ...
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
