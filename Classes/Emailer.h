//
//  Emailer.h
//  WormAssay
//
//  Created by Chris Marcellino on 5/5/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface Emailer : NSObject

// must call on main thread
+ (void)sendMailMessageToRecipients:(NSString *)recipientsString
                            subject:(NSString *)subject
                               body:(NSString *)body
                    attachmentPaths:(NSArray *)attachmentPaths;

@end
