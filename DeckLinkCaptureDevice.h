//
//  DeckLinkCaptureDevice.h
//  WormAssay
//
//  Created by Chris Marcellino on 10/16/13.
//  Copyright (c) 2013 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

// BlackMagic DeckLink access
@interface DeckLinkCaptureDevice : NSObject

+ (BOOL)isDriverInstalled;
+ (NSString *)deckLinkSystemVersion;        // for display only

- (NSString *)uniqueID;

@end
