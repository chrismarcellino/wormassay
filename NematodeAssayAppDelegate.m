//
//  NematodeAssayAppDelegate.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "NematodeAssayAppDelegate.h"
#import "VideoSource.h"
#import "DocumentController.h"
#import <QTKit/QTKit.h>

@interface NematodeAssayAppDelegate ()

- (void)loadCaptureDevices;
- (void)captureDevicesChanged;

@end

@implementation NematodeAssayAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    registeredDevices = [[NSMutableArray alloc] init];
    
    // Create our NSDocumentController subclass first
    [[[DocumentController alloc] init] autorelease];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{    
    // Register for camera notifications and create windows for each camera
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasConnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasDisconnectedNotification object:nil];
    
    [self loadCaptureDevices];
    
    // XX TILE WINDOWS
}

- (void)loadCaptureDevices
{
    NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
    NSMutableSet *presentUniqueIds = [[NSMutableSet alloc] init];
    
    // Iterate through current capture devices, creating new documents for new ones
    for (QTCaptureDevice *device in [QTCaptureDevice inputDevices]) {
        NSString *modelUniqueID = [device modelUniqueID];
        NSString *uniqueID = [device uniqueID];
        BOOL isBuiltInDevice = [modelUniqueID rangeOfString:@"VendorID_1452"].location != NSNotFound;  // Apple USB devices
        
        // Only consider devices capable of video output and that meet our built-in device criteria
        if (([device hasMediaType:QTMediaTypeVideo] || [device hasMediaType:QTMediaTypeMuxed]) && 
            (!isBuiltInDevice || !ignoreBuiltInDevices)) {
            [presentUniqueIds addObject:uniqueID];
            
            // Construct the URL for the capture device
            NSURL *url = [[NSURL alloc] initWithScheme:CaptureDeviceScheme host:@"" path:[@"/" stringByAppendingString:uniqueID]];
            
            // If there is no open VideoSource document for this URL, create one
            if (![documentController documentForURL:url]) {
                // Log enumerated devices
                NSLog(@"Enumerated device \"%@\" with model ID \"%@\", unique ID %@, format descriptions: %@",
                      [device localizedDisplayName],
                      modelUniqueID,
                      uniqueID,
                      [[device formatDescriptions] valueForKey:@"formatDescriptionAttributes"]);
                
                NSError *error = nil;
                [documentController openDocumentWithContentsOfURL:url display:YES error:&error];
                if (error) {
                    [[NSAlert alertWithError:error] runModal];
                }
            }
                
            [url release];
        }
    }
    
    // Iterate through current documents and remove ones that no longer correspond to current capture devices
    for (NSDocument *document in [documentController documents]) {
        NSURL *url = [document fileURL];
        NSLog(@"url: %@", url);
        
        //XXX
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
