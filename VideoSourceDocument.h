//
//  VideoSourceDocument.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>
#import <QuartzCore/QuartzCore.h>

@class VideoProcessor;
@class BitmapOpenGLView;

extern NSString *const CaptureDeviceScheme;
extern NSString *const CaptureDeviceFileType;

extern NSURL *URLForCaptureDeviceUniqueID(NSString *uniqueID);
extern NSString *UniqueIDForCaptureDeviceURL(NSURL *url);

extern BOOL DeviceIsAppleUSBDevice(QTCaptureDevice *device);


@interface VideoSourceDocument : NSDocument {
    // A document will strictly have one of captureDevice or movie and their associated objects
    QTCaptureDevice *_captureDevice;
    QTCaptureSession *_captureSession;
    QTCaptureDeviceInput *_captureDeviceInput;
    QTCaptureDecompressedVideoOutput *_captureDecompressedVideoOutput;
    
    QTMovie *_movie;
    dispatch_queue_t _movieQueue;
    dispatch_source_t _movieFrameExtractTimer;
    
    VideoProcessor *_processor;
    BitmapOpenGLView *_bitmapOpenGLView;
    NSUInteger _frameDropCount;
    NSString *_sourceIdentifier;
    BOOL _closeCalled;
}

@property(nonatomic, readonly) QTCaptureDevice *captureDevice;
@property(nonatomic, readonly) QTMovie *movie;
@property(nonatomic, readonly) NSString *sourceIdentifier;      // unique and suitable for logging

- (NSSize)expectedFrameSize;
@property NSSize lastFrameSize;

@end
