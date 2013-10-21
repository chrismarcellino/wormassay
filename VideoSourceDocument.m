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
#import "DeckLinkCaptureDevice.h"

NSString *const CaptureDeviceWasConnectedOrDisconnectedNotification = @"CaptureDeviceWasConnectedOrDisconnectedNotification";

NSString *const AVFCaptureDeviceScheme = @"avfcapturedevice";
NSString *const AVFCaptureDeviceFileType = @"dyn.avfcapturedevice";

NSString *const BlackmagicDeckLinkCaptureDeviceScheme = @"blackmagicdecklink";
NSString *const BlackmagicDeckLinkCaptureDeviceFileType = @"dyn.blackmagicdecklink";



NSURL *URLForAVCaptureDevice(AVCaptureDevice *device)
{
    NSString *uniqueID = [device uniqueID];
    return [[NSURL alloc] initWithScheme:AVFCaptureDeviceScheme
                                    host:@""
                                    path:[@"/" stringByAppendingString:uniqueID]];
}

NSURL *URLForBlackmagicDeckLinkDevice(DeckLinkCaptureDevice *device)
{
    NSString *uniqueID = [device uniqueID];
    return [[NSURL alloc] initWithScheme:BlackmagicDeckLinkCaptureDeviceScheme
                                    host:@""
                                    path:[@"/" stringByAppendingString:uniqueID]];
}

NSString *UniqueIDForCaptureDeviceURL(NSURL *url, BOOL *isBlackmagicDeckLinkDevice)
{
    NSString *uniqueID = nil;
    if ([[url scheme] caseInsensitiveCompare:AVFCaptureDeviceScheme] == NSOrderedSame ||
        [[url scheme] caseInsensitiveCompare:BlackmagicDeckLinkCaptureDeviceScheme] == NSOrderedSame) {
        // Remove the leading slash from the absolute URL path
        uniqueID = [url path];
        if ([uniqueID hasPrefix:@"/"]) {
            uniqueID = [uniqueID substringFromIndex:1];
        }
    }
    
    if (isBlackmagicDeckLinkDevice) {
        *isBlackmagicDeckLinkDevice = [[url scheme] caseInsensitiveCompare:BlackmagicDeckLinkCaptureDeviceScheme] == NSOrderedSame;
    }
    
    return uniqueID;
}

BOOL DeviceIsAppleUSBDevice(AVCaptureDevice *device)
{
    NSString *modelID = [device modelID];
    return modelID && [modelID rangeOfString:@"VendorID_1452"].location != NSNotFound;
}

BOOL DeviceIsUVCDevice(AVCaptureDevice *device)
{
    NSString *modelID = [device modelID];
    return modelID && [modelID rangeOfString:@"UVC"].location != NSNotFound;
}

@interface VideoSourceDocument ()

@property NSSize lastFrameSize;

@end


@implementation VideoSourceDocument

@synthesize lastFrameSize = _lastFrameSize;

+ (void)initialize
{
    if (self == [DeckLinkCaptureDevice class]) {
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(postDevicesChanged) name:AVCaptureDeviceWasConnectedNotification object:nil];
        [center addObserver:self selector:@selector(postDevicesChanged) name:AVCaptureDeviceWasDisconnectedNotification object:nil];
        [center addObserver:self selector:@selector(postDevicesChanged) name:DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification object:nil];
    }
}

+ (void)postDevicesChanged
{
    [[NSNotificationCenter defaultCenter] postNotificationName:CaptureDeviceWasConnectedOrDisconnectedNotification object:nil];
}

+ (NSArray *)cameraDeviceURLsIgnoringBuiltInCamera:(BOOL)ignoreBuiltInCameras useBlackmagicDeckLinkDriver:(BOOL)useDeckLink
{
    NSMutableArray *urls = [NSMutableArray array];
    
    NSMutableArray *deckLinkNames = [NSMutableArray array];
    if (useDeckLink) {
        for (DeckLinkCaptureDevice *device in [DeckLinkCaptureDevice captureDevices]) {
            NSURL *url = URLForBlackmagicDeckLinkDevice(device);
            [urls addObject:url];
            
            // Store the display names to do a best-effort attempt to supress access from AVF
            [deckLinkNames addObject:[device localizedName]];
            [deckLinkNames addObject:[device modelName]];
        }
    }
    
    // Iterate through current capture devices
    for (AVCaptureDevice *device in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
        BOOL isADeckLinkDevice = [deckLinkNames count] > 0 &&
                                    [deckLinkNames containsObject:[device localizedName]] &&
                                    [deckLinkNames containsObject:[device modelID]];
        
        // See if we need to ignore this devices
        if (!isADeckLinkDevice && (!ignoreBuiltInCameras || !DeviceIsAppleUSBDevice(device))) {
            // Construct the URL for the capture device
            NSURL *url = URLForAVCaptureDevice(device);
            [urls addObject:url];
        }
    }
    
    return urls;
}

