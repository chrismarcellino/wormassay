//
//  PlateData.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "PlateData.h"

static const size_t InitialVectorSize = 1024;

static void meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, size_t firstIndex = 0);

@interface PlateData () {
    NSUInteger _wellCount;
    NSTimeInterval _startPresentationTime;
    NSUInteger _totalFrameCount;
    NSUInteger _frameDropCount;
    std::vector<double> _presentationTimes;
    std::vector<std::vector<double> > _occupancyFractionsByWell;
    std::vector<std::vector<double> > _normalizedMovedFractionsByWell;
}

@end


@implementation PlateData

@synthesize wellCount = _wellCount;
@synthesize startPresentationTime = _startPresentationTime;
@synthesize totalFrameCount = _totalFrameCount;
@synthesize frameDropCount = _frameDropCount;

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime
{
    if ((self = [super init])) {
        _wellCount = wellCount;
        _startPresentationTime = presentationTime;
        
        _occupancyFractionsByWell.resize(wellCount);
        _normalizedMovedFractionsByWell.resize(wellCount);
        _presentationTimes.reserve(InitialVectorSize);
        for (size_t i = 0; i < wellCount; i++) {
            _occupancyFractionsByWell[i].reserve(InitialVectorSize);
            _normalizedMovedFractionsByWell[i].reserve(InitialVectorSize);
        }
    }
    return self;
}

- (NSTimeInterval)lastPresentationTime
{
    return _presentationTimes.size() > 0 ? _presentationTimes.back() : _startPresentationTime;
}

- (void)addFrameOccupancyFractions:(double *)occupancyFraction
          normalizedMovedFractions:(double *)normalizedMovedFractions
                atPresentationTime:(NSTimeInterval)presentationTime
{
    NSAssert(presentationTime >= [self lastPresentationTime], @"out of order presentation times");
    
    _presentationTimes.push_back(presentationTime);
    for (NSUInteger well = 0; well < _wellCount; well++) {
        _occupancyFractionsByWell[well].push_back(occupancyFraction[well]);
        _normalizedMovedFractionsByWell[well].push_back(normalizedMovedFractions[well]);
    }
}

- (NSUInteger)sampleCount
{
    return _presentationTimes.size();
}

- (void)incrementTotalFrameCount
{
    _totalFrameCount++;
}

- (void)incrementFrameDropCount
{
    _frameDropCount++;
}

- (size_t)sampleIndexStartingAtSecondsFromEnd:(NSTimeInterval)seconds
{
    NSTimeInterval time = [self lastPresentationTime] - seconds;
    return std::lower_bound(_presentationTimes.begin(), _presentationTimes.end(), time) - _presentationTimes.begin();
}

- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well
{
    meanAndStdDev(_occupancyFractionsByWell[well], *mean, *stddev);
}

- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds
{
    meanAndStdDev(_occupancyFractionsByWell[well], *mean, *stddev, [self sampleIndexStartingAtSecondsFromEnd:seconds]);
}

- (void)normalizedMovedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well
{
    meanAndStdDev(_normalizedMovedFractionsByWell[well], *mean, *stddev);
}

- (void)normalizedMovedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds
{
    meanAndStdDev(_normalizedMovedFractionsByWell[well], *mean, *stddev, [self sampleIndexStartingAtSecondsFromEnd:seconds]);
}

static void meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, NSUInteger firstIndex)
{
    double sum = 0.0;
    for (size_t i = firstIndex; i < vec.size(); i++) {
        sum += vec[i];
    }
    mean = sum / (vec.size() - firstIndex);
    
    double variance = 0.0;
    for (size_t i = firstIndex; i < vec.size(); i++) {
        double difference = vec[i] - mean;
        variance += difference * difference;
    }
    variance /= (vec.size() - firstIndex);
    stddev = sqrt(variance);
}


@end
