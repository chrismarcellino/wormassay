//
//  VideoSourceController.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>
#import <QuartzCore/QuartzCore.h>

@class BitmapOpenGLView;

extern NSString *const CaptureDeviceScheme;
extern NSString *const CaptureDeviceFileType;

extern NSURL *URLForCaptureDeviceUniqueID(NSString *uniqueID);
extern NSString *UniqueIDForCaptureDeviceURL(NSURL *url);


@interface VideoSourceController : NSDocument {
    // A document will strictly have one of captureDevice or movie and their associated objects
    QTCaptureDevice *_captureDevice;
    QTCaptureSession *_captureSession;
    QTCaptureDeviceInput *_captureDeviceInput;
    QTCaptureDecompressedVideoOutput *_captureDecompressedVideoOutput;
    
    QTMovie *_movie;
    dispatch_queue_t _movieFrameExtractQueue;
    dispatch_source_t _movieFrameExtractTimer;
    QTTime _nextExtractTime;
    
    BitmapOpenGLView *_bitmapOpenGLView;
    NSUInteger frameDropCount;
}

- (NSSize)lastKnownResolution;

@end
