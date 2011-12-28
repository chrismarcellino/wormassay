//
//  NematodeAssayAppDelegate.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class VideoProcessor;

@interface NematodeAssayAppDelegate : NSObject <NSApplicationDelegate> {
    NSMutableSet *_registeredDevices;
}

@end
