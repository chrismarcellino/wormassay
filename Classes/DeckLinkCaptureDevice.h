//
//  DeckLinkCaptureDevice.h
//  WormAssay
//
//  Created by Chris Marcellino on 10/16/13.
//  Copyright (c) 2013 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

@protocol DeckLinkCaptureDeviceSampleBufferDelegate;
@class DeckLinkCaptureMode;

typedef enum {
    DeckLinkFieldDominanceUnknown = 0,
    DeckLinkFieldDominanceProgressive,
    DeckLinkFieldDominanceProgressiveSegmented,
    DeckLinkFieldDominanceInterlacedLowerFieldFirst,
    DeckLinkFieldDominanceInterlacedUpperFieldFirst
} DeckLinkFieldDominance;
#define DeckLinkFieldDominanceIsInterlaced(x) ((x) == DeckLinkFieldDominanceInterlacedLowerFieldFirst ||\
                                                (x) == DeckLinkFieldDominanceInterlacedUpperFieldFirst)

extern NSString *const DeckLinkCaptureDeviceWasConnectedOrDisconnectedNotification;


// Blackmagic DeckLink access
@interface DeckLinkCaptureDevice : NSObject

+ (BOOL)isDriverInstalled;
+ (NSString *)deckLinkSystemVersion;        // for display only
+ (NSArray *)captureDevices;

- (NSString *)uniqueID;
- (NSString *)localizedName;
- (NSString *)modelName;

- (NSArray *)allCaptureModes;
// After resolution, higher frame rates come first regardless of field dominance so that we always get all of the data
// when possible and don't misinterpret an interlaced field pair as a half speed progressive field.
- (NSArray *)allCaptureModesSortedByDescendingResolutionAndFrameRate;

- (void)setSampleBufferDelegate:(id<DeckLinkCaptureDeviceSampleBufferDelegate>)sampleBufferDelegate
                          queue:(dispatch_queue_t)sampleBufferCallbackQueue;

- (BOOL)startCaptureWithCaptureMode:(DeckLinkCaptureMode *)captureMode error:(NSError **)outError;
- (void)startCaptureWithSearchForModeWithModes:(NSArray *)captureModeSearchList;
- (void)stopCapture;

@end


@protocol DeckLinkCaptureDeviceSampleBufferDelegate <NSObject>

- (void)captureDevice:(DeckLinkCaptureDevice *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        inCaptureMode:(DeckLinkCaptureMode *)mode;

@end


@interface DeckLinkCaptureMode : NSObject

@property(readonly) NSString *displayName;
@property(readonly) NSSize frameSize;
@property(readonly) NSTimeInterval frameDuration;   // in seconds
@property(readonly) DeckLinkFieldDominance fieldDominance;

@end
