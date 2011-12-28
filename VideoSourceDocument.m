//
//  VideoSourceDocument.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "VideoSourceDocument.h"
#import "opencv2/core/core_c.h"
#import <QuartzCore/QuartzCore.h>
#import "BitmapOpenGLView.h"
#import "VideoProcessorController.h"
#import "VideoProcessor.h"
#import "VideoFrame.h"

NSString *const CaptureDeviceScheme = @"capturedevice";
NSString *const CaptureDeviceFileType = @"dyn.capturedevice";

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

BOOL DeviceIsAppleUSBDevice(QTCaptureDevice *device)
{
    NSString *modelUniqueID = [device modelUniqueID];
    return modelUniqueID && [modelUniqueID rangeOfString:@"VendorID_1452"].location != NSNotFound;
}

@interface VideoSourceDocument ()

- (void)adjustWindowSizing;
- (void)pixelBufferOrImageHasArrived:(id)pixelBufferOrCIImage isCIImage:(BOOL)isCIImage;
- (void)processCVPixelBufferSynchronously:(CVPixelBufferRef)pixelBuffer;
- (void)processCIImageSynchronously:(CIImage *)image;
- (void)processVideoFrame:(VideoFrame *)image;
- (void)movieDidEnd;

@end


@implementation VideoSourceDocument

@synthesize captureDevice = _captureDevice;
@synthesize movie = _movie;
@synthesize sourceIdentifier = _sourceIdentifier;
@synthesize lastFrameSize;

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
        _frameArrivalQueue = dispatch_queue_create("frame-arrival-queue", NULL);
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
        
        _sourceIdentifier = [[NSString alloc] initWithFormat:@"%@ (%@)",
                             [_captureDevice localizedDisplayName],
                             [captureDeviceUniqueID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
                             nil];
        
        RunLog(@"Opened device \"%@\" with model ID \"%@\".", _sourceIdentifier, [_captureDevice modelUniqueID] ? [_captureDevice modelUniqueID] : @"(none)");
    } else if ([absoluteURL isFileURL]) {
        NSDictionary *attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                    absoluteURL, QTMovieURLAttribute,
                                    [NSNumber numberWithBool:YES], QTMovieOpenForPlaybackAttribute,
                                    [NSNumber numberWithBool:NO], QTMovieOpenAsyncOKAttribute,
                                    nil];
        _movie = [[QTMovie alloc] initWithAttributes:attributes error:outError];
        [attributes release];
        if (_movie) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(movieDidEnd) name:QTMovieDidEndNotification object:_movie];
            
            NSRect frame = NSZeroRect;
            frame.size = [[_movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
            _movieView = [[QTMovieView alloc] initWithFrame:frame];
            [_movieView setMovie:_movie];
            [_movieView setControllerVisible:NO];
            [_movieView setPreservesAspectRatio:YES];
            [_movieView setDelegate:[self retain]];         // released in -close
            
            _sourceIdentifier = [[absoluteURL path] retain];
            RunLog(@"Opened file \"%@\".", _sourceIdentifier);
        }
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
    if (_movie) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieDidEndNotification object:_movie];
    }
    
    [_captureDevice release];
    [_captureSession release];
    [_captureDeviceInput release];
    [_captureDecompressedVideoOutput release];
    dispatch_release(_frameArrivalQueue);
    
    [_movie release];
    [_movieInvisibleWindow release];
    [_movieView release];
    [_ciContext release];
    
    [_processor release];
    [_bitmapOpenGLView release];
    [_sourceIdentifier release];
    [super dealloc];
}

- (void)makeWindowControllers
{
    NSRect visibleScreenFrame = [[NSScreen mainScreen] visibleFrame];
    NSRect contentRect;
    contentRect.size = [self expectedFrameSize];
    contentRect.origin = NSMakePoint(visibleScreenFrame.origin.x,
                                     visibleScreenFrame.origin.y + visibleScreenFrame.size.height - contentRect.size.height);
    
    // Create the window to hold the content view and contrain it to preserve the aspect ratio
    NSUInteger styleMask = NSTitledWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
    if (_movie) {
        styleMask |= NSClosableWindowMask;
    }
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect styleMask:styleMask backing:NSBackingStoreBuffered defer:YES];
    // Enable multi-threaded drawing
    [window setPreferredBackingLocation:NSWindowBackingLocationVideoMemory];
	[window useOptimizedDrawing:YES];       // since there are no overlapping subviews
    [window setOpaque:YES];
    [window setShowsResizeIndicator:NO];
    
    // Insert the bitmap view into the window (the view is created in init so that it is safe to access by the capture threads without locking)
    [_bitmapOpenGLView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [window setContentView:_bitmapOpenGLView];
    
    // Create the window controller
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    [windowController setWindowFrameAutosaveName:[[self fileURL] relativeString]];
    [self addWindowController:windowController];
    [window release];
    [windowController release];
    
    // Remove the icon if this is a capture device
    if (_captureDevice) {
        [window setRepresentedURL:nil];
    }
    
    // Capture devices will adjust their window constraints when the first frame arrives
    if (!_captureDevice) {
        [self adjustWindowSizing];
    }
}

