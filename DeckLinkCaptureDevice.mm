//
//  DeckLinkCaptureDevice.mm
//  WormAssay
//
//  Created by Chris Marcellino on 10/16/13.
//  Copyright (c) 2013 Chris Marcellino. All rights reserved.
//

#import "DeckLinkCaptureDevice.h"
#import "DeckLinkAPI.h"

using namespace std;

NSString *const DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification = @"DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification";

// C++ shim subclass for callbacks
class DeckLinkCaptureDeviceCPP : public IDeckLinkInputCallback {
public:
    DeckLinkCaptureDeviceCPP(DeckLinkCaptureDevice *objcObject) : _objcObject(objcObject) {}
    
	// IUnknown needs only a dummy implementation as this C++ obj will be solely owned by the ObjC class.
	virtual HRESULT QueryInterface(REFIID iid, LPVOID *ppv) { return E_NOINTERFACE; }
	virtual ULONG AddRef() { return 1; }
	virtual ULONG Release() { return 1; }
    
	// IDeckLinkInputCallback interface
    virtual HRESULT VideoInputFormatChanged(BMDVideoInputFormatChangedEvents notificationEvents, IDeckLinkDisplayMode *newMode, BMDDetectedVideoInputFormatFlags detectedSignalFlags);
    virtual HRESULT VideoInputFrameArrived(IDeckLinkVideoInputFrame* videoFrame, IDeckLinkAudioInputPacket* audioPacket);
    
private:
	__weak DeckLinkCaptureDevice *_objcObject;  // not retained
};

// C++ subclass for notifications
class DeckLinkStreamingDeviceNotifier : public IBMDStreamingDeviceNotificationCallback {
public:
	// IUnknown needs only a dummy implementation as this C++ obj will be an eternal singleton
	virtual HRESULT QueryInterface(REFIID iid, LPVOID *ppv) { return E_NOINTERFACE; }
	virtual ULONG AddRef() { return 1; }
	virtual ULONG Release() { return 1; }
    
    // IBMDStreamingDeviceNotificationCallback interface
    virtual HRESULT StreamingDeviceArrived(IDeckLink* device) {
        @autoreleasepool {
            [[NSNotificationCenter defaultCenter] postNotificationName:DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification object:nil];
        }
        return S_OK;
    }
    
    virtual HRESULT StreamingDeviceRemoved(IDeckLink* device) {
        @autoreleasepool {
            [[NSNotificationCenter defaultCenter] postNotificationName:DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification object:nil];
        }
        return S_OK;
    }
    
    virtual HRESULT StreamingDeviceModeChanged(IDeckLink* device, BMDStreamingDeviceMode mode) { return S_OK; };
};


// C++ safe ivars
@interface DeckLinkCaptureDevice () {
    DeckLinkCaptureDeviceCPP::DeckLinkCaptureDeviceCPP* _cppObject;
    dispatch_queue_t _lockQueue;
    
    IDeckLink* _deckLink;
    IDeckLinkInput *_deckLinkInput;
    
    __weak id<DeckLinkCaptureDeviceSampleBufferDelegate> _sampleBufferDelegate;
    dispatch_queue_t _callbackQueue;
    
    NSArray *_captureModesSearchList;       // nil if not capturing
    NSUInteger _captureModesSearchListIndex;
    BOOL _lastFrameHasValidInputSource;
    BOOL _retryDispatchAfterPending;
}

@end


@interface DeckLinkCaptureMode ()

@property NSString *fieldDominanceDisplayName;
@property BMDDisplayMode deckLinkDisplayMode;

- (id)initWithIDeckLinkDisplayMode:(IDeckLinkDisplayMode*)displayMode;

@end


@implementation DeckLinkCaptureDevice

+ (void)initialize
{
    static IBMDStreamingDiscovery *discovery = NULL;
    
    if (self == [DeckLinkCaptureDevice class]) {
        NSAssert(!discovery, @"discovery object already exists");
        discovery = CreateBMDStreamingDiscoveryInstance();      // will return NULL if driver not installed
        if (discovery) {
            discovery->InstallDeviceNotifications(new DeckLinkStreamingDeviceNotifier());
        }
    }
}

