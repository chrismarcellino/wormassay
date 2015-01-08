//
//  LoggingAndNotificationsSettingsWindowController.h
//  WormAssay
//
//  Created by Chris Marcellino on 5/11/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface LoggingAndNotificationsSettingsWindowController : NSWindowController <NSWindowDelegate>

- (IBAction)browseForRunOutputFolderPath:(id)sender;
- (IBAction)openMail:(id)sender;
- (IBAction)testEmailNotifications:(id)sender;

@end
