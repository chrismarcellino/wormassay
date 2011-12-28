//
//  NematodeAssayAppDelegate.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "NematodeAssayAppDelegate.h"
#import <QTKit/QTKit.h>

@interface NematodeAssayAppDelegate ()

- (void)captureDevicesChanged;

@end

@implementation NematodeAssayAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    registeredDevices = [[NSMutableArray alloc] init];
    
    // Register for camera notifications and create windows for each camera
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasConnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceWasDisconnectedNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceFormatDescriptionsDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(captureDevicesChanged) name:QTCaptureDeviceAttributeDidChangeNotification object:nil];
    
    [self captureDevicesChanged];
    // TILE WINDOWS
}

- (void)captureDevicesChanged
{
    
    
    for (QTCaptureDevice *device in [QTCaptureDevice inputDevices]) {
        if ([device hasMediaType:QTMediaTypeVideo] || [device hasMediaType:QTMediaTypeMuxed]) {
            
        }
    }
}

@end