+ (BOOL)isDriverInstalled
{
    BOOL installed = NO;
    
	IDeckLinkIterator *deckLinkIterator = CreateDeckLinkIteratorInstance();
    if (deckLinkIterator) {
        installed = YES;
        deckLinkIterator->Release();
    }
    
    return installed;
}

+ (NSString *)deckLinkSystemVersion
{
    NSString *systemVersion = nil;
    
    IDeckLinkAPIInformation *apiInfo = CreateDeckLinkAPIInformationInstance();
    if (apiInfo) {
        CFStringRef retainedString = NULL;
        apiInfo->GetString(BMDDeckLinkAPIVersion, &retainedString);   // this returns a +1 retained string
        if (retainedString) {
            systemVersion = [(__bridge id)retainedString copy];
            CFRelease(retainedString);
        }
        apiInfo->Release();
    }
    
    return systemVersion;
}

+ (NSArray *)captureDevices
{
    NSMutableArray *devices = [[NSMutableArray alloc] init];
	
	// Create an iterator
	IDeckLinkIterator *deckLinkIterator = CreateDeckLinkIteratorInstance();
	if (deckLinkIterator) {
        // List all DeckLink devices
        IDeckLink* deckLink = NULL;
        while (deckLinkIterator->Next(&deckLink) == S_OK) {
            // Add device to the device list
            if (deckLink) {
                DeckLinkCaptureDevice *device = [[self alloc] initWithDeckLinkInterface:deckLink];
                if (device) {
                    [devices addObject:device];
                }
                deckLink->Release();
            }
        }
        
		deckLinkIterator->Release();
	}
	
	return devices;
}

- (id)initWithDeckLinkInterface:(IDeckLink*)deckLink
{
    if ((self = [super init])) {
        _deckLink = deckLink;
        _deckLink->AddRef();
        
        _deckLink->QueryInterface(IID_IDeckLinkInput, (void**)&_deckLinkInput);        // implicit +1 ref count
        if (!_deckLinkInput) {
            return nil;
        }
        
        _cppObject = new DeckLinkCaptureDeviceCPP::DeckLinkCaptureDeviceCPP(self);
        // Set capture callback
        _deckLinkInput->SetCallback(_cppObject);
        
        _lockQueue = dispatch_queue_create("decklink-device-lock-queue", NULL);
    }
    return self;
}

- (void)dealloc
{
    if (_deckLink) {
        _deckLink->Release();
    }
    if (_deckLinkInput) {
        _deckLinkInput->StopStreams();
        _deckLinkInput->SetCallback(NULL);
        _deckLinkInput->Release();
    }
    
    delete _cppObject;
}