+ (NSArray *)readableTypes
{
    return [NSArray arrayWithObjects:AVFCaptureDeviceFileType, @"public.movie", nil];
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
    // Videos cannot be created anew
    return nil;
}

- (id)initForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError
{
    // Movies are not writeable
    return nil;
}

- (void)dealloc
{
    if (_frameArrivalQueue) {
        dispatch_release(_frameArrivalQueue);
    }
}

- (NSString *)sourceIdentifier
{
    NSString *sourceIdentifier;
    if (_avCaptureDevice) {
        sourceIdentifier = [[NSString alloc] initWithFormat:@"%@ (%@)", [_avCaptureDevice localizedName], [_avCaptureDevice uniqueID], nil];
    } else if (_deckLinkCaptureDevice) {
        sourceIdentifier = [[NSString alloc] initWithFormat:@"%@ (%@)", [_deckLinkCaptureDevice localizedName], [_deckLinkCaptureDevice uniqueID], nil];
    } else {
        sourceIdentifier = [[self fileURL] path];
    }
    return sourceIdentifier;
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
    if (_urlAsset) {
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
    
    // Remove the icon if this is a capture device
    if (_avCaptureDevice || _deckLinkCaptureDevice) {
        [window setRepresentedURL:nil];
    } else {        // video file
        // Capture devices will adjust their window constraints when the first frame arrives
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
        if (_avCaptureDevice || _deckLinkCaptureDevice) {
            size = NSMakeSize(720.0, 480.0);
        } else {
            NSArray *videoTracks = [_urlAsset tracksWithMediaType:AVMediaTypeVideo];
            AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
            size = [videoTrack naturalSize];
        }
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    BOOL success = NO;
    NSString *fileSourceDisplayName = nil;
    
    // While kCVPixelFormatType_422YpCbCr8 is the strictly most efficient for H.264 output, we use kCVPixelFormatType_32BGRA as
    // it is the best format for both OpenCV and OpenGL processing.
    NSDictionary *bufferAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
                                      [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                      nil];
    // Create the proper capture device/asset
    BOOL isBlackmagicDeckLinkDevice = NO;
    NSString *captureDeviceUniqueID = UniqueIDForCaptureDeviceURL(absoluteURL, &isBlackmagicDeckLinkDevice);
    if (captureDeviceUniqueID && !isBlackmagicDeckLinkDevice) {        // AVFoundation Capture devices
        if (captureDeviceUniqueID) {
            _avCaptureDevice = [AVCaptureDevice deviceWithUniqueID:captureDeviceUniqueID];
            RunLog(@"Opened device \"%@\" with model ID \"%@\".", [self sourceIdentifier], [_avCaptureDevice modelID]);
        } else if (outError) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Unknown capture device ID", nil)
                                                                 forKey:NSLocalizedDescriptionKey];
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
        }
        
        // Start capture
        if ([_avCaptureDevice isInUseByAnotherApplication]) {
            RunLog(@"Warning: device %@ is un use by another application", [_avCaptureDevice localizedName]);
        }
        _captureSession = [[AVCaptureSession alloc] init];
        _captureDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:_avCaptureDevice error:outError];
        if (_captureDeviceInput) {
            _captureVideoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
            [_captureVideoDataOutput setVideoSettings:bufferAttributes];
            [_captureVideoDataOutput setAlwaysDiscardsLateVideoFrames:NO];      // to ensure the saved video doesn't miss frames
            [_captureVideoDataOutput setSampleBufferDelegate:self queue:_frameArrivalQueue];
            
            if ([_captureSession canAddInput:_captureDeviceInput] && [_captureSession canAddOutput:_captureVideoDataOutput]) {
                [_captureSession addInput:_captureDeviceInput];
                [_captureSession addOutput:_captureVideoDataOutput];
                
                // Limit the frame rate to no higher than 30 fps
                for (AVCaptureConnection *connection in [_captureVideoDataOutput connections]) {
                    if ([connection isVideoMinFrameDurationSupported]) {
                        [connection setVideoMinFrameDuration:CMTimeMake(1, 30)];
                    }
                }
                
                [_captureSession startRunning];
                success = YES;
            } else if (outError) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Unable to add inputs to capture session", nil)
                                                                     forKey:NSLocalizedDescriptionKey];
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }
        }
    } else if (captureDeviceUniqueID && isBlackmagicDeckLinkDevice) {     // Blackmagic DeckLink device
        // Make our device
        for (DeckLinkCaptureDevice *captureDevice in [DeckLinkCaptureDevice captureDevices]) {
            if ([[captureDevice uniqueID] isEqual:captureDeviceUniqueID]) {
                _deckLinkCaptureDevice = captureDevice;
                break;
            }
        }
        RunLog(@"Opened device \"%@\" with model ID \"%@\".", [self sourceIdentifier], [_deckLinkCaptureDevice modelName]);
        
        // Start capturing in our ideal mode
        DeckLinkCaptureMode *captureMode = [_deckLinkCaptureDevice highestResolutionCaptureModeWithFieldDominance:DeckLinkFieldDominanceProgressive
                                                                                           targetMinFrameDuration:(1.0 / 30.0)];
        RunLog(@"Available capture modes: %@; selected mode: %@", [_deckLinkCaptureDevice supportedCaptureModes], captureMode);
        [_deckLinkCaptureDevice setSampleBufferDelegate:self queue:_frameArrivalQueue];
        success = [_deckLinkCaptureDevice startCaptureWithCaptureMode:captureMode error:outError];
    } else if ([absoluteURL isFileURL]) {           // Video files
        _urlAsset = [AVAsset assetWithURL:absoluteURL];
        if (_urlAsset && [[_urlAsset tracksWithMediaType:AVMediaTypeVideo] count] > 0) {
            _assetReader = [[AVAssetReader alloc] initWithAsset:_urlAsset error:outError];
            RunLog(@"Opened file \"%@\".", [self sourceIdentifier]);
        }
        
        // Get frames from movie file
        NSArray *videoTracks = [_urlAsset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
        _assetReaderOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:bufferAttributes];
        // This optimization is only available on 10.8+
        if ([_assetReaderOutput respondsToSelector:@selector(setAlwaysCopiesSampleData:)]) {
            [_assetReaderOutput setAlwaysCopiesSampleData:NO];
        }
        if ([_assetReader canAddOutput:_assetReaderOutput]) {
            [_assetReader addOutput:_assetReaderOutput];
            success = [_assetReader startReading];
            if (outError) {
                *outError = [_assetReader error];
            }
        }
        
        fileSourceDisplayName = [[[self fileURL] path] lastPathComponent];
        
        // Get the first frame (async)
        NSTimeInterval frameInterval = 1.0 / [videoTrack nominalFrameRate];
        dispatch_async(_frameArrivalQueue, ^{
            [self getNextVideoFileFrameWithStartTime:CACurrentMediaTime() firstFrameTime:NAN frameInterval:frameInterval];
        });
    }
    
    NSAssert(!_processor, @"processor already exists");
    _processor = [[VideoProcessor alloc] initWithFileOutputDelegate:self fileSourceDisplayName:fileSourceDisplayName];
    [[VideoProcessorController sharedInstance] addVideoProcessor:_processor];
    
    return success;
}

