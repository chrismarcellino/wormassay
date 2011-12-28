//
//  WormAssayAppDelegate.m
//  WormAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "WormAssayAppDelegate.h"
#import "VideoSourceDocument.h"
#import "DocumentController.h"
#import "VideoProcessorController.h"
#import "VideoProcessor.h"
#import <QTKit/QTKit.h>

static NSString *const IgnoreBuiltInCamerasUserDefaultsKey = @"IgnoreBuiltInCameras";
static NSString *const LoggingWindowAutosaveName = @"LoggingWindow";

@interface WormAssayAppDelegate ()

- (void)loadCaptureDevices;
- (void)captureDevicesChanged;

@end

@implementation WormAssayAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Register default user defaults
    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], IgnoreBuiltInCamerasUserDefaultsKey, nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    [defaults release];
    
    // Create our NSDocumentController subclass first
    [[[DocumentController alloc] init] autorelease];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Register for camera notifications and create windows for each camera
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasConnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasDisconnectedNotification object:nil];
    
    // Register for defaults changes
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self
                                                              forKeyPath:[@"values." stringByAppendingString:IgnoreBuiltInCamerasUserDefaultsKey]
                                                                 options:0
                                                                 context:NULL];
    
    // Create the logging window and associate it with the VideoProcessorController
    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    NSRect rect = screenFrame;
    rect.size.width = MIN(1000, rect.size.width);
    rect.size.height = MIN(200, rect.size.height);
    NSUInteger styleMask = NSTitledWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask | NSUtilityWindowMask;
    _loggingPanel = [[NSPanel alloc] initWithContentRect:rect styleMask:styleMask backing:NSBackingStoreBuffered defer:YES];
    [_loggingPanel setHidesOnDeactivate:NO];
    [_loggingPanel setTitle:@"Run Log"];
    [_loggingPanel setFrameUsingName:LoggingWindowAutosaveName];
    [_loggingPanel setFrameAutosaveName:LoggingWindowAutosaveName];
    
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    [_loggingPanel setContentView:textView];
    [textView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [textView release];
    [_loggingPanel orderBack:self];
    
    [[VideoProcessorController sharedInstance] setRunLogTextStorage:[textView textStorage]];
    
    [self loadCaptureDevices];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    [self loadCaptureDevices];
}

- (void)loadCaptureDevices
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    NSMutableSet *presentUniqueIds = [[NSMutableSet alloc] init];
    
    BOOL ignoreBuiltInCameras = [[NSUserDefaults standardUserDefaults] boolForKey:IgnoreBuiltInCamerasUserDefaultsKey];
    
    // Iterate through current capture devices, creating new documents for new ones
    for (QTCaptureDevice *device in [QTCaptureDevice inputDevices]) {
        NSString *modelUniqueID = [device modelUniqueID];
        NSString *uniqueID = [device uniqueID];
        
        BOOL isBuiltInCamera = [modelUniqueID rangeOfString:@"VendorID_1452"].location != NSNotFound;  // Apple USB devices
        
        // Only consider devices capable of video output and that meet our built-in device criteria
        if (([device hasMediaType:QTMediaTypeVideo] || [device hasMediaType:QTMediaTypeMuxed]) && 
            (!isBuiltInCamera || !ignoreBuiltInCameras)) {
            [presentUniqueIds addObject:uniqueID];
            
            // Construct the URL for the capture device
            NSURL *url = URLForCaptureDeviceUniqueID(uniqueID);
            
            // If there is no open VideoSourceDocument document for this URL, create one
            if (![documentController documentForURL:url]) {                
                NSError *error = nil;
                [documentController openDocumentWithContentsOfURL:url display:YES error:&error];
                if (error) {
                    [[NSAlert alertWithError:error] runModal];
                }
            }
        }
    }
    
    // Iterate through current documents and remove ones that no longer correspond to current capture devices
    for (NSDocument *document in [documentController documents]) {
        NSURL *url = [document fileURL];        // not necessarily a file URL
        NSString *captureDeviceUniqueID = UniqueIDForCaptureDeviceURL(url);
        if (captureDeviceUniqueID) {
            if (![presentUniqueIds containsObject:captureDeviceUniqueID]) {
                [document close];
            }
        }
    }
    
    [presentUniqueIds release];
}

- (void)captureDevicesChanged
{
    [self performSelector:@selector(loadCaptureDevices) withObject:nil afterDelay:0.0];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    return NO;
}

@end
