//
//  VideoSource.m
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "VideoSource.h"

NSString *const CaptureDeviceScheme = @"capturedevice";


@implementation VideoSource

- (id)init
{
    if ((self = [super init])) {
        [self setHasUndoManager:NO];
    }
    
    return self;
}

- (id)initWithType:(NSString *)typeName error:(NSError **)outError
{
    // Movies cannot be created anew
    [self autorelease];
    return nil;
}

- (id)initWithContentsOfURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    if ([[absoluteURL scheme] caseInsensitiveCompare:CaptureDeviceScheme] == NSOrderedSame) {
        NSCharacterSet *slashSet = [NSCharacterSet characterSetWithCharactersInString:@"/"];
        NSString *uniqueId = [[absoluteURL path] stringByTrimmingCharactersInSet:slashSet];
        if (uniqueId) {
            captureDevice = [[QTCaptureDevice deviceWithUniqueID:uniqueId] retain];
        } else {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"Unknown capture device ID" forKey:NSLocalizedDescriptionKey];
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
        }
    } else if ([absoluteURL isFileURL]) {
        movie = [[QTMovie alloc] initWithURL:absoluteURL error:outError];
    }
    
    if (captureDevice || movie) {
        return [super initWithContentsOfURL:absoluteURL ofType:typeName error:outError];
    } else {
        [self autorelease];
        return nil;
    }
}

- (id)initForURL:(NSURL *)absoluteDocumentURL withContentsOfURL:(NSURL *)absoluteDocumentContentsURL ofType:(NSString *)typeName error:(NSError **)outError
{
    // Movies are not writeable
    [self autorelease];
    return nil;
}

- (void)dealloc
{
    [captureDevice release];
    [movie release];
    [super dealloc];
}

- (void)makeWindowControllers
{
    NSRect rect = NSZeroRect;
    rect.size = [self maximumNativeResolution];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                   styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES];
    NSWindowController *windowController = [[NSWindowController alloc] initWithWindow:window];
    [self addWindowController:windowController];
    [window release];
    [windowController release];
}

- (NSSize)maximumNativeResolution
{
    // XXX CONSIDER LIMITING RESOLUTION FOR PERFORMANCE
    NSSize size;
    
    if (captureDevice) {
        size = NSZeroSize;
        for (QTFormatDescription *formatDescription in [captureDevice formatDescriptions]) {
            NSSize formatSize = [[formatDescription attributeForKey:QTFormatDescriptionVideoEncodedPixelsSizeAttribute] sizeValue];
            if (formatSize.width > size.width && formatSize.height > size.height) {
                size = formatSize;
            }
        }
    } else {
        size = [[movie attributeForKey:QTMovieNaturalSizeAttribute] sizeValue];
    }
    
    return size;
}

- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
    if (captureDevice) {
        
    } else {
        
    }
}

@end
