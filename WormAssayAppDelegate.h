//
//  WormAssayAppDelegate.h
//  WormAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class VideoProcessor;
@class ArrayTableView;

@interface WormAssayAppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate> {
    NSWindowController *_loggingAndNotificationsWindowController;
    NSArray *_loggingPanelTopLevelObjects;
}

@property(nonatomic, retain) IBOutlet NSMenu *assayAnalyzerMenu;
@property(nonatomic, retain) IBOutlet NSMenu *plateOrientationMenu;
@property(nonatomic, retain) IBOutlet NSTextView *runLogTextView;
@property(nonatomic, retain) IBOutlet NSScrollView *runLogScrollView;

- (IBAction)openRunOutputFolder:(id)sender;
- (IBAction)showLoggingAndNotificationSettings:(id)sender;
- (IBAction)plateOrientationWasSelected:(id)sender;
- (IBAction)manuallyReportResultsAndResetProcessor:(id)sender;

@end

NSString *formattedDataSize(unsigned long long bytes);
