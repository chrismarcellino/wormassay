//
//  VideoSourceDocument.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoSourceDocument.h"
#import "opencv2/core/core_c.h"
#import <QuartzCore/QuartzCore.h>
#import "BitmapOpenGLView.h"
#import "VideoProcessor.h"
#import "IplImageObject.h"

NSString *const CaptureDeviceScheme = @"capturedevice";
NSString *const CaptureDeviceFileType = @"dyn.capturedevice";

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

@interface VideoSourceDocument ()

- (void)adjustWindowSizing;
- (void)processVideoFrame:(IplImageObject *)image presentationTime:(QTTime)presentationTime;

@end


@implementation VideoSourceDocument

@synthesize captureDevice = _captureDevice;
@synthesize movie = _movie;
@synthesize sourceIdentifier = _sourceIdentifier;

+ (NSArray *)readableTypes
{
    return [NSArray arrayWithObjects:CaptureDeviceFileType, @"public.movie", @"public.image", nil];
}

+ (NSArray *)writableTypes
{
    return [NSArray array];
}

- (id)init
{
    if ((self = [super init])) {
        [self setHasUndoManager:NO];
        _bitmapOpenGLView = [[BitmapOpenGLView alloc] init];
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
    // Create either a QTCaptureDevice or QTMovie and store a unique but human readable identifier for it
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
        
        _sourceIdentifier = [[NSString alloc] initWithFormat:@"\"%@\" (%@)", [_captureDevice localizedDisplayName], captureDeviceUniqueID];
        
        ProcessLog(@"Opened device \"%@\" with model ID \"%@\"", _sourceIdentifier, [_captureDevice modelUniqueID]);
    } else if ([absoluteURL isFileURL]) {
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    absoluteURL, QTMovieURLAttribute,
                                    [NSNumber numberWithBool:YES], QTMovieOpenForPlaybackAttribute,
                                    [NSNumber numberWithBool:NO], QTMovieOpenAsyncOKAttribute,
                                    nil];
        _movie = [[QTMovie alloc] initWithAttributes:attributes error:outError];
        _movieQueue = dispatch_queue_create("Movie frame extraction queue", NULL);
        [attributes release];
        
        _sourceIdentifier = [[absoluteURL path] retain];
        ProcessLog(@"Opened file \"%@\"", _sourceIdentifier);
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
    if (_movieQueue) {
        dispatch_release(_movieQueue);
    }
    if (_movieFrameExtractTimer) {
        dispatch_release(_movieFrameExtractTimer);
    }
    
    [_bitmapOpenGLView release];
    [_sourceIdentifier release];
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
    
    // Insert the bitmap view into the window (the view is created in init so that it is safe to access by the capture threads without locking)
    [_bitmapOpenGLView setFrame:contentRect];
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
        [window setContentMaxSize:contentSize];
        [window setContentMinSize:NSMakeSize(MAX(contentSize.width / 4, MIN(contentSize.width, 256)),
                                             MAX(contentSize.height / 4, MIN(contentSize.height, 256)))];
        [window setContentAspectRatio:contentSize];
                
        // If the content size is changing, reset the frame
        if (existingContentMaxSize.width != contentSize.width && existingContentMaxSize.height != contentSize.height) {
            NSRect existingFrame = [window frame];
            NSRect newFrame = [window frameRectForContentRect:NSMakeRect(0.0, 0.0, contentSize.width, contentSize.height)];
            newFrame.origin.x = existingFrame.origin.x;
            newFrame.origin.y = existingFrame.origin.y + existingFrame.size.height - newFrame.size.height;
            [window setFrame:[window constrainFrameRect:newFrame toScreen:[window screen]] display:YES];
        }
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
        
        // Use a better pre-roll placeholder size
        NSUInteger formatCount = [[_captureDevice formatDescriptions] count];
        if (formatCount == 0 || (formatCount == 1 && size.width == 160 && size.height == 120)) {
            size = NSMakeSize(640.0, 480.0);
        }
    } else {
        size = [[_movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    BOOL success = NO;
    
    [[VideoProcessor sharedInstance] noteSourceIdentifierHasConnected:_sourceIdentifier];
    
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
        // Calculate a representative retrievable frame time delta. Note that some formats have time scales that vary (which isn't a concern here).
        [_movie gotoBeginning];
        QTTime firstFrameTime = [_movie currentTime];
        [_movie stepForward];
        QTTime secondFrameTime = [_movie currentTime];
        [_movie gotoBeginning];
        NSTimeInterval frameDuration = 0.0;
        NSTimeInterval firstFrameTimeInterval, secondFrameTimeInterval;
        if (QTGetTimeInterval(firstFrameTime, &firstFrameTimeInterval) && QTGetTimeInterval(secondFrameTime, &secondFrameTimeInterval)) {
            frameDuration = secondFrameTimeInterval - firstFrameTimeInterval;
        }
        
        if (frameDuration > 0.0) {
            success = YES;
            [_movie detachFromCurrentThread];
            
            NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                        QTMovieFrameImageTypeCGImageRef, QTMovieFrameImageType,
                                        nil];
            
            _movieFrameExtractTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _movieQueue);
            dispatch_source_set_event_handler(_movieFrameExtractTimer, ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                // Migrate the movie to this thread
                [QTMovie enterQTKitOnThread];
                [_movie attachToCurrentThread];
                
                // Capture a frame
                NSError *error = nil;
                QTTime currentFrameTime = [_movie currentTime];
                CGImageRef videoFrame = (CGImageRef)[_movie frameImageAtTime:currentFrameTime withAttributes:attributes error:&error];
                if (error) {
                    NSLog(@"Video frame decode error: %@", error);
                }
                if (videoFrame) {
                    IplImageObject *image = [[IplImageObject alloc] initByCopyingCGImage:videoFrame resultChannelCount:4];
                    [self processVideoFrame:image presentationTime:currentFrameTime];
                    [image release];
                }
                
                // Step forward and loop if we are at the end
                [_movie stepForward];
                if (QTTimeCompare(currentFrameTime, [_movie currentTime]) == NSEqualToComparison) {
                    [_movie gotoBeginning];
                }
                
                [_movie detachFromCurrentThread];
                [QTMovie exitQTKitOnThread];
                [pool release];
            });
            dispatch_source_set_timer(_movieFrameExtractTimer, 0, frameDuration * NSEC_PER_SEC, 0);
            dispatch_resume(_movieFrameExtractTimer);
            [attributes release];
        }
    }
    
    return success;
}

