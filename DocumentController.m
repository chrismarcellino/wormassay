//
//  DocumentController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "DocumentController.h"
#import "VideoSourceController.h"


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
    return [NSArray arrayWithObject:NSStringFromClass([VideoSourceController class])];
}

@end
