//
//  VideoSourceController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoSourceController.h"
#import "BitmapOpenGLView.h"
#import "IplImageConversionUtilities.hpp"
#import "opencv2/core/core_c.h"

NSString *const CaptureDeviceScheme = @"capturedevice";
NSString *const CaptureDeviceFileType = @"dyn.capturedevice";

static NSPoint LastCascadePoint = { 0.0, 0.0 };

static void releaseIplImage(void *baseAddress, void *context);

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

@interface VideoSourceController ()

- (void)adjustWindowSizing;
- (void)processVideoFrame:(IplImage *)iplImage presentationTime:(QTTime)presentationTime;

@end


@implementation VideoSourceController

@synthesize captureDevice = _captureDevice;
@synthesize movie = _movie;

+ (NSArray *)readableTypes
{
    //return [[QTMovie movieFileTypes:QTIncludeCommonTypes] arrayByAddingObject:CaptureDeviceFileType];
    return [NSArray arrayWithObjects:CaptureDeviceFileType, @"public.movie", nil];
}

+ (NSArray *)writableTypes
{
    return [NSArray array];
}

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
            _captureDevice = [[QTCaptureDevice deviceWithUniqueID:captureDeviceUniqueID] retain];
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Unknown capture device ID" forKey:NSLocalizedDescriptionKey];
            if (outError) {
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }
        }
    } else if ([absoluteURL isFileURL]) {
        _movieFrameExtractQueue = dispatch_queue_create("movie frame extract queue", NULL);
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    absoluteURL, QTMovieURLAttribute,
                                    [NSNumber numberWithBool:YES], QTMovieOpenForPlaybackAttribute,
                                    [NSNumber numberWithBool:NO], QTMovieOpenAsyncOKAttribute,
                                    nil];
        _movie = [[QTMovie alloc] initWithAttributes:attributes error:outError];
        [attributes release];
    }
    
    if (_captureDevice) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(adjustWindowSizing)
                                                     name:QTCaptureDeviceFormatDescriptionsDidChangeNotification
                                                   object:_captureDevice];
    }
    
    if (!_captureDevice && !_movie) {
        [self autorelease];
        return nil;
    }
    
    return [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
}

- (id)initForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError
{
    // Movies are not writeable
    [self autorelease];
    return nil;
}

- (void)dealloc
{
    if (_captureDevice) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:QTCaptureDeviceFormatDescriptionsDidChangeNotification
                                                      object:_captureDevice];
    }
    
    [_captureDevice release];
    [_captureSession release];
    [_captureDeviceInput release];
    [_captureDecompressedVideoOutput release];
    
    [_movie release];
    if (_movieFrameExtractQueue) {
        dispatch_release(_movieFrameExtractQueue);
    }
    if (_movieFrameExtractTimer) {
        dispatch_release(_movieFrameExtractTimer);
    }
    
    [_bitmapOpenGLView release];
    [super dealloc];
}

