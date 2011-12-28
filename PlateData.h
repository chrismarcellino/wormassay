//
//  PlateData.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import <Foundation/Foundation.h>

// Thread-safe
@interface PlateData : NSObject

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime;

@property(readonly) NSUInteger wellCount;
@property(readonly) NSTimeInterval startPresentationTime;
@property(readonly) NSTimeInterval lastPresentationTime;
@property(readonly) NSUInteger receivedFrameCount;
@property(readonly) NSUInteger frameDropCount;
@property(readonly) NSUInteger sampleCount;

// MovementUnits are implemented dependent arbitrary units. Occupancy fractions are unitless values describing the proportion of the
// worm occupied by the well. OccupancyFractions are optional.
- (void)addMovementUnits:(double *)movementUnits
 frameOccupancyFractions:(double *)occupancyFraction        // may be NULL if not supported by a MotionAnalyzer
      atPresentationTime:(NSTimeInterval)presentationTime;

// Allows reporting of non-formatted results text to be provided with the results and in the log files. Most MotionAnalyzers are
// not expected to provide this.
- (void)appendToAdditionalResultsText:(NSString *)additionalResultsText;

- (void)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;
- (void)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds;
- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;

- (void)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames;

@end


// Frame rate statistics are automatically set by the VideoProcessors. MotionAnalyzers should not manipulate these.
@interface PlateData (FrameRateStatistics)

- (void)incrementReceivedFrameCount;
- (void)incrementFrameDropCount;
- (void)addProcessingTime:(NSTimeInterval)processingTime;

@end