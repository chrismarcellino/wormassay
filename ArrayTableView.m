//
//  ArrayTableView.m
//  WormAssay
//
//  Created by Chris Marcellino on 5/10/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "ArrayTableView.h"


@implementation ArrayTableView

@synthesize contents =_contents;

- (id)init
{
    if ((self = [super init])) {
        [self setDataSource:self];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder:aDecoder])) {
        [self setDataSource:self];
    }
    return self;
}

- (void)setContents:(NSArray *)contents
{
    NSAssert([self dataSource] == self, @"dataSource cannot be changed");
    
    if (_contents != contents) {
        [_contents release];
        _contents = [contents copy];
        [self reloadData];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_contents count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    id element = [_contents objectAtIndex:row];
    if ([element isKindOfClass:[NSMapTable class]]) {
        element = [element objectForKey:tableColumn];
    }
    return element;
}

@end
