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
- (NSArray *)supportedCaptureModes;     // just the ones that can be currently enabled based on the attached camera
// in order of priority: 1) resolution, 2) field dominance, 3) frame duration
- (DeckLinkCaptureMode *)highestResolutionSupportedCaptureMode;

- (void)setSampleBufferDelegate:(id<DeckLinkCaptureDeviceSampleBufferDelegate>)sampleBufferDelegate
                          queue:(dispatch_queue_t)sampleBufferCallbackQueue;
- (BOOL)startCaptureWithCaptureMode:(DeckLinkCaptureMode *)captureMode error:(NSError **)outError;
- (void)stopCapture;

@end


@protocol DeckLinkCaptureDeviceSampleBufferDelegate <NSObject>

- (void)captureDevice:(DeckLinkCaptureDevice *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer;

@end


@interface DeckLinkCaptureMode : NSObject

@property(readonly) NSString *displayName;
@property(readonly) NSSize frameSize;
@property(readonly) NSTimeInterval frameDuration;   // in seconds
@property(readonly) DeckLinkFieldDominance fieldDominance;

@end
