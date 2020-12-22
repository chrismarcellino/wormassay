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
    if ([[inAbsoluteURL scheme] caseInsensitiveCompare:AVFCaptureDeviceScheme] == NSOrderedSame) {
        return AVFCaptureDeviceFileType;
    }
    if ([[inAbsoluteURL scheme] caseInsensitiveCompare:BlackmagicDeckLinkCaptureDeviceScheme] == NSOrderedSame) {
        return BlackmagicDeckLinkCaptureDeviceFileType;
    }
    
    return [super typeForContentsOfURL:inAbsoluteURL error:outError];
}

- (NSArray *)documentClassNames
{
    return @[ NSStringFromClass([VideoSourceDocument class])];
}

@end
