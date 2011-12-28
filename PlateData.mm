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
    NSUInteger _receivedFrameCount;
    NSUInteger _frameDropCount;
    std::vector<double> _presentationTimes;
    std::vector<std::vector<double> > _occupancyFractionsByWell;
    std::vector<std::vector<double> > _movedFractionsByWell;
    std::vector<double> _processingTimes;
}

@end


@implementation PlateData

@synthesize wellCount = _wellCount;
@synthesize startPresentationTime = _startPresentationTime;
@synthesize receivedFrameCount = _receivedFrameCount;
@synthesize frameDropCount = _frameDropCount;

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime
{
    if ((self = [super init])) {
        _wellCount = wellCount;
        _startPresentationTime = presentationTime;
        
        _occupancyFractionsByWell.resize(wellCount);
        _movedFractionsByWell.resize(wellCount);
        _presentationTimes.reserve(InitialVectorSize);
        _processingTimes.reserve(InitialVectorSize);
        for (size_t i = 0; i < wellCount; i++) {
            _occupancyFractionsByWell[i].reserve(InitialVectorSize);
            _movedFractionsByWell[i].reserve(InitialVectorSize);
        }
    }
    return self;
}

- (NSTimeInterval)lastPresentationTime
{
    return _presentationTimes.size() > 0 ? _presentationTimes.back() : _startPresentationTime;
}

- (void)addFrameOccupancyFractions:(double *)occupancyFraction
          movedFractions:(double *)movedFractions
                atPresentationTime:(NSTimeInterval)presentationTime
{
    NSAssert(presentationTime >= [self lastPresentationTime], @"out of order presentation times");
    
    _presentationTimes.push_back(presentationTime);
    for (NSUInteger well = 0; well < _wellCount; well++) {
        _occupancyFractionsByWell[well].push_back(occupancyFraction[well]);
        _movedFractionsByWell[well].push_back(movedFractions[well]);
    }
}

- (void)addProcessingTime:(NSTimeInterval)processingTime
{
    _processingTimes.push_back(processingTime);
}

- (NSUInteger)sampleCount
{
    return _presentationTimes.size();
}

- (void)incrementReceivedFrameCount
{
    _receivedFrameCount++;
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

- (void)movedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well
{
    meanAndStdDev(_movedFractionsByWell[well], *mean, *stddev);
}

- (void)movedFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds
{
    meanAndStdDev(_movedFractionsByWell[well], *mean, *stddev, [self sampleIndexStartingAtSecondsFromEnd:seconds]);
}

- (void)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames
{
    NSUInteger firstIndex = 0;
    if (_processingTimes.size() > lastFrames) {
        firstIndex = _processingTimes.size() - lastFrames;
    }
    meanAndStdDev(_processingTimes, *mean, *stddev, firstIndex);
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
