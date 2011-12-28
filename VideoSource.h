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

extern NSURL *URLForCaptureDeviceUniqueID(NSString *uniqueID);
extern NSString *UniqueIDForCaptureDeviceURL(NSURL *url);


@interface VideoSource : NSDocument {
    // A document will strictly have one of captureDevice or movie and their associated objects
    QTCaptureDevice *captureDevice;
    QTCaptureSession *captureSession;
    QTCaptureDeviceInput *captureDeviceInput;
    QTCaptureDecompressedVideoOutput *captureDecompressedVideoOutput;
    
    QTMovie *movie;
    dispatch_queue_t movieFrameExtractQueue;
    dispatch_source_t movieFrameExtractTimer;
    QTTime nextExtractTime;
}

- (NSSize)maximumNativeResolution;

@end