// Called on main thread
- (void)close
{
    if (!_closeCalled) {
        _closeCalled = YES;
        _sendFramesToAssetWriter = NO;
        RunLog(@"Closing %@: %@", (_avCaptureDevice || _deckLinkCaptureDevice) ? @"removed device" : @"file", [self sourceIdentifier]);
        [[VideoProcessorController sharedInstance] removeVideoProcessor:_processor];
        
        if (_avCaptureDevice) {
            [_captureSession stopRunning];
            [_captureVideoDataOutput setSampleBufferDelegate:nil queue:NULL];
        } else if (_deckLinkCaptureDevice) {
            [_deckLinkCaptureDevice stopCapture];
            [_deckLinkCaptureDevice setSampleBufferDelegate:nil queue:NULL];
        } else {
            [_assetReader cancelReading];
            [_urlAsset cancelLoading];
        }
    }
    [super close];
}

// for video file sources. called on a background thread in _frameArrivalQueue.
- (void)getNextVideoFileFrameWithStartTime:(NSTimeInterval)startTime
                            firstFrameTime:(NSTimeInterval)firstFrameTime
                             frameInterval:(NSTimeInterval)frameInterval
{
    if (_closeCalled) {
        return;
    }
    
    CMSampleBufferRef sampleBuffer = [_assetReaderOutput copyNextSampleBuffer];
    
    if (sampleBuffer) {
        [self cmSampleBufferHasArrived:sampleBuffer];
        
        // Figure out when we should ask for the next frame (i.e. at frame rate)
        NSTimeInterval frameTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer));
        NSAssert(isfinite(frameTime), @"invalid frame time");
        if (!isfinite(firstFrameTime)) {
            firstFrameTime = frameTime;
        }
        
        NSTimeInterval currentTime = CACurrentMediaTime();
        NSTimeInterval delayInSeconds = (frameTime - firstFrameTime) - (currentTime - startTime) + frameInterval;
        dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(dispatchTime, _frameArrivalQueue, ^{
            [self getNextVideoFileFrameWithStartTime:startTime firstFrameTime:firstFrameTime frameInterval:frameInterval];
        });
    } else {
         [self videoPlaybackDidEnd];
    }
}

