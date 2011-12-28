//
//  PlateData.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    ReportingStyleNone = 0,
    ReportingStyleRaw,
    ReportingStyleMean,
    ReportingStyleMeanAndStdDev
} ReportingStyle;

// Thread-safe
@interface PlateData : NSObject

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime;

@property(readonly) NSUInteger wellCount;
@property(readonly) NSTimeInterval startPresentationTime;
@property(readonly) NSTimeInterval lastPresentationTime;

// MovementUnits are implemented dependent arbitrary units. This is the only required data.
- (void)appendMovementUnit:(double)movementUnit atPresentationTime:(NSTimeInterval)presentationTime forWell:(int)well;

// Adds results to a specific column, creating the column if necessary.
- (void)setReportingStyle:(ReportingStyle)style forDataColumnID:(const char *)columnID;
- (void)appendResult:(double)result toDataColumn:(const char *)columnID forWell:(int)well;

// Allows reporting of non-formatted results text to be provided with the results and in the log files. Most MotionAnalyzers are
// not expected to provide this.
- (void)appendToAdditionalResultsText:(NSString *)text;

- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well;
- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well inLastSeconds:(NSTimeInterval)seconds;

// Frame rate statistics are automatically set by the VideoProcessors. MotionAnalyzers should not manipulate these.
@property(readonly) NSUInteger receivedFrameCount;
@property(readonly) NSUInteger frameDropCount;
- (void)incrementReceivedFrameCount;
- (void)incrementFrameDropCount;

- (void)addProcessingTime:(NSTimeInterval)processingTime;
- (void)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames;

// Results Output

@end
