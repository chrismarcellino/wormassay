//
//  PlateData.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "PlateData.h"
#import "WellFinding.hpp"

// Required data column identifiers
static const char* MovementUnitID = "MovementUnits";
static const char* PresentationTimeID = "Timestamp";

static bool meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, size_t firstIndex = 0);
static inline void appendCSVElement(NSMutableString *output, NSString *element);

@interface PlateData () {
    NSUInteger _wellCount;
    NSTimeInterval _startPresentationTime;
    NSTimeInterval _lastPresentationTime;
    std::vector<std::map<std::string, std::vector<double> > > _valuesByWellAndDataColumn;
    std::map<std::string, ReportingStyle> _reportingStyleByDataColumn;
    NSUInteger _receivedFrameCount;
    NSUInteger _frameDropCount;
    std::vector<double> _processingTimes;
    NSMutableString *_additionalResultsText;
}

@end


@implementation PlateData

@synthesize wellCount = _wellCount;
@synthesize startPresentationTime = _startPresentationTime;
@synthesize lastPresentationTime = _lastPresentationTime;
@synthesize receivedFrameCount = _receivedFrameCount;
@synthesize frameDropCount = _frameDropCount;

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime
{
    if ((self = [super init])) {
        _wellCount = wellCount;
        _startPresentationTime = _lastPresentationTime = presentationTime;
        _valuesByWellAndDataColumn.resize(wellCount);
        
        [self setReportingStyle:(ReportingStyleMean | ReportingStyleStdDev | ReportingStyleRaw) forDataColumnID:MovementUnitID];
    }
    return self;
}

- (void)dealloc
{
    [_additionalResultsText release];
    [super dealloc];
}

- (void)appendMovementUnit:(double)movementUnit atPresentationTime:(NSTimeInterval)presentationTime forWell:(int)well
{
    @synchronized(self) {
        NSAssert(presentationTime >= _lastPresentationTime, @"out of order presentation times");
        _lastPresentationTime = presentationTime;
        [self appendResult:movementUnit toDataColumnID:MovementUnitID forWell:well];
        [self appendResult:presentationTime toDataColumnID:PresentationTimeID forWell:well];
    }
}

- (void)setReportingStyle:(ReportingStyle)style forDataColumnID:(const char *)columnID
{
    @synchronized(self) {
        _reportingStyleByDataColumn[std::string(columnID)] = style;
    }
}

- (ReportingStyle)reportingStyleForDataColumnID:(const char *)columnID
{
    @synchronized(self) {
        return _reportingStyleByDataColumn[std::string(columnID)];
    }
}

- (void)appendResult:(double)result toDataColumnID:(const char *)columnID forWell:(int)well
{
    @synchronized(self) {
        _valuesByWellAndDataColumn[well][std::string(columnID)].push_back(result);
    }
}

- (void)appendToAdditionalResultsText:(NSString *)text
{
    @synchronized(self) {
        if (!_additionalResultsText) {
            _additionalResultsText = [[NSMutableString alloc] init];
        }
        [_additionalResultsText appendString:text];
    }
}

- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well
{
    @synchronized(self) {
        return meanAndStdDev(_valuesByWellAndDataColumn[well][std::string(PresentationTimeID)], *mean, *stddev);
    }
}

- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well inLastSeconds:(NSTimeInterval)seconds
{
    @synchronized(self) {
        NSTimeInterval time = [self lastPresentationTime] - seconds;
        std::vector<double>* presentationTimes = &_valuesByWellAndDataColumn[well][std::string(PresentationTimeID)];
        size_t index = std::lower_bound(presentationTimes->begin(), presentationTimes->end(), time) - presentationTimes->begin();
        return meanAndStdDev(_valuesByWellAndDataColumn[well][std::string(MovementUnitID)], *mean, *stddev, index);
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

- (double)averageFramesPerSecond
{
    return (double)[self receivedFrameCount] / ([self lastPresentationTime] - [self startPresentationTime]);
}

- (double)droppedFrameProportion
{
    return (double)[self frameDropCount] / ([self receivedFrameCount] + [self frameDropCount]);
}

- (void)addProcessingTime:(NSTimeInterval)processingTime
{
    @synchronized(self) {
        _processingTimes.push_back(processingTime);
    }
}

- (BOOL)processingTimeMean:(double *)mean stdDev:(double *)stddev inLastFrames:(NSUInteger)lastFrames
{
    @synchronized(self) {
        NSUInteger firstIndex = 0;
        if (_processingTimes.size() > lastFrames) {
            firstIndex = _processingTimes.size() - lastFrames;
        }
        return meanAndStdDev(_processingTimes, *mean, *stddev, firstIndex);
    }
}

static bool meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, NSUInteger firstIndex)
{
    int numSamples = vec.size() - firstIndex;
    double sum = 0.0;
    for (size_t i = firstIndex; i < vec.size(); i++) {
        sum += vec[i];
    }
    mean = sum / numSamples;
    
    double variance = 0.0;
    for (size_t i = firstIndex; i < vec.size(); i++) {
        double difference = vec[i] - mean;
        variance += difference * difference;
    }
    variance /= numSamples;
    stddev = sqrt(variance);
    return numSamples > 0;
}

- (NSArray *)sortedColumnIDsWithData
{
    @synchronized(self) {
        NSMutableArray *columnIDs = [NSMutableArray arrayWithCapacity:_valuesByWellAndDataColumn.size()];
        for (map<std::string, std::vector<double> >::iterator it = _valuesByWellAndDataColumn[0].begin(); it != _valuesByWellAndDataColumn[0].end(); it++) {
            NSString *columnID = [[NSString alloc] initWithUTF8String:(it->first).c_str()];
            [columnIDs addObject:columnID];
            [columnID release];
        }
        [columnIDs sortUsingSelector:@selector(caseInsensitiveCompare:)];
        return columnIDs;
    }
}

- (NSString *)csvOutputForPlateID:(NSString *)plateID withAdditionalRawDataOutput:(NSMutableDictionary *)rawColumnIDsToCSVStrings
{
    @synchronized(self) {
        NSMutableString *output = [[NSMutableString alloc] init];
        
        // Write header row
        appendCSVElement(output, @"PlateAndWellID");
        
        NSArray *dataColumnIDs = [self sortedColumnIDsWithData];
        for (NSString *columnID in dataColumnIDs) {
            std::string columnIDStdStr = std::string([columnID UTF8String]);
            
            ReportingStyle style = _reportingStyleByDataColumn[columnIDStdStr];
            if (style & ReportingStyleMean) {
                appendCSVElement(output, [columnID stringByAppendingString:@"-Mean"]);
            }
            if (style & ReportingStyleStdDev) {
                appendCSVElement(output, [columnID stringByAppendingString:@"-StdDev"]);
            }
        }
        
        [output appendString:@"\n"];
        
        // Write stats for each well
        for (size_t well = 0; well < _valuesByWellAndDataColumn.size(); well++) {
            // Output the plate-well ID
            std::string wellID = wellIdentifierStringForIndex(well, _valuesByWellAndDataColumn.size());
            NSString *plateAndWellID = [NSString stringWithFormat:@"%@-%s", plateID, wellID.c_str()];
            appendCSVElement(output, plateAndWellID);
            
            for (NSString *columnID in dataColumnIDs) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                
                std::string columnIDStdStr = std::string([columnID UTF8String]);
                
                ReportingStyle style = _reportingStyleByDataColumn[columnIDStdStr];
                if ((style & ReportingStyleMean) || (style & ReportingStyleStdDev)) {
                    double mean, stddev;
                    meanAndStdDev(_valuesByWellAndDataColumn[well][std::string(PresentationTimeID)], mean, stddev);
                    if (style & ReportingStyleMean) {
                        appendCSVElement(output, [NSString stringWithFormat:@"%f", mean]);
                    }
                    if (style & ReportingStyleStdDev) {
                        appendCSVElement(output, [NSString stringWithFormat:@"%f", stddev]);
                    }
                }
                
                [output appendString:@"\n"];
                
                // Append all raw values on a line, preceeded by the plate-well id
                if (style & ReportingStyleRaw) {
                    // Get the string for this column ID if we've already started one
                    NSMutableString *rawLine = [rawColumnIDsToCSVStrings objectForKey:columnID];
                    if (!rawLine) {
                        rawLine = [NSMutableString string];
                        [rawColumnIDsToCSVStrings setObject:rawLine forKey:columnID];
                    }
                    
                    appendCSVElement(rawLine, plateAndWellID);
                    const std::vector<double>* rawValues = &_valuesByWellAndDataColumn[well][columnIDStdStr];
                    for (size_t i = 0; i < rawValues->size(); i++) {
                        NSString *valueString = [[NSString alloc] initWithFormat:@"%f", rawValues->at(i)];
                        appendCSVElement(rawLine, valueString);
                        [valueString release];
                    }
                    [rawLine appendString:@"\n"];
                }
                
                [pool release];
            }
        }
        return output;
    }
}

static inline void appendCSVElement(NSMutableString *output, NSString *element)
{
    if ([element rangeOfString:@","].length > 0 || [element rangeOfString:@"\""].length > 0) {
        element = [element stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        element = [NSString stringWithFormat:@"\"%@\"", element];
    }
    
    [output appendString:element];
    [output appendString:@","];
}

@end
