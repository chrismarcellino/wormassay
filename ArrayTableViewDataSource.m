//
//  ArrayTableViewDataSource.m
//  WormAssay
//
//  Created by Chris Marcellino on 5/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "ArrayTableViewDataSource.h"


@implementation ArrayTableViewDataSource

- (id)initByCopyingArray:(NSArray *)array
{
    if ((self = [super init])) {
        _array = [array copy];
    }
    
    return self;
}

- (void)dealloc
{
    [_array release];
    [super dealloc];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_array count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return [_array objectAtIndex:row];
}

@end
