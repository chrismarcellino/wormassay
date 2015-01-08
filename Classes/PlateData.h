//
//  PlateData.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

enum {
    ReportingStyleNone = 0,
    ReportingStyleMean = 1 << 1,
    ReportingStyleStdDev = 1 << 2,
    ReportingStyleRaw = 1 << 20,
    ReportingStylePercent = 1 << 21
};
typedef int ReportingStyle;

// Thread-safe
@interface PlateData : NSObject

// Set wellCount to 0 for a non-well plate
- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime;

@property(readonly) NSUInteger wellCount;
@property(readonly) NSTimeInterval startPresentationTime;
@property(readonly) NSTimeInterval lastPresentationTime;

// MovementUnits are analyzer dependent arbitrary units. This is the only required data.
- (void)appendMovementUnit:(double)movementUnit atPresentationTime:(NSTimeInterval)presentationTime forWell:(int)well;

// Adds results to a specific column, creating the column if necessary.
- (void)setReportingStyle:(ReportingStyle)style forDataColumnID:(const char *)columnID;
- (ReportingStyle)reportingStyleForDataColumnID:(const char *)columnID;
- (void)appendResult:(double)result toDataColumnID:(const char *)columnID forWell:(int)well;

// Allows reporting of non-formatted results text to be provided with the results and in the log files. Most MotionAnalyzers are
// not expected to provide this.
- (void)appendToAdditionalResultsText:(NSString *)text;

- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well;
- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well inLastSeconds:(NSTimeInterval)seconds;

// Frame rate statistics are automatically set by the VideoProcessors. MotionAnalyzers should not manipulate these.
@property(readonly) NSUInteger receivedFrameCount;
@property(readonly) NSUInteger frameDropCount;
@property(readonly) NSUInteger sampleCount;
- (void)incrementReceivedFrameCount;
- (void)incrementFrameDropCount;
- (double)averageFramesPerSecond;
- (double)droppedFrameProportion;

- (void)addProcessingTime:(NSTimeInterval)processingTime;
- (BOOL)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames;

// Results Output
- (NSArray *)sortedColumnIDsWithData;
- (NSString *)csvOutputForPlateID:(NSString *)plateID
                           scanID:(NSString *)scanID
      withAdditionalRawDataOutput:(NSMutableDictionary *)rawColumnIDsToCSVStrings
                     analyzerName:(NSString *)analyzerName
                 columnMajorOrder:(BOOL)columnMajorOrder;

@end
