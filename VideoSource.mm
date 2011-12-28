//
//  VideoSource.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoSource.h"
#import "IplImageConversionUtilities.hpp"


NSString *const CaptureDeviceScheme = @"capturedevice";
static NSPoint LastCascadePoint = { 0.0, 0.0 };

NSURL *URLForCaptureDeviceUniqueID(NSString *uniqueID)
{
    return [[[NSURL alloc] initWithScheme:CaptureDeviceScheme
                                     host:@""
                                     path:[@"/" stringByAppendingString:uniqueID]] autorelease];
}

NSString *UniqueIDForCaptureDeviceURL(NSURL *url)
{
    NSString *uniqueID = nil;
    if ([[url scheme] caseInsensitiveCompare:CaptureDeviceScheme] == NSOrderedSame) {
        // Remove the leading slash from the absolute URL path
        uniqueID = [url path];
        if ([uniqueID hasPrefix:@"/"]) {
            uniqueID = [uniqueID substringFromIndex:1];
        }
    }
    return uniqueID;
}

@interface VideoSource ()

- (void)processVideoFrame:(CVImageBufferRef)videoFrame presentationTime:(QTTime)presentationTime;

@end


@implementation VideoSource

- (id)init
{
    if ((self = [super init])) {
        [self setHasUndoManager:NO];
    }
    
    return self;
}

- (id)initWithType:(NSString *)typeName error:(NSError **)outError
{
    // Movies cannot be created anew
    [self autorelease];
    return nil;
}

- (id)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    NSString *captureDeviceUniqueID = UniqueIDForCaptureDeviceURL(absoluteURL);
    if (captureDeviceUniqueID) {
        if (captureDeviceUniqueID) {
            captureDevice = [[QTCaptureDevice deviceWithUniqueID:captureDeviceUniqueID] retain];
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Unknown capture device ID" forKey:NSLocalizedDescriptionKey];
            if (outError) {
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }
        }
    } else if ([absoluteURL isFileURL]) {
        movieFrameExtractQueue = dispatch_queue_create("movie frame extract queue", NULL);
        movie = [[QTMovie alloc] initWithURL:absoluteURL error:outError];
    }
    
    if (captureDevice || movie) {
        return [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
    } else {
        [self autorelease];
        return nil;
    }
}

- (id)initForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError
{
    // Movies are not writeable
    [self autorelease];
    return nil;
}

- (void)dealloc
{
    [captureDevice release];
    [captureSession release];
    [captureDeviceInput release];
    [captureDecompressedVideoOutput release];
    
    [movie release];
    if (movieFrameExtractQueue) {
        dispatch_release(movieFrameExtractQueue);
    }
    if (movieFrameExtractTimer) {
        dispatch_release(movieFrameExtractTimer);
    }
    
    [imageLayer release];
    [super dealloc];
}

- (void)makeWindowControllers
{
    NSRect contentRect = NSZeroRect;
    contentRect.size = [self maximumNativeResolution];
    
    // Create the window to hold the content view and contrain it to preserve the aspect ratio
    NSUInteger styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect styleMask:styleMask backing:NSBackingStoreBuffered defer:YES];
    [window setContentMaxSize:contentRect.size];
    [window setContentMinSize:NSMakeSize(contentRect.size.width / 4, contentRect.size.height / 4)];
    [window setContentAspectRatio:contentRect.size];
    
    // Enable multi-threaded drawing
	[window setAllowsConcurrentViewDrawing:YES];
    [window setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
	[window useOptimizedDrawing:YES];       // since there are no overlapping subviews
    
    // Create the subview and sets its layer
    NSView *imageView = [[NSView alloc] init];
    [imageView setCanDrawConcurrently:YES];
    imageLayer = [[CALayer alloc] init];
    [imageView setLayer:imageLayer];
    [imageView setWantsLayer:YES];
    [window setContentView:imageView];
    [imageView release];
    
    // XXX
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    [windowController setWindowFrameAutosaveName:[[self fileURL] relativeString]];
    [self addWindowController:windowController];
    [window release];
    [windowController release];
    
    // Cascade the window if it doesn't have a previously saved position
    LastCascadePoint = [window cascadeTopLeftFromPoint:LastCascadePoint];
}

