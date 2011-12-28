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
@property(readonly) NSUInteger totalFrameCount;
@property(readonly) NSUInteger frameDropCount;
@property(readonly) NSUInteger sampleCount;

- (void)addFrameOccupancyFractions:(double *)occupancyFraction
          normalizedMovedFractions:(double *)normalizedMovedFractions
                atPresentationTime:(NSTimeInterval)presentationTime;

- (void)incrementTotalFrameCount;
- (void)incrementFrameDropCount;

- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;
- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds;
- (void)normalizedMovedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well;
- (void)normalizedMovedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds;

@end