- (NSString *)uniqueID
{
    NSString *localizedName = [self localizedName];
    NSString *modelName = [self modelName];
    // Our only option for a psuedo-unqiue id is to use these strings
    NSString *uniqueID =  [NSString stringWithFormat:@"%@-%@", modelName, localizedName];
    NSArray *words = [uniqueID componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [words componentsJoinedByString:@""];
}

- (NSString *)localizedName
{
    NSString *name = nil;
    
    // Get the name of this device
    CFStringRef	cfStrName = NULL;
    _deckLink->GetDisplayName(&cfStrName);
    if (cfStrName) {
        name = [(__bridge NSString *)cfStrName copy];
        CFRelease(cfStrName);
    } else {
        name = NSLocalizedString(@"DeckLink", nil);
    }
    
    return name;
}

- (NSString *)modelName
{
    NSString *model = nil;
    
    // Get the model of this device
    CFStringRef	cfStrName = NULL;
    _deckLink->GetModelName(&cfStrName);
    if (cfStrName) {
        model = [(__bridge NSString *)cfStrName copy];
        CFRelease(cfStrName);
    } else {
        model = @"DeckLink";
    }
    
    return model;
}

- (NSArray *)allCaptureModes
{
    NSMutableArray *modes = [NSMutableArray array];
    
    IDeckLinkDisplayModeIterator* displayModeIterator = NULL;
    _deckLinkInput->GetDisplayModeIterator(&displayModeIterator);
    if (displayModeIterator) {
        IDeckLinkDisplayMode* displayMode = NULL;
		while (displayModeIterator->Next(&displayMode) == S_OK) {
            if (displayMode) {
                DeckLinkCaptureMode *captureMode = [[DeckLinkCaptureMode alloc] initWithIDeckLinkDisplayMode:displayMode];
                [modes addObject:captureMode];
                
                // Release the displayMode
                displayMode->Release();
            }
        }
        
		displayModeIterator->Release();
    }
    
    return modes;
}

- (NSArray *)allCaptureModesSortedByDescendingResolutionAndFrameRate
{
    return [[self allCaptureModes] sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
        CGFloat width1 = [obj1 frameSize].width;
        CGFloat width2 = [obj2 frameSize].width;
        
        // Most important factor is frame size (width)
        if (width1 < width2) {
            return NSOrderedDescending;     // reverse the normal convention to have largest first
        } else if (width1 > width2) {
            return NSOrderedAscending;
        } else {
            // Next we must move interlaced sources ahead of non-interlaced sources so we don't have a false
            // positive on an incorrectly interlaced progressive field
            DeckLinkFieldDominance fd1 = [obj1 fieldDominance];
            DeckLinkFieldDominance fd2 = [obj2 fieldDominance];
            if (DeckLinkFieldDominanceIsInterlaced(fd1) && !DeckLinkFieldDominanceIsInterlaced(fd2)) {
                return NSOrderedAscending;
            } else if (!DeckLinkFieldDominanceIsInterlaced(fd1) && DeckLinkFieldDominanceIsInterlaced(fd2)) {
                return NSOrderedDescending;
            } else {
                // Last, pick the highest frame rate (lowest frame duration) first
                NSTimeInterval frameDuration1 = [obj1 frameDuration];
                NSTimeInterval frameDuration2 = [obj2 frameDuration];
                
                if (frameDuration1 < frameDuration2) {
                    return NSOrderedAscending;
                } else if (frameDuration1 > frameDuration2) {
                    return NSOrderedDescending;
                } else {
                    return NSOrderedSame;
                }
            }
        }
    }];
}