- (NSSize)maximumNativeResolution
{
    NSSize size;
    
    if (captureDevice) {
        size = NSZeroSize;
        for (QTFormatDescription *formatDescription in [captureDevice formatDescriptions]) {
            NSSize formatSize = [[formatDescription attributeForKey:QTFormatDescriptionVideoEncodedPixelsSizeAttribute] sizeValue];
            if (formatSize.width > size.width && formatSize.height > size.height) {
                size = formatSize;
            }
        }
    } else {
        size = [[movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    BOOL success;
    // XXX Set up analysis machinery here
    
    if (captureDevice) {
        // Start capture
        captureSession = [[QTCaptureSession alloc] init];
        success = [captureDevice open:outError];
        if (success) {
            captureDeviceInput = [[QTCaptureDeviceInput alloc] initWithDevice:captureDevice];
            success = [captureSession addInput:captureDeviceInput error:outError];
            if (success) {
                captureDecompressedVideoOutput = [[QTCaptureDecompressedVideoOutput alloc] init];
                [captureDecompressedVideoOutput setDelegate:self];
                success = [captureSession addOutput:captureDecompressedVideoOutput error:outError];
                if (success) {
                    [captureSession startRunning];
                }
            }
        }
    } else {
        // Start frame grab of video at time scale rate to simulate live processing
        QTTime duration = [[movie attributeForKey:QTMovieDurationAttribute] QTTimeValue];
        QTTime start = { 0, duration.timeScale, 0 };

        // Ensure that we are able to read at least one frame
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:QTMovieFrameImageTypeCVPixelBufferRef, QTMovieFrameImageType, nil];
        success = [movie frameImageAtTime:nextExtractTime withAttributes:attributes error:outError] != nil;
        
        movieFrameExtractTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, movieFrameExtractQueue);
        dispatch_source_set_event_handler(movieFrameExtractTimer, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            
            CVPixelBufferRef videoFrame = [movie frameImageAtTime:nextExtractTime withAttributes:attributes error:nil];
            [self processVideoFrame:videoFrame presentationTime:nextExtractTime];
            QTTime increment = { 1, duration.timeScale, 0 };
            QTTimeIncrement(nextExtractTime, increment);
            
            // Loop back to the begining if past the end
            QTTimeRange range = { start, duration };
            if (!QTTimeInTimeRange(increment, range)) {
                nextExtractTime = start;
            }
            
            [pool release];
        });
        dispatch_source_set_timer(movieFrameExtractTimer, 0, NSEC_PER_SEC * 1000 / duration.timeScale, 0);
        [attributes release];
    }
    
    return success;
}

- (void)close
{
    // XXX Tear down analysis machinery
    
    if (movieFrameExtractTimer) {
        dispatch_source_cancel(movieFrameExtractTimer);
    }
    [super close];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
  didOutputVideoFrame:(CVImageBufferRef)videoFrame
     withSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    [self processVideoFrame:(CVPixelBufferRef)videoFrame presentationTime:[sampleBuffer presentationTime]];
}

// This method will be called on a background thread. It will not be called again until the current call returns.
// Interviening frames may be dropped if the video is a live capture device source. 
- (void)processVideoFrame:(CVPixelBufferRef)videoFrame presentationTime:(QTTime)presentationTime
{
    [CATransaction begin];
    [imageLayer setContents:videoFrame];
    [CATransaction commit];
    
    //IplImage *iplImage = CreateIplImageFromCVPixelBuffer(videoFrame);
    
    

    // XXX Analyze video and pass data back to a master controller
}

- (NSString *)displayName
{
    NSString *displayName;
    if (captureDevice) {
        displayName = [captureDevice localizedDisplayName];
    } else {
        displayName = [super displayName];
    }
    return displayName;
}

@end
