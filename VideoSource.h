//
//  VideoSource.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>

extern NSString *const CaptureDeviceScheme;


@interface VideoSource : NSDocument {
    // A document will strictly have one of captureDevice or movie
    QTCaptureDevice *captureDevice;
    QTMovie *movie;
}

- (NSSize)maximumNativeResolution;

@end