- (void)setSampleBufferDelegate:(id<DeckLinkCaptureDeviceSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue
{
    dispatch_sync(_lockQueue, ^{
        _callbackQueue = sampleBufferCallbackQueue;
        _sampleBufferDelegate = sampleBufferDelegate;
    });
}

- (BOOL)startCaptureWithCaptureMode:(DeckLinkCaptureMode *)captureMode error:(NSError **)outError
{
    __block BOOL result;
    
    dispatch_sync(_lockQueue, ^{
        _captureModesSearchList = [NSArray arrayWithObject:captureMode];
        _captureModesSearchListIndex = 0;
        result = [self enableVideoInputInCurrentModeWithError:outError];
    });
    
    return result;
}

// can't return a result or error here immediately as this is an async and indefinite search.
- (void)startCaptureWithSearchForModeWithModes:(NSArray *)captureModeSearchList
{
    dispatch_sync(_lockQueue, ^{
        _captureModesSearchList = [captureModeSearchList copy];
        _captureModesSearchListIndex = 0;
        NSAssert([_captureModesSearchList count] > 0, @"search list was empty");
        [self enableVideoInputInCurrentModeWithError:nil];  // eat temporary errors
    });
}

- (BOOL)enableVideoInputInCurrentModeWithError:(NSError **)outError
{
    NSAssert(_captureModesSearchList, @"no search list");
    BOOL success = NO;
    // Stop in case we're already running
    _deckLinkInput->StopStreams();
    
    // See if input mode change events are supported
    bool supportsFormatDetection = NO;
    IDeckLinkAttributes* deckLinkAttributes = NULL;
    _deckLink->QueryInterface(IID_IDeckLinkAttributes, (void**)&deckLinkAttributes);
    if (deckLinkAttributes) {
        deckLinkAttributes->GetFlag(BMDDeckLinkSupportsInputFormatDetection, &supportsFormatDetection);
        deckLinkAttributes->Release();
    }
    
    DeckLinkCaptureMode *captureMode = [_captureModesSearchList objectAtIndex:_captureModesSearchListIndex];
    BMDDisplayMode displayMode = [captureMode deckLinkDisplayMode];
    // YUV is the common denominator format of the DeckLink SDK
    BMDPixelFormat pixelFormat = bmdFormat8BitYUV;
    // Enable input video mode detection if the device supports it
    BMDVideoInputFlags videoInputFlags = supportsFormatDetection ? bmdVideoInputEnableFormatDetection : bmdVideoInputFlagDefault;
    
    BMDDisplayModeSupport supported = bmdDisplayModeNotSupported;
    _deckLinkInput->DoesSupportVideoMode(displayMode, pixelFormat, videoInputFlags, &supported, NULL);
    if (supported == bmdDisplayModeSupported || supported == bmdDisplayModeSupportedWithConversion) {
        // Set the video input mode
        if (_deckLinkInput->EnableVideoInput(displayMode, pixelFormat, videoInputFlags) == S_OK) {
            if (_deckLinkInput->StartStreams() == S_OK) {
                success = YES;
            } else if (outError) {
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:NSLocalizedString(@"Unable to start the DeckLink stream.", nil)
                                                                     forKey:NSLocalizedDescriptionKey];
                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }
        } else if (outError) {
            NSString *description = [NSString stringWithFormat:NSLocalizedString(@"Unable to enable Blackmagic DeckLink video output for %@ in mode %@.", nil),
                                     [self localizedName], captureMode];
            NSString *recoverySuggestion = NSLocalizedString(@"Close any applications that may be using the device and verify that the camera is set to use supported settings.", nil);
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey,
                                      recoverySuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                      nil];
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
        }
    }  else if (outError) {
        NSString *description = [NSString stringWithFormat:NSLocalizedString(@"Unable to obtain 422YpCbCr8 output for %@ in mode %@.", nil),
                                 [self localizedName], captureMode];
        NSString *recoverySuggestion = NSLocalizedString(@"Contact the WormAssay authors for further assistance.", nil);
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey,
                                  recoverySuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                  nil];
        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
    }
    
    if (!success) {
        [self retryCaptureWithNextModeAfterDelay];
    }
    
    return success;
}

- (void)stopCapture
{
    dispatch_sync(_lockQueue, ^{
        _deckLinkInput->StopStreams();
        _captureModesSearchList = nil;
        _captureModesSearchListIndex = NSNotFound;
    });
}

- (void)retryCaptureWithNextModeAfterDelay
{
    // only one dispatch_after should be in flight at once
    if (!_retryDispatchAfterPending) {
        _retryDispatchAfterPending = YES;
        _deckLinkInput->StopStreams();
        
        NSTimeInterval delay = 1.0 / 10.0;      // don't retry immediately to avoid tight polling and more coorect frames to arrive
        dispatch_time_t dispatchTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));
        dispatch_after(dispatchTime, _lockQueue, ^{
            _retryDispatchAfterPending = NO;
            // ensure that capture hasn't been stopped or valid frames have been received in the interim
            if (_captureModesSearchList && !_lastFrameHasValidInputSource) {
                // move to the next item in the queue looping if necessary
                _captureModesSearchListIndex++;
                _captureModesSearchListIndex %= [_captureModesSearchList count];
                [self enableVideoInputInCurrentModeWithError:nil];
            }
        });
    }
}

- (void)videoInputFormatChangedWithNotificationEvents:(BMDVideoInputFormatChangedEvents)notificationEvents
                                              newMode:(IDeckLinkDisplayMode *)newMode
                                  detectedSignalFlags:(BMDDetectedVideoInputFormatFlags)detectedSignalFlags
{
    DeckLinkCaptureMode *captureMode = [[DeckLinkCaptureMode alloc] initWithIDeckLinkDisplayMode:newMode];
    dispatch_sync(_lockQueue, ^{
        // Must check and lock atomically to ensure there is no race where a client may disable and we reenable
        if (_captureModesSearchList && [_captureModesSearchList containsObject:captureMode]) {
            _captureModesSearchListIndex = 0;        // arbitrary; will begin next search from the top
            [self enableVideoInputInCurrentModeWithError:nil];
        }
    });
}

