//
//  WormAssayAppDelegate.h
//  WormAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class VideoProcessor;

@interface WormAssayAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    NSPanel *_loggingPanel;
    NSWindowController *_loggingAndNotificationWindowController;
}

@property(nonatomic, retain) IBOutlet NSMenu *assayAnalyzerMenu;

- (IBAction)openRunOutputFolder:(id)sender;
- (IBAction)showLoggingAndNotificationSettings:(id)sender;

@end

NSString *formattedDataSize(unsigned long long bytes);
