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
	DeckLinkCaptureDevice *_objcObject;  // weak
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
    
    virtual HRESULT StreamingDeviceModeChanged (IDeckLink* device, BMDStreamingDeviceMode mode) { return S_OK; };
};


// C++ safe ivars
@interface DeckLinkCaptureDevice () {
    DeckLinkCaptureDeviceCPP::DeckLinkCaptureDeviceCPP* _cppObject;
    IDeckLink* _deckLink;
    IDeckLinkInput *_deckLinkInput;
    dispatch_queue_t _lock;
    dispatch_queue_t _callbackQueue;
    __weak id<DeckLinkCaptureDeviceSampleBufferDelegate> _sampleBufferDelegate;
    BOOL _capturingEnabled;
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
        _lock = dispatch_queue_create("decklink-device-atomicity-queue", NULL);
        _cppObject = new DeckLinkCaptureDeviceCPP::DeckLinkCaptureDeviceCPP(self);
        
        _deckLink = deckLink;
        _deckLink->AddRef();
        
        _deckLink->QueryInterface(IID_IDeckLinkInput, (void**)&_deckLinkInput);        // implicit +1 ref count
        if (!_deckLinkInput) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    [self stopCapture];
    
    dispatch_release(_lock);
    delete _cppObject;
    
    if (_deckLink) {
        _deckLink->Release();
    }
    if (_deckLinkInput) {
        _deckLinkInput->Release();
    }
    if (_callbackQueue) {
        dispatch_release(_callbackQueue);
    }
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

- (NSArray *)supportedCaptureModes
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

- (DeckLinkCaptureMode *)highestResolutionCaptureModeWithFieldDominance:(DeckLinkFieldDominance)fieldDominance
                                                 targetMinFrameDuration:(NSTimeInterval)targetMinFrameDuration
{
    DeckLinkCaptureMode *bestMode = nil;
    
    targetMinFrameDuration -= FLT_EPSILON;      // FLT gives us more room for error
    
    // If this default is set, return early with this mode
    NSString *const forceDeckLinkModeIndexDefaultsKey = @"ForceDeckLinkModeIndex";
    NSUInteger val = (NSUInteger)[[NSUserDefaults standardUserDefaults] integerForKey:forceDeckLinkModeIndexDefaultsKey];
    if (val > 0) {
        val--;      // switch from natural to array indexing
        NSArray *captureModes = [self supportedCaptureModes];
        if (val < [captureModes count]) {
            bestMode = [captureModes objectAtIndex:val];
            NSLog(@"%@ defaults key set--forcing mode %@", forceDeckLinkModeIndexDefaultsKey, bestMode);
        } else {
            NSLog(@"%@ defaults key set beyond bounds (%lull)", forceDeckLinkModeIndexDefaultsKey, (unsigned long)[captureModes count]);
        }
    }
    
    if (!bestMode) {
        for (DeckLinkCaptureMode *mode in [self supportedCaptureModes]) {
            // Start with the first, since barring the following rules, we want the frontmost mode
            if (!bestMode) {
                bestMode = mode;
            }
            // See if the this mode is better than our current one. Our highest priority is getting a large feed.
            // 1080 is ideal, but if the user has a camera set to provide a larger feed (e.g 2k/4k), we will accept it.
            else if ([mode frameSize].height > [bestMode frameSize].height) {
                bestMode = mode;
            }
            // Next, we prefer progressive scan
            else if ([bestMode fieldDominance] != DeckLinkFieldDominanceProgressive && [mode fieldDominance] == DeckLinkFieldDominanceProgressive) {
                bestMode = mode;
            }
            // Finally, if those prior rules haven't determined the mode, lets aim for <= 30 fps
            else if ([bestMode frameDuration] < targetMinFrameDuration && [mode frameDuration] >= targetMinFrameDuration) {
                bestMode = mode;
            }
        }
    }
    
    return bestMode;
}

- (void)setSampleBufferDelegate:(id<DeckLinkCaptureDeviceSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue
{
    dispatch_sync(_lock, ^{
        NSAssert(_callbackQueue, @"sampleBufferCallbackQueue is required)");
        _callbackQueue = sampleBufferCallbackQueue;
        dispatch_retain(_callbackQueue);
        
        _sampleBufferDelegate = sampleBufferDelegate;
    });
}

- (BOOL)startCaptureWithCaptureMode:(DeckLinkCaptureMode *)captureMode error:(NSError **)outError
{
    __block BOOL succcess = NO;
    
    dispatch_sync(_lock, ^{
        // In case the caller just wants to update captureMode, or this is in response to a format change notification
        if (_capturingEnabled) {
            _deckLinkInput->StopStreams();
            _capturingEnabled = NO;
        }
        
        // See if input mode change events are supported
        bool supportsFormatDetection = NO;
        IDeckLinkAttributes* deckLinkAttributes = NULL;
        _deckLink->QueryInterface(IID_IDeckLinkAttributes, (void**)&deckLinkAttributes);
        if (deckLinkAttributes) {
            deckLinkAttributes->GetFlag(BMDDeckLinkSupportsInputFormatDetection, &supportsFormatDetection);
            deckLinkAttributes->Release();
        }
        
        // Set capture callback
        _deckLinkInput->SetCallback(_cppObject);
        
        BMDDisplayMode displayMode = [captureMode deckLinkDisplayMode];
        // We require BGRA for our image pipeline.
        BMDPixelFormat pixelFormat = bmdFormat8BitBGRA;
        // Enable input video mode detection if the device supports it
        BMDVideoInputFlags videoInputFlags = supportsFormatDetection ? bmdVideoInputEnableFormatDetection : bmdVideoInputFlagDefault;
        
        BMDDisplayModeSupport supported = bmdDisplayModeNotSupported;
        _deckLinkInput->DoesSupportVideoMode(displayMode, pixelFormat, videoInputFlags, &supported, NULL);
        if (supported == bmdDisplayModeSupported || supported == bmdDisplayModeSupportedWithConversion) {
            // Set the video input mode
            if (_deckLinkInput->EnableVideoInput(displayMode, pixelFormat, videoInputFlags) == S_OK) {
                if (_deckLinkInput->StartStreams() == S_OK) {
                    _capturingEnabled = YES;
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
            NSString *description = [NSString stringWithFormat:NSLocalizedString(@"Unable to obtain BGRA output for %@ in mode %@.", nil),
                                     [self localizedName], captureMode];
            NSString *recoverySuggestion = NSLocalizedString(@"Contact the WormAssay authors for further assistance.", nil);
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:description, NSLocalizedDescriptionKey,
                                      recoverySuggestion, NSLocalizedRecoverySuggestionErrorKey,
                                      nil];
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
        }
        
        succcess = _capturingEnabled;
    });
    
    return succcess;
}

- (void)stopCapture
{
    dispatch_sync(_lock, ^{
        _deckLinkInput->StopStreams();
        _capturingEnabled = NO;
    });
}

- (void)videoInputFormatChangedWithNotificationEvents:(BMDVideoInputFormatChangedEvents)notificationEvents
                                              newMode:(IDeckLinkDisplayMode *)newMode
                                  detectedSignalFlags:(BMDDetectedVideoInputFormatFlags)detectedSignalFlags
{
    DeckLinkCaptureMode *captureMode = [[DeckLinkCaptureMode alloc] initWithIDeckLinkDisplayMode:newMode];
    [self startCaptureWithCaptureMode:captureMode error:nil];
}

static void pixelBufferReleaseBytesCallback(void *releaseRefCon, const void *baseAddress)
{
    ((IDeckLinkVideoInputFrame*)releaseRefCon)->Release();
}

- (void)videoInputFrameArrived:(IDeckLinkVideoInputFrame*)videoFrame audioPacket:(IDeckLinkAudioInputPacket*)audioPacket
{
    dispatch_sync(_lock, ^{
        BOOL hasValidInputSource = !(videoFrame->GetFlags() & bmdFrameHasNoInputSource);
        void *baseAddress = NULL;
        videoFrame->GetBytes(&baseAddress);
        
        if (_capturingEnabled && videoFrame && hasValidInputSource && baseAddress) {
            videoFrame->AddRef();
            CVPixelBufferRef pixelBuffer = NULL;
            CVReturn result = CVPixelBufferCreateWithBytes(NULL,
                                                           videoFrame->GetWidth(),
                                                           videoFrame->GetHeight(),
                                                           kCMPixelFormat_32BGRA,
                                                           baseAddress,
                                                           videoFrame->GetRowBytes(),
                                                           pixelBufferReleaseBytesCallback,
                                                           videoFrame,
                                                           NULL,
                                                           &pixelBuffer);
            if (pixelBuffer) {
                // Get timestamps
                int32_t timescale = 60000;    // good numerator 24, 29.97, 30 and 60 fps
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
                
                NSAssert(_sampleBufferDelegate && _callbackQueue, @"delegate and queue must be set before starting capture");
                dispatch_async(_callbackQueue, ^{
                    [_sampleBufferDelegate captureDevice:self didOutputSampleBuffer:sampleBuffer];
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