// Called on _frameArrivalQueue
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [self cmSampleBufferHasArrived:sampleBuffer];
}

// Called on _frameArrivalQueue
- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [self logFrameDroppedDuringEncoding];
    [_processor noteVideoFrameWasDropped];
}

// Called on _frameArrivalQueue
- (void)captureDevice:(DeckLinkCaptureDevice *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
    [self cmSampleBufferHasArrived:sampleBuffer];
}

- (void)logFrameDroppedDuringEncoding
{
    // This normally shouldn't happen as we ask for all frames to be queued
    if (_sendFramesToAssetWriter) {
        _recordingFrameDropCount++;
        if (_recordingFrameDropCount == 1 || _recordingFrameDropCount % 10 == 0) {
            RunLog(@"Frames dropped from saved video: %lull", (unsigned long)_recordingFrameDropCount);
            if (_recordingFrameDropCount == 20) {       // i.e. only once per recording
                RunLog(@"To reduced the number of dropped frames, quit all other running programs or use faster computer.");
            }
        }
    }
}

// this must be called on _frameArrivalQueu
- (void)cmSampleBufferHasArrived:(CMSampleBufferRef)sampleBuffer
{
    if (_currentlyProcessingFrame) {
        [_processor noteVideoFrameWasDropped];
    } else {
        _currentlyProcessingFrame = YES;
        
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        CVPixelBufferRef pixelBuffer = CVPixelBufferRetain(CMSampleBufferGetImageBuffer(sampleBuffer));
        
        // Do processing work on another queue so the arrival queue isn't blocked and new frames can be dropped in the interim
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                [self processPixelBufferSynchronously:pixelBuffer];
                CVPixelBufferRelease(pixelBuffer);
            }
            
            // Mark that we're done
            dispatch_sync(_frameArrivalQueue, ^{
                _currentlyProcessingFrame = NO;
            });
        });
    }
    
    // Send all frames to the asset writer if enabled
    if (_sendFramesToAssetWriter) {
        if (_firstFrameToAssetWriter) {
            // Give the start timestamp to the asset writer
            CMTime frameCMTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            [_assetWriter startSessionAtSourceTime:frameCMTime];
            _firstFrameToAssetWriter = NO;
        }
        
        if ([_assetWriterInput isReadyForMoreMediaData]) {
            [_assetWriterInput appendSampleBuffer:sampleBuffer];
        } else {
            [self logFrameDroppedDuringEncoding];
        }
    }
}

