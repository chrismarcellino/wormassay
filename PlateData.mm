//
//  PlateData.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
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
    std::vector<std::vector<double> > _movementUnitsByWell;
    std::vector<std::vector<double> > _occupancyFractionsByWell;
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
        _movementUnitsByWell.resize(wellCount);
        _presentationTimes.reserve(InitialVectorSize);
        _processingTimes.reserve(InitialVectorSize);
        for (size_t i = 0; i < wellCount; i++) {
            _occupancyFractionsByWell[i].reserve(InitialVectorSize);
            _movementUnitsByWell[i].reserve(InitialVectorSize);
        }
    }
    return self;
}

- (NSTimeInterval)lastPresentationTime
{
    @synchronized(self) {
        return _presentationTimes.size() > 0 ? _presentationTimes.back() : _startPresentationTime;
    }
}

- (void)addFrameOccupancyFractions:(double *)occupancyFraction
                     movementUnits:(double *)movementUnits
                atPresentationTime:(NSTimeInterval)presentationTime
{
    @synchronized(self) {
        NSAssert(presentationTime >= [self lastPresentationTime], @"out of order presentation times");
        
        _presentationTimes.push_back(presentationTime);
        for (NSUInteger well = 0; well < _wellCount; well++) {
            _occupancyFractionsByWell[well].push_back(occupancyFraction[well]);
            _movementUnitsByWell[well].push_back(movementUnits[well]);
        }
    }
}

- (void)addProcessingTime:(NSTimeInterval)processingTime
{
    @synchronized(self) {
        _processingTimes.push_back(processingTime);
    }
}

- (NSUInteger)sampleCount
{
    @synchronized(self) {
        return _presentationTimes.size();
    }
}

- (void)incrementReceivedFrameCount
{
    @synchronized(self) {
        _receivedFrameCount++;
    }
}

- (void)incrementFrameDropCount
{
    @synchronized(self) {
        _frameDropCount++;
    }
}

// Must call @synchronized
- (size_t)sampleIndexStartingAtSecondsFromEnd:(NSTimeInterval)seconds
{
    NSTimeInterval time = [self lastPresentationTime] - seconds;
    return std::lower_bound(_presentationTimes.begin(), _presentationTimes.end(), time) - _presentationTimes.begin();
}

- (void)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well
{
    @synchronized(self) {
        meanAndStdDev(_movementUnitsByWell[well], *mean, *stddev);
    }
}

- (void)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well inLastSeconds:(NSTimeInterval)seconds
{
    @synchronized(self) {
        meanAndStdDev(_movementUnitsByWell[well], *mean, *stddev, [self sampleIndexStartingAtSecondsFromEnd:seconds]);
    }
}

- (void)occupancyFractionMean:(double *)mean stdDev:(double *)stddev forWell:(NSUInteger)well
{
    @synchronized(self) {
        meanAndStdDev(_occupancyFractionsByWell[well], *mean, *stddev);
    }
}

- (void)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames
{
    @synchronized(self) {
        NSUInteger firstIndex = 0;
        if (_processingTimes.size() > lastFrames) {
            firstIndex = _processingTimes.size() - lastFrames;
        }
        meanAndStdDev(_processingTimes, *mean, *stddev, firstIndex);
    }
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