- (void)makeWindowControllers
{
    NSRect contentRect = NSZeroRect;
    contentRect.size = [self lastKnownResolution];
    
    // Create the window to hold the content view and contrain it to preserve the aspect ratio
    NSUInteger styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect styleMask:styleMask backing:NSBackingStoreBuffered defer:YES];
    // Enable multi-threaded drawing
    [window setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
	[window useOptimizedDrawing:YES];       // since there are no overlapping subviews
    [window setOpaque:YES];
    
    // Create the subview and sets its layer
    _bitmapOpenGLView = [[BitmapOpenGLView alloc] initWithFrame:contentRect];
    [_bitmapOpenGLView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [window setContentView:_bitmapOpenGLView];
    
    // Create the window controller
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    [windowController setWindowFrameAutosaveName:[[self fileURL] relativeString]];
    [self addWindowController:windowController];
    [window release];
    [windowController release];
    
    // Cascade the window if it doesn't have a previously saved position
    NSRect frame = [window frame];
    if (frame.origin.x == 0.0 && frame.origin.y == 0.0) {
        LastCascadePoint = [window cascadeTopLeftFromPoint:LastCascadePoint];
    }
    
    // Remove the icon and disable the close butotn if this is a capture device
    if (_captureDevice) {
        [window setRepresentedURL:nil];
        [[window standardWindowButton:NSWindowCloseButton] setEnabled:NO];
    }
    
    [self adjustWindowSizing];
}

- (void)adjustWindowSizing
{
    NSSize contentSize = [self lastKnownResolution];
    
    // Adjust the main window controllers's window (currently only window)
    NSArray *windowControllers = [self windowControllers];
    if ([windowControllers count] > 0) {
        NSWindow *window = [[windowControllers objectAtIndex:0] window];
        
        NSSize existingContentMaxSize = [window contentMaxSize];
        
        // If the content size is changing, reset the frame
        if (existingContentMaxSize.width != contentSize.width && existingContentMaxSize.height != contentSize.height) {
            NSRect existingFrame = [window frame];
            NSPoint existingTopLeftPoint = NSMakePoint(existingFrame.origin.x, existingFrame.origin.y + existingFrame.size.height);
            
            [window setContentSize:contentSize];
            [window setFrameTopLeftPoint:existingTopLeftPoint];
        }
        
        [window setContentMaxSize:contentSize];
        [window setContentMinSize:NSMakeSize(MAX(contentSize.width / 4, MIN(contentSize.width, 256)),
                                             MAX(contentSize.height / 4, MIN(contentSize.height, 256)))];
        [window setContentAspectRatio:contentSize];
    }
}

- (NSSize)lastKnownResolution
{
    NSSize size;
    
    if (_captureDevice) {
        size = NSZeroSize;
        for (QTFormatDescription *formatDescription in [_captureDevice formatDescriptions]) {
            NSSize formatSize = [[formatDescription attributeForKey:QTFormatDescriptionVideoEncodedPixelsSizeAttribute] sizeValue];
            if (formatSize.width > size.width && formatSize.height > size.height) {
                size = formatSize;
            }
        }
    } else {
        size = [[_movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    BOOL success;
    
    if (_captureDevice) {
        // Start capture
        _captureSession = [[QTCaptureSession alloc] init];
        success = [_captureDevice open:outError];
        if (success) {
            _captureDeviceInput = [[QTCaptureDeviceInput alloc] initWithDevice:_captureDevice];
            success = [_captureSession addInput:_captureDeviceInput error:outError];
            if (success) {
                _captureDecompressedVideoOutput = [[QTCaptureDecompressedVideoOutput alloc] init];
                
                NSDictionary *bufferAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                  [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey, nil];
                [_captureDecompressedVideoOutput setPixelBufferAttributes:bufferAttributes];
                [bufferAttributes release];
                
                [_captureDecompressedVideoOutput setDelegate:self];
                success = [_captureSession addOutput:_captureDecompressedVideoOutput error:outError];
                if (success) {
                    [_captureSession startRunning];
                }
            }
        }
    } else {
        // Start frame grab of video at time scale rate to simulate live processing
        QTTime duration = [[_movie attributeForKey:QTMovieDurationAttribute] QTTimeValue];
        QTTime start = { 0, duration.timeScale, 0 };

        // Ensure that we are able to read at least one frame
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:QTMovieFrameImageTypeCGImageRef, QTMovieFrameImageType, nil];
        success = [_movie frameImageAtTime:[_movie currentTime] withAttributes:attributes error:outError] != nil;
        
        if (success) {
            [_movie detachFromCurrentThread];
            
            _movieFrameExtractTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _movieFrameExtractQueue);
            dispatch_source_set_event_handler(_movieFrameExtractTimer, ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                // Migrate the movie to this thread
                [QTMovie enterQTKitOnThread];
                [_movie attachToCurrentThread];
                
                NSError *error = nil;
                CGImageRef videoFrame = (CGImageRef)[_movie frameImageAtTime:[_movie currentTime] withAttributes:attributes error:&error];
                if (error) {
                    NSLog(@"Video frame decode error: %@", error);
                }
                if (videoFrame) {
                    IplImage *iplImage = CreateIplImageFromCGImage(videoFrame, 4);
                    [self processVideoFrame:iplImage presentationTime:_nextExtractTime];
                }
                QTTime increment = { 1, duration.timeScale, 0 };
                QTTimeIncrement(_nextExtractTime, increment);
                
                // Loop back to the begining if past the end
                QTTimeRange range = { start, duration };
                if (!QTTimeInTimeRange(increment, range)) {
                    _nextExtractTime = start;
                }
                
                [_movie detachFromCurrentThread];
                [QTMovie exitQTKitOnThread];
                [pool release];
            });
            dispatch_source_set_timer(_movieFrameExtractTimer, 0, NSEC_PER_SEC * 1000ull / duration.timeScale, 0);
            dispatch_resume(_movieFrameExtractTimer);
        }
        [attributes release];
    }
    
    return success;
}

- (void)close
{
    // XXX Tear down analysis machinery
    
    [_captureSession stopRunning];
    [_captureDecompressedVideoOutput setDelegate:nil];
    if (_movieFrameExtractTimer) {
        dispatch_source_cancel(_movieFrameExtractTimer);
    }
    [super close];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
  didOutputVideoFrame:(CVImageBufferRef)videoFrame
     withSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    IplImage *iplImage = CreateIplImageFromCVPixelBuffer((CVPixelBufferRef)videoFrame, 4);
    [self processVideoFrame:iplImage presentationTime:[sampleBuffer presentationTime]];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
didDropVideoFrameWithSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    frameDropCount++;
    if (frameDropCount == 1 || frameDropCount % 10 == 0) {
        NSLog(@"Device \"%@\" dropped %llu total frames", [_captureDevice localizedDisplayName], (unsigned long long)frameDropCount);
    }
}

// This method will be called on a background thread. It will not be called again until the current call returns.
// Interviening frames may be dropped if the video is a live capture device source. 
- (void)processVideoFrame:(IplImage *)iplImage presentationTime:(QTTime)presentationTime
{
    NSAssert(iplImage->width * iplImage->nChannels == iplImage->widthStep, @"packed images are required");
    BitmapDrawingData drawingData = { iplImage->imageData, iplImage->width, iplImage->height, GL_BGRA, GL_UNSIGNED_BYTE, releaseIplImage, iplImage };
    [_bitmapOpenGLView drawBitmapTexture:&drawingData];
    
    // XXX Analyze video and pass data back to a master controller
}

static void releaseIplImage(void *baseAddress, void *context)
{
    IplImage *image = (IplImage *)context;
    cvReleaseImage(&image);
}

- (NSString *)displayName
{
    NSString *displayName;
    if (_captureDevice) {
        displayName = [_captureDevice localizedDisplayName];
    } else {
        displayName = [super displayName];
    }
    return displayName;
}
  
@end