// do NOT call on _frameArrivalQueue as this blocks. called on a background thread.
- (void)processPixelBufferSynchronously:(CVImageBufferRef)pixelBuffer
{
    // Ensure we have the proper frame size for this device, correcting for non-square pixels.
    // AVCaptureDecompressedVideoOutput is guaranteed to be a CVPixelBufferRef.
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
                    // Round after multiplying since we want to round the result not the ratio
                    squarePixelBufferSize.width *= horizontalPixel / verticalPixel;
                    squarePixelBufferSize.width = round(squarePixelBufferSize.width);
                } else {
                    squarePixelBufferSize.height *= verticalPixel / horizontalPixel;
                    squarePixelBufferSize.height = round(squarePixelBufferSize.height);
                }
            }
        }
    }
    
    // If our pixel buffer doesn't match this size, or we don't have a square pixel buffer, set attributes and change the requested size.
    if (!NSEqualSizes(bufferSize, squarePixelBufferSize) || !NSEqualSizes(squarePixelBufferSize, [self lastFrameSize])) {
        // Arbitrarily limit UVC devices to 640x480 for maximum compatability. These cameras (webcams) should only be used for barcoding.
        if (_avCaptureDevice && DeviceIsUVCDevice(_avCaptureDevice)) {
            squarePixelBufferSize = NSMakeSize(640.0, 480.0);
        }
        
        [self setLastFrameSize:squarePixelBufferSize];
        
        RunLog(@"Receiving %g x %g video from device \"%@\".", (double)squarePixelBufferSize.width, (double)squarePixelBufferSize.height, [self sourceIdentifier]);
        // Only set a buffer size if we have a non-square pixel size and this is a camera
        if (_captureVideoDataOutput && !NSEqualSizes(bufferSize, squarePixelBufferSize)) {
            NSMutableDictionary *bufferAttributes = [[_captureVideoDataOutput videoSettings] mutableCopy];
            [bufferAttributes setObject:[NSNumber numberWithDouble:squarePixelBufferSize.width] forKey:(id)kCVPixelBufferWidthKey];
            [bufferAttributes setObject:[NSNumber numberWithDouble:squarePixelBufferSize.height] forKey:(id)kCVPixelBufferHeightKey];
            [_captureVideoDataOutput setVideoSettings:bufferAttributes];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self adjustWindowSizing];
        });
    } else {
        // Use CPU (Mach) time to ensure a monotonically increasing time. It can later be subtracted from the current time to determine the sample time/date.
        VideoFrame *frame = [[VideoFrame alloc] initByCopyingCVPixelBuffer:pixelBuffer presentationTime:CACurrentMediaTime()];
        [self processVideoFrame:frame];
    }
}

- (void)processVideoFrame:(VideoFrame *)image
{
    [_processor processVideoFrame:image debugFrameCallback:^(VideoFrame *image) {
        [_bitmapOpenGLView renderImage:image];
    }];
}

- (void)videoPlaybackDidEnd
{
    RunLog(@"Video ended.");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self close];
    });
}

- (NSString *)displayName
{
    NSString *displayName;
    if (_avCaptureDevice) {
        displayName = [_avCaptureDevice localizedName];
    } else if (_deckLinkCaptureDevice) {
        displayName = [_deckLinkCaptureDevice localizedName];
    } else {
        displayName = [super displayName];
    }
    return displayName;
}

- (void)videoProcessor:(VideoProcessor *)vp shouldBeginRecordingToURL:(NSURL *)outputFileURL
{
    dispatch_async(_frameArrivalQueue, ^{
        if (_urlAsset) {
#if WORMASSAY_DEBUG
            RunLog(@"Reencoding video for debug build.");
#else
            return;
#endif
        }
        
        // Create asset writers for output
        NSError *error = nil;
        _assetWriter = [[AVAssetWriter alloc] initWithURL:outputFileURL fileType:AVFileTypeMPEG4 error:&error];
        if (_assetWriter) {
            NSSize size = [self expectedFrameSize];
            NSDictionary *outputSettings = [[NSDictionary alloc] initWithObjectsAndKeys:
                                            AVVideoCodecH264, AVVideoCodecKey,
                                            [NSNumber numberWithInteger:size.width], AVVideoWidthKey,
                                            [NSNumber numberWithInteger:size.height], AVVideoHeightKey,
                                            nil];
            _assetWriterInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:outputSettings sourceFormatHint:NULL];
            [_assetWriterInput setExpectsMediaDataInRealTime:YES];
            [_assetWriter setShouldOptimizeForNetworkUse:NO];
            [_assetWriter addInput:_assetWriterInput];
            [_assetWriter startWriting];
            
            _sendFramesToAssetWriter = YES;
            _firstFrameToAssetWriter = YES;
            _recordingFrameDropCount = 0;
            RunLog(@"Began recording video to disk.");
        }
        if (error) {
            RunLog(@"Error recording video to disk: %@ %@", [error localizedDescription], [error localizedFailureReason]);
        }
    });
}

- (void)videoProcessorShouldStopRecording:(VideoProcessor *)vp completion:(void (^)(NSError *error))completion    // error will be nil upon success
{
    // Ensure we've stopped enqqueing frames safely
    dispatch_async(_frameArrivalQueue, ^{
        _sendFramesToAssetWriter = NO;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // This call blocks so we perform it async
            BOOL success = _assetWriter ? [_assetWriter finishWriting] : YES;
            NSError *error = [_assetWriter error];
            if (!success) {
                RunLog(@"Error finishing recording to file \"%@\": %@", [[_assetWriter outputURL] path], error);
            }
            completion(error);
        });
    });
}

@end
