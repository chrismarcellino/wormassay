//
//  ArrayTableViewDataSource.h
//  WormAssay
//
//  Created by Chris Marcellino on 5/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <AppKit/AppKit.h>

@interface ArrayTableViewDataSource : NSObject <NSTableViewDataSource> {
    NSArray *_array;
}

- (id)initByCopyingArray:(NSArray *)array;

@end
