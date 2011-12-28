//
//  DocumentController.m
//  WormAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "DocumentController.h"
#import "VideoSourceDocument.h"


@implementation DocumentController

- (NSString *)typeForContentsOfURL:(NSURL *)inAbsoluteURL error:(NSError **)outError
{
    if ([[inAbsoluteURL scheme] caseInsensitiveCompare:CaptureDeviceScheme] == NSOrderedSame) {
        return CaptureDeviceFileType;
    }
    return [super typeForContentsOfURL:inAbsoluteURL error:outError];
}

- (NSArray *)documentClassNames
{
    return [NSArray arrayWithObject:NSStringFromClass([VideoSourceDocument class])];
}

@end
