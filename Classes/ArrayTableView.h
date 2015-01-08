//
//  ArrayTableView.h
//  WormAssay
//
//  Created by Chris Marcellino on 5/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <AppKit/AppKit.h>

@interface ArrayTableView : NSTableView <NSTableViewDataSource>

// Contents is an array of object values for a one column table, or alternatively, an array of NSMapTables
// mapping NSTableColumns to object values.
@property(copy, nonatomic) NSArray *contents;

@end
