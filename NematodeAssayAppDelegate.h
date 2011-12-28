//
//  NematodeAssayAppDelegate.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NematodeAssayAppDelegate : NSObject <NSApplicationDelegate> {
@private
    NSWindow *window;
}

@property (assign) IBOutlet NSWindow *window;

@end