static void pixelBufferReleaseBytesCallback(void *releaseRefCon, const void *baseAddress)
{
    ((IDeckLinkVideoInputFrame*)releaseRefCon)->Release();
}

- (void)videoInputFrameArrived:(IDeckLinkVideoInputFrame*)videoFrame audioPacket:(IDeckLinkAudioInputPacket*)audioPacket
{
    dispatch_sync(_lockQueue, ^{
        _lastFrameHasValidInputSource = videoFrame && !(videoFrame->GetFlags() & bmdFrameHasNoInputSource);
        void *baseAddress = NULL;
        if (videoFrame) {
            videoFrame->GetBytes(&baseAddress);
        }
        
        if (_captureModesSearchList && !_lastFrameHasValidInputSource) {
            [self retryCaptureWithNextModeAfterDelay];
        } else if (_captureModesSearchList && baseAddress) {
            videoFrame->AddRef();
            CVPixelBufferRef pixelBuffer = NULL;
            // ensure our two video code constant FOURCC enum types are equivalent
#if !(kCMPixelFormat_422YpCbCr8 == bmdFormat8BitYUV && \
    kCMPixelFormat_422YpCbCr10 == bmdFormat10BitYUV && \
    kCMPixelFormat_32BGRA == bmdFormat8BitBGRA && \
    kCMPixelFormat_32ARGB == bmdFormat8BitARGB)
#error sanity check of useful FOURCC codes failed
#endif
            CVReturn result = CVPixelBufferCreateWithBytes(NULL,
                                                           videoFrame->GetWidth(),
                                                           videoFrame->GetHeight(),
                                                           videoFrame->GetPixelFormat(),
                                                           baseAddress,
                                                           videoFrame->GetRowBytes(),
                                                           pixelBufferReleaseBytesCallback,
                                                           videoFrame,
                                                           NULL,
                                                           &pixelBuffer);
            if (pixelBuffer) {
                // Get timestamps
                int32_t timescale = 60000;    // good numerator for 24, 29.97, 30 and 60 fps
                BMDTimeValue frameTime;
                BMDTimeValue frameDuration;
                videoFrame->GetStreamTime(&frameTime, &frameDuration, timescale);
                
                CMTime presentationTimeStamp = CMTimeMake(frameTime, timescale);
                CMTime duration = CMTimeMake(frameDuration, timescale);
                CMSampleTimingInfo sampleTiming = { duration, presentationTimeStamp, kCMTimeInvalid };
                
                // Create the format description
                CMVideoFormatDescriptionRef formatDescription = NULL;
                CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &formatDescription);
                
                CMSampleBufferRef sampleBuffer = NULL;
                CMSampleBufferCreateForImageBuffer(NULL,
                                                   pixelBuffer,
                                                   YES,
                                                   NULL,
                                                   NULL,
                                                   formatDescription,
                                                   &sampleTiming,
                                                   &sampleBuffer);
                CFRelease(formatDescription);
                CFRelease(pixelBuffer);
                
                NSAssert(_sampleBufferDelegate && _callbackQueue, @"delegate and queue must be set when capturing is enabled");
                dispatch_async(_callbackQueue, ^{
                    DeckLinkCaptureMode *mode = [_captureModesSearchList objectAtIndex:_captureModesSearchListIndex];
                    [_sampleBufferDelegate captureDevice:self didOutputSampleBuffer:sampleBuffer inCaptureMode:mode];
                    CFRelease(sampleBuffer);
                });
            } else {
                NSLog(@"Unable to create pixel buffer. CVPixelBufferCreateWithBytes returned %i.", result);
            }
        }
    });
}

@end


@implementation DeckLinkCaptureMode