- (void)adjustWindowSizing
{
    NSSize contentSize = [self expectedFrameSize];
    
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

- (NSSize)expectedFrameSize
{
    NSSize size = [self lastFrameSize];
    
    if (size.width == 0 || size.height == 0) {
        if (_captureDevice) {
            size = NSMakeSize(720.0, 480.0);
        } else {
            size = [[_movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
        }
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    BOOL success = NO;
    
    if (_captureDevice) {
        // Start capture
        _captureSession = [[QTCaptureSession alloc] init];
        success = [_captureDevice open:outError];
        if (success) {
            _captureDeviceInput = [[QTCaptureDeviceInput alloc] initWithDevice:_captureDevice];
            // Disable muxed audio devices
            for (QTCaptureConnection *connection in [_captureDeviceInput connections]) {
                if ([[connection mediaType] isEqual:QTMediaTypeSound]) {
                    [connection setEnabled:NO];
                }
            }
            
            success = [_captureSession addInput:_captureDeviceInput error:outError];
            if (success) {
                _captureDecompressedVideoOutput = [[QTCaptureDecompressedVideoOutput alloc] init];
                NSDictionary *bufferAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                  [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                                  nil];
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
        // To play the movie, it must be in the view hiearchy
        _movieInvisibleWindow = [[NSWindow alloc] initWithContentRect:[_movieView frame] styleMask:0 backing:NSBackingStoreBuffered defer:NO];
        [_movieInvisibleWindow setContentView:_movieView];
        [_movieView play:self];
        success = YES;
    }
    
    NSAssert(!_processor, @"processor already exists");
    QTCaptureMovieFileOutput *captureFileOutput = nil;
    NSString *fileSourceFilename = nil;
    if (_captureDevice) {
        captureFileOutput = [[QTCaptureMovieFileOutput alloc] init];
        NSError *error = nil;
        if (![_captureSession addOutput:captureFileOutput error:&error]) {
            RunLog(@"Unable to add QTCaptureFileOutput to capture session: %@", error);
            [captureFileOutput release];
            captureFileOutput = nil;
        }
    } else {
        fileSourceFilename = [[[_movie attributeForKey:QTMovieURLAttribute] path] lastPathComponent];
    }
    _processor = [[VideoProcessor alloc] initWithCaptureFileOutput:captureFileOutput fileSourceFilename:fileSourceFilename];
    [captureFileOutput release];
    [[VideoProcessorController sharedInstance] addVideoProcessor:_processor];
    
    return success;
}

// Called on main thread
- (void)close
{
    if (!_closeCalled) {
        _closeCalled = YES;
        RunLog(@"Closing %@: %@", _captureDevice ? @"removed device" : @"file", _sourceIdentifier);
        [[VideoProcessorController sharedInstance] removeVideoProcessor:_processor];
        
        if (_captureDevice) {
            [_captureSession stopRunning];
            [_captureDecompressedVideoOutput setDelegate:nil];
        } else {
            [NSThread sleepForTimeInterval:0.1];     // work around hard to reproduce CIImage/QTMovieView thread safety issues (brutal hack)
            [_movieView pause:self];
            if ([_movieView delegate] == self) {
                [self autorelease];
                [_movieView setDelegate:nil];
            }
        }
    }
    [super close];
}

// Called on a background thread by the capture output
- (void)captureOutput:(QTCaptureOutput *)captureOutput
  didOutputVideoFrame:(CVImageBufferRef)videoFrame
     withSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    [self pixelBufferOrImageHasArrived:(id)videoFrame isCIImage:NO];
}

// Called on a background thread when using a pre-recorded movie file
- (CIImage *)view:(QTMovieView *)view willDisplayImage:(CIImage *)image
{
    [self pixelBufferOrImageHasArrived:image isCIImage:YES];
    return nil;
}

- (void)pixelBufferOrImageHasArrived:(id)pixelBufferOrCIImage isCIImage:(BOOL)isCIImage
{
    dispatch_sync(_frameArrivalQueue, ^{
        if (_currentlyProcessingFrame) {
            [_processor noteVideoFrameWasDropped];
        } else {
            _currentlyProcessingFrame = YES;
            
            // Do processing work on another queue so the arrival queue isn't blocked and new frames can be dropped in the interim
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                if (isCIImage) {
                    [self processCIImageSynchronously:(CIImage *)pixelBufferOrCIImage];
                } else {
                    [self processCVPixelBufferSynchronously:(CVPixelBufferRef)pixelBufferOrCIImage];
                }
                [pool release];
                
                // Mark that we're done
                dispatch_sync(_frameArrivalQueue, ^{
                    _currentlyProcessingFrame = NO;
                });
            });
        }
    });
}

- (void)processCVPixelBufferSynchronously:(CVPixelBufferRef)pixelBuffer
{
    // Ensure we have the proper frame size for this device, correcting for non-square pixels.
    // QTCaptureDecompressedVideoOutput is guaranteed to be a CVPixelBufferRef.
    NSSize bufferSize = NSMakeSize(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    NSSize squarePixelBufferSize = bufferSize;
    
    CFDictionaryRef aspectRatioDict = CVBufferGetAttachment(pixelBuffer, kCVImageBufferPixelAspectRatioKey, NULL);
    if (aspectRatioDict) {
        CFNumberRef horizontalPixelNumber = CFDictionaryGetValue(aspectRatioDict, kCVImageBufferPixelAspectRatioHorizontalSpacingKey);
        CFNumberRef verticalPixelNumber = CFDictionaryGetValue(aspectRatioDict, kCVImageBufferPixelAspectRatioVerticalSpacingKey);
        if (horizontalPixelNumber && verticalPixelNumber) {
            double horizontalPixel, verticalPixel;
            CFNumberGetValue(horizontalPixelNumber, kCFNumberDoubleType, &horizontalPixel);
            CFNumberGetValue(verticalPixelNumber, kCFNumberDoubleType, &verticalPixel);
            if (horizontalPixel != verticalPixel) {
                if (horizontalPixel > verticalPixel) {
                    squarePixelBufferSize.width *= horizontalPixel / verticalPixel;
                } else {
                    squarePixelBufferSize.height *= verticalPixel / horizontalPixel;                    
                }
            }
        }
    }
    
    // If our pixel buffer doesn't match this size, or we don't have a square pixel buffer, set attributes and change the requested size.
    if (!NSEqualSizes(bufferSize, squarePixelBufferSize) || !NSEqualSizes(squarePixelBufferSize, [self lastFrameSize])) {
        [self setLastFrameSize:squarePixelBufferSize];
        
        RunLog(@"Receiving %g x %g video from device \"%@\".", (double)squarePixelBufferSize.width, (double)squarePixelBufferSize.height, _sourceIdentifier);
        // Only set a buffer size if we have a non-square pixel size
        if (!NSEqualSizes(bufferSize, squarePixelBufferSize)) {
            NSMutableDictionary *bufferAttributes = [[_captureDecompressedVideoOutput pixelBufferAttributes] mutableCopy];
            [bufferAttributes setObject:[NSNumber numberWithDouble:squarePixelBufferSize.width] forKey:(id)kCVPixelBufferWidthKey];
            [bufferAttributes setObject:[NSNumber numberWithDouble:squarePixelBufferSize.height] forKey:(id)kCVPixelBufferHeightKey];
            [_captureDecompressedVideoOutput setPixelBufferAttributes:bufferAttributes];
            [bufferAttributes release];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self adjustWindowSizing];
        });
    } else {
        // Use CPU (Mach) time to ensure a monotonically increasing time. It can later be subtracted from the current time to determine the sample time/date.
        VideoFrame *frame = [[VideoFrame alloc] initByCopyingCVPixelBuffer:pixelBuffer
                                                        resultChannelCount:4
                                                          presentationTime:CACurrentMediaTime()];
        [self processVideoFrame:frame];
        [frame release];
    }
}

- (void)processCIImageSynchronously:(CIImage *)image
{
    // Reuse the context for performance reasons
    if (!_ciContext) {
        _ciContext = [[CIContext contextWithCGContext:NULL options:nil] retain];
    }
    
    VideoFrame *frame = [[VideoFrame alloc] initByCopyingCIImage:image
                                                  usingCIContext:_ciContext
                                                      bitmapSize:[[_movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue]
                                              resultChannelCount:4
                                                presentationTime:CACurrentMediaTime()];
    [self processVideoFrame:frame];
    [frame release];
}

- (void)processVideoFrame:(VideoFrame *)image
{
    [_processor processVideoFrame:image debugFrameCallback:^(VideoFrame *image) {
        [_bitmapOpenGLView renderImage:image];
    }];
}

- (void)movieDidEnd
{
    RunLog(@"Movie ended.");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self close];
    });
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
