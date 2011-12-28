//
//  DocumentController.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "DocumentController.h"
#import "VideoSource.h"


@implementation DocumentController

- (NSString *)typeForContentsOfURL:(NSURL *)inAbsoluteURL error:(NSError **)outError
{
    if ([[inAbsoluteURL scheme] caseInsensitiveCompare:CaptureDeviceScheme] == NSOrderedSame) {
        return @"video";
    }
    return [super typeForContentsOfURL:inAbsoluteURL error:outError];
}

@end