@synthesize displayName = _displayName;
@synthesize frameSize = _frameSize;
@synthesize frameDuration = _frameDuration;
@synthesize fieldDominance = _fieldDominance;
@synthesize fieldDominanceDisplayName = _fieldDominanceDisplayName;
@synthesize deckLinkDisplayMode = _deckLinkDisplayMode;

- (id)initWithIDeckLinkDisplayMode:(IDeckLinkDisplayMode*)displayMode
{
    if ((self = [super init])) {
        // Get the description string
        CFStringRef modeName = NULL;
        displayMode->GetName(&modeName);
        if (modeName) {
            _displayName = [(__bridge NSString *)modeName copy];
            CFRelease(modeName);
        } else {
            _displayName = NSLocalizedString(@"Unknown mode", nil);
        }
        
        // Get the frame size
        long width = displayMode->GetWidth();
        long height = displayMode->GetHeight();
        _frameSize = NSMakeSize(width, height);
        
        // Get the frame rate
        BMDTimeValue frameDuration = 0;
        BMDTimeScale timeScale = 1;
        displayMode->GetFrameRate(&frameDuration, &timeScale);
        _frameDuration = (double)frameDuration / (double)timeScale;
        
        // Get the field dominance
        switch (displayMode->GetFieldDominance()) {
            case bmdProgressiveFrame:
                _fieldDominance = DeckLinkFieldDominanceProgressive;
                _fieldDominanceDisplayName = NSLocalizedString(@"progressive", nil);
                break;
            case bmdProgressiveSegmentedFrame:
                _fieldDominance = DeckLinkFieldDominanceProgressiveSegmented;
                _fieldDominanceDisplayName = NSLocalizedString(@"progressive segmented", nil);
                break;
            case bmdLowerFieldFirst:
                _fieldDominance = DeckLinkFieldDominanceInterlacedLowerFieldFirst;
                _fieldDominanceDisplayName = NSLocalizedString(@"interlaced (lower field first)", nil);
                break;
            case bmdUpperFieldFirst:
                _fieldDominance = DeckLinkFieldDominanceInterlacedUpperFieldFirst;
                _fieldDominanceDisplayName = NSLocalizedString(@"interlaced (upper field first)", nil);
                break;
            default:
                _fieldDominance = DeckLinkFieldDominanceUnknown;
                _fieldDominanceDisplayName = NSLocalizedString(@"unknown", nil);
                break;
        }
        
        // Get the internal mode enum type
        _deckLinkDisplayMode = displayMode->GetDisplayMode();
    }
    return self;
}

- (BOOL)isEqual:(id)object
{
    return (self == object) ||
        (object &&
        NSEqualSizes(_frameSize, [object frameSize]) &&
        _frameDuration == [object frameDuration] &&
        _fieldDominance == [object fieldDominance] &&
        _deckLinkDisplayMode == [object deckLinkDisplayMode]);
}

- (NSString *)description
{
    return [NSString stringWithFormat:NSLocalizedString(@"%@ (frame size %gx%g, frame duration %g (%g fps), field dominance %@)", nil),
            _displayName, _frameSize.width, _frameSize.height, _frameDuration, 1.0 / _frameDuration, _fieldDominanceDisplayName];
}

@end


// DeckLinkCaptureDeviceCPP implementation
HRESULT DeckLinkCaptureDeviceCPP::VideoInputFormatChanged(BMDVideoInputFormatChangedEvents notificationEvents, IDeckLinkDisplayMode *newMode, BMDDetectedVideoInputFormatFlags detectedSignalFlags) {
    @autoreleasepool {
        [_objcObject videoInputFormatChangedWithNotificationEvents:notificationEvents newMode:newMode detectedSignalFlags:detectedSignalFlags];
    }
    return S_OK;
}

HRESULT DeckLinkCaptureDeviceCPP::VideoInputFrameArrived(IDeckLinkVideoInputFrame* videoFrame, IDeckLinkAudioInputPacket* audioPacket) {
    @autoreleasepool {
        [_objcObject videoInputFrameArrived:videoFrame audioPacket:audioPacket];
    }
    return S_OK;
}

