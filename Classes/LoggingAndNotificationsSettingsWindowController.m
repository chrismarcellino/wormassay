//
//  LoggingAndNotificationsSettingsWindowController.m
//  WormAssay
//
//  Created by Chris Marcellino on 5/11/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "LoggingAndNotificationsSettingsWindowController.h"
#import "VideoProcessorController.h"
#import "Emailer.h"

@implementation LoggingAndNotificationsSettingsWindowController

- (id)init
{
    return [super initWithWindowNibName:@"LoggingAndNotificationsSettings"];
}

- (IBAction)browseForRunOutputFolderPath:(id)sender
{
    VideoProcessorController *videoProcessorController = [VideoProcessorController sharedInstance];
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setCanCreateDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setResolvesAliases:YES];
    
    NSString *path = [videoProcessorController runOutputFolderPath];
    [panel setDirectoryURL:path ? [NSURL fileURLWithPath:path] : nil];
    
    [panel setPrompt:NSLocalizedString(@"Choose", nil)];
    [panel setTitle:NSLocalizedString(@"Output Folder", nil)];
    
    if ([panel runModal] == NSModalResponseOK) {
        [videoProcessorController setRunOutputFolderPath:[[panel URL] path]];
    }
}

- (IBAction)openMail:(id)sender
{
    NSURL *url = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.mail"];
    if (url) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (IBAction)testEmailNotifications:(id)sender
{
    NSString *recipients = [[VideoProcessorController sharedInstance] notificationEmailRecipients];
    NSString *body = [NSString stringWithFormat:NSLocalizedString(@"This is a test email message sent by %@.", nil),
                      [[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleNameKey]];
    [Emailer sendMailMessageToRecipients:recipients subject:@"Test message" body:body attachmentPaths:nil];
}

- (id)videoProcessorController      // for binding to by the nib's controls
{
    return [VideoProcessorController sharedInstance];
}

@end
