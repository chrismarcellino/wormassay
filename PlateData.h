//
//  PlateData.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface PlateData : NSObject

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime;

@property(readonly) NSUInteger wellCount;
@property(readonly) NSTimeInterval startPresentationTime;
@property(readonly) NSTimeInterval lastPresentationTime;
@property(readonly) NSUInteger receivedFrameCount;
@property(readonly) NSUInteger frameDropCount;
@property(readonly) NSUInteger sampleCount;

- (void)addFrameOccupancyFractions:(double *)occupancyFraction
          movedFractions:(double *)movedFractions
                atPresentationTime:(NSTimeInterval)presentationTime;

- (void)addProcessingTime:(NSTimeInterval)processingTime;

- (void)incrementReceivedFrameCount;
- (void)incrementFrameDropCount;

- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;
- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds;
- (void)movedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;
- (void)movedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds;

- (void)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames;

@end
