//
//  WormAssayAppDelegate.h
//  WormAssay
//
//  Created by Chris Marcellino on 3/31/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class VideoProcessor;

@interface WormAssayAppDelegate : NSObject <NSApplicationDelegate> {
    NSPanel *_loggingPanel;
}

@property(nonatomic, retain) IBOutlet NSMenu *assayAnalyzerMenu;

@end

NSString *formattedDataSize(unsigned long long bytes);
