//
//  Emailer.m
//  WormAssay
//
//  Created by Chris Marcellino on 5/5/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "Emailer.h"


@implementation Emailer

+ (void)sendMailMessageToRecipients:(NSString *)recipients subject:(NSString *)subject body:(NSString *)body attachmentPaths:(NSArray *)attachmentPaths
{
    NSAssert([NSThread isMainThread], @"must call on main thread");
    
    // Create the attachment commands
    NSMutableString *attachmentCommands = [NSMutableString string];
    for (NSString *path in attachmentPaths) {
        [attachmentCommands appendFormat:@"make new attachment with properties {file name:\"%@\"} at after the last paragraph \n", path];
    }
    
    NSString *source = [NSString stringWithFormat:@
                        // Get the current visibility of Mail
                        "tell application \"System Events\" \n"
                        "copy (name of processes) contains \"Mail\" and visible of process \"Mail\" to mailWasVisible \n"
                        "end tell \n"                        
                        // Draft the message and add the attachments
                        "tell application \"Mail\" \n"
                        "set newMessage to make new outgoing message with properties {subject:\"%@\", content:\"%@\"} \n"
                        "tell newMessage \n"
                        "make new to recipient at end of to recipients with properties {address:\"%@\"} \n"
                        "%@"
                        "set visible to true \n"
                        "end tell \n"
                        "send newMessage \n"
                        "end tell \n"
                        // Make mail hidden again if it already was hidden
                        "if not mailWasVisible then tell application \"System Events\" \n"
                        "set visible of process \"Mail\" to false \n"
                        "end tell \n",
                        subject, body, recipients, attachmentCommands];
    
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *errorDict = nil;
    [script executeAndReturnError:&errorDict];
    if (errorDict) {
        NSString *errorText = [errorDict objectForKey:NSAppleScriptErrorMessage];
        if (!errorText) {
            errorText = [errorDict description];
        }
        
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Unable to send email", nil)];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Error running AppleScript to send email: %@\n\nCheck the security settings in System Preferences > Security & Privacy > Privacy > Automation.", @"alert format string"),
                                   errorText]];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", nil)];
        [alert runModal];
    }
}

@end
