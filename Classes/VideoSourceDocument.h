//
//  VideoSourceDocument.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/1/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "VideoProcessor.h"
#import "DeckLinkCaptureDevice.h"

@class VideoProcessor;
@class BitmapOpenGLView;

extern NSString *const CaptureDeviceWasConnectedOrDisconnectedNotification;

extern NSString *const AVFCaptureDeviceScheme;
extern NSString *const AVFCaptureDeviceFileType;

extern NSString *const BlackmagicDeckLinkCaptureDeviceScheme;
extern NSString *const BlackmagicDeckLinkCaptureDeviceFileType;


// A VideoSourceDocument corresponds to each document window and hence camera input
@interface VideoSourceDocument : NSDocument <AVCaptureVideoDataOutputSampleBufferDelegate, DeckLinkCaptureDeviceSampleBufferDelegate, VideoProcessorRecordingDelegate> {
    dispatch_queue_t _frameArrivalQueue;
    
    VideoProcessor *_processor;
    BitmapOpenGLView *_bitmapOpenGLView;
    
    BOOL _closeCalled;
    NSSize _frameSize;
    
    // Shared video encoders
    AVAssetWriter *_assetWriter;
    AVAssetWriterInput *_assetWriterInput;
    BOOL _currentlyProcessingFrame;
    BOOL _sendFramesToAssetWriter;
    BOOL _firstFrameToAssetWriter;
    NSUInteger _recordingFrameDropCount;
                                                    
    // A document will have only one of the following sets of variables set depending on the input:
    
    // AVFoundation (QuickTime X) capture devices
    AVCaptureDevice *_avCaptureDevice;
    AVCaptureSession *_captureSession;
    AVCaptureDeviceInput *_captureDeviceInput;
    AVCaptureVideoDataOutput *_captureVideoDataOutput;
    
    // AVFoundation movie file input
    AVAsset *_urlAsset;
    AVAssetReader *_assetReader;
    AVAssetReaderTrackOutput *_assetReaderOutput;
    
    // Blackmagic DeckLink capture device
    DeckLinkCaptureDevice *_deckLinkCaptureDevice;
    DeckLinkCaptureMode *_lastMode;
}

// unique urls for each camera device (only meaningful to this class)
+ (NSArray *)cameraDeviceURLsIgnoringBuiltInCamera:(BOOL)ignoreBuiltInCameras useBlackmagicDeckLinkDriver:(BOOL)useDeckLink;

- (NSString *)sourceIdentifier;      // unique and suitable for logging

@end
