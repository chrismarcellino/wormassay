//
//  NematodeAssayAppDelegate.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "NematodeAssayAppDelegate.h"
#import "VideoSourceController.h"
#import "DocumentController.h"
#import <QTKit/QTKit.h>

static NSString *const IgnoreBuiltInCamerasUserDefaultsKey = @"IgnoreBuiltInCameras";

@interface NematodeAssayAppDelegate ()

- (void)loadCaptureDevices;
- (void)captureDevicesChanged;

@end

@implementation NematodeAssayAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    _registeredDevices = [[NSMutableArray alloc] init];

    // Register default user defaults
    NSDictionary *defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
                              [NSNumber numberWithBool:YES], IgnoreBuiltInCamerasUserDefaultsKey, nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
    [defaults release];
    
    // Create our NSDocumentController subclass first
    [[[DocumentController alloc] init] autorelease];
    
    // Get the capture system started as early as possible so we can try to avoid resolution changes
    [QTCaptureDevice inputDevices];
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
    
    [self loadCaptureDevices];
    
    // XX TILE WINDOWS
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
            
            // If there is no open VideoSourceController document for this URL, create one
            if (![documentController documentForURL:url]) {
                // Log enumerated devices
                NSLog(@"Enumerated device \"%@\" with model ID \"%@\", unique ID %@",
                      [device localizedDisplayName],
                      modelUniqueID,
                      uniqueID);
                
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
                NSLog(@"Closing removed device with unique ID %@", captureDeviceUniqueID);
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