- (void)close
{
    // Work around AppKit calling close twice in succession
    if (!closeCalled) {
        closeCalled = YES;
        ProcessLog(@"Closing removed device/file: %@", _sourceIdentifier);
        [[VideoProcessor sharedInstance] noteSourceIdentifierHasDisconnected:_sourceIdentifier];
        
        [_captureSession stopRunning];
        [_captureDecompressedVideoOutput setDelegate:nil];
        if (_movieFrameExtractTimer) {
            dispatch_source_cancel(_movieFrameExtractTimer);
        }
    }
    [super close];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
  didOutputVideoFrame:(CVImageBufferRef)videoFrame
     withSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    // QTCaptureDecompressedVideoOutput is guaranteed to be a CVPixelBufferRef
    IplImageObject *image = [[IplImageObject alloc] initByCopyingCVPixelBuffer:(CVPixelBufferRef)videoFrame
                                                            resultChannelCount:4
                                                              vmCopyIfPossible:YES];
    [self processVideoFrame:image presentationTime:[sampleBuffer presentationTime]];
    [image release];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
didDropVideoFrameWithSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    _frameDropCount++;
    if (_frameDropCount == 10 || _frameDropCount == 100 || _frameDropCount % 1000 == 0) {
        ProcessLog(@"Device %@ dropped %llu total frames", _sourceIdentifier, (unsigned long long)_frameDropCount);
    }
}

// This method will be called on a background thread. It will not be called again until the current call returns.
// Interviening frames may be dropped if the video is a live capture device source. 
- (void)processVideoFrame:(IplImageObject *)image presentationTime:(QTTime)presentationTime
{
    NSTimeInterval presentationTimeInterval;
    if (!QTGetTimeInterval(presentationTime, &presentationTimeInterval)) {
        presentationTimeInterval = CACurrentMediaTime();
    }
    
    [[VideoProcessor sharedInstance] processVideoFrame:image
                                        fromSourceIdentifier:_sourceIdentifier
                                            presentationTime:presentationTimeInterval
                                   debugVideoFrameCompletion:^(IplImageObject *image) {
        [_bitmapOpenGLView renderImage:image];
    }];
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
