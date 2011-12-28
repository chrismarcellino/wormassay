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
static const char* MovementUnitID = "Movement Units";
static const char* PresentationTimeID = "Timestamp";

static bool meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, size_t firstIndex = 0);
static inline NSString *valueAsString(double value, bool asPercent);
static inline void appendCSVElement(NSMutableString *output, NSString *element);

@interface PlateData () {
    NSUInteger _wellCount;
    NSTimeInterval _startPresentationTime;
    NSTimeInterval _lastPresentationTime;
    std::vector<std::map<std::string, std::vector<double> > > _valuesByWellAndDataColumn;
    std::map<std::string, ReportingStyle> _reportingStyleByDataColumn;
    NSUInteger _receivedFrameCount;
    NSUInteger _frameDropCount;
    NSUInteger _sampleCount;
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
@synthesize sampleCount = _sampleCount;

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
        if (_lastPresentationTime != presentationTime) {
            _sampleCount++;
            _lastPresentationTime = presentationTime;
        }
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

- (NSString *)csvOutputForPlateID:(NSString *)plateID
                           scanID:(NSString *)scanID
      withAdditionalRawDataOutput:(NSMutableDictionary *)rawColumnIDsToCSVStrings
                     analyzerName:(NSString *)analyzerName
                 columnMajorOrder:(BOOL)columnMajorOrder
{
    @synchronized(self) {
        NSMutableString *output = [NSMutableString string];
        
        // Write header row
        appendCSVElement(output, @"Plate and Well");
        appendCSVElement(output, @"Scan ID");
        appendCSVElement(output, @"Well");
        appendCSVElement(output, @"Assay Date/Time");
        
        NSArray *dataColumnIDs = [self sortedColumnIDsWithData];
        for (NSString *columnID in dataColumnIDs) {
            std::string columnIDStdStr = std::string([columnID UTF8String]);
            
            ReportingStyle style = _reportingStyleByDataColumn[columnIDStdStr];
            if (style & ReportingStyleMean) {
                appendCSVElement(output, [columnID stringByAppendingString:@" - Mean"]);
            }
            if (style & ReportingStyleStdDev) {
                appendCSVElement(output, [columnID stringByAppendingString:@" - Std. Dev."]);
            }
        }
        
        appendCSVElement(output, [NSString stringWithFormat:@"Assay: %@, version %@",
                                  [analyzerName stringByReplacingOccurrencesOfString:@"—" withString:@"-"],
                                  [[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleVersionKey]]);
        [output appendString:@"\n"];
        
        // Get the assay date/time
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterFullStyle];
        [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
        NSString *assayDateTime = [dateFormatter stringFromDate:[NSDate date]];
        [dateFormatter release];
        
        // Write stats for each well
        for (size_t i = 0; i < _valuesByWellAndDataColumn.size(); i++) {
            size_t well;
            if (columnMajorOrder) {
                int rows, columns;
                getPlateConfigurationForWellCount(_valuesByWellAndDataColumn.size(), rows, columns);
                well = (i % rows) * columns + i / rows;
            } else {
                well = i;
            }
            
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            
            // Output the plate-well ID
            std::string wellID = wellIdentifierStringForIndex(well, _valuesByWellAndDataColumn.size());
            NSString *wellIDString = [NSString stringWithUTF8String:wellID.c_str()];
            NSString *plateAndWellID = [NSString stringWithFormat:@"%@ Well %@", plateID, wellIDString];
            appendCSVElement(output, plateAndWellID);
            
            // Output the scan ID and well by themselves
            appendCSVElement(output, scanID);
            appendCSVElement(output, wellIDString);
            
            // Output the assay date/time
            appendCSVElement(output, assayDateTime);
            
            for (NSString *columnID in dataColumnIDs) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                
                std::string columnIDStdStr = std::string([columnID UTF8String]);
                
                ReportingStyle style = _reportingStyleByDataColumn[columnIDStdStr];
                if ((style & ReportingStyleMean) || (style & ReportingStyleStdDev)) {
                    double mean, stddev;
                    meanAndStdDev(_valuesByWellAndDataColumn[well][columnIDStdStr], mean, stddev);
                    if (style & ReportingStyleMean) {
                        appendCSVElement(output, valueAsString(mean, style & ReportingStylePercent));
                    }
                    if (style & ReportingStyleStdDev) {
                        appendCSVElement(output, valueAsString(stddev, style & ReportingStylePercent));
                    }
                }
                
                // Append all raw values on a line, preceeded by the plate-well id
                if (style & ReportingStyleRaw) {
                    // Get the string for this column ID if we've already started one
                    NSMutableString *rawLine = [rawColumnIDsToCSVStrings objectForKey:columnID];
                    if (!rawLine) {
                        rawLine = [NSMutableString string];
                        [rawColumnIDsToCSVStrings setObject:rawLine forKey:columnID];
                    }
                    
                    appendCSVElement(rawLine, plateAndWellID);
                    appendCSVElement(rawLine, scanID);
                    appendCSVElement(rawLine, wellIDString);
                    const std::vector<double>* rawValues = &_valuesByWellAndDataColumn[well][columnIDStdStr];
                    for (size_t i = 0; i < rawValues->size(); i++) {
                        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                        appendCSVElement(rawLine, valueAsString(rawValues->at(i), style & ReportingStylePercent));
                        [pool release];
                    }
                    [rawLine appendString:@"\n"];
                }
                
                [pool release];
            }
            [output appendString:@"\n"];
            [pool release];
        }
        [output appendString:@"\n"];
        return output;
    }
}

static inline NSString *valueAsString(double value, bool asPercent)
{
    return asPercent ? [NSString stringWithFormat:@"%.4g%%", value * 100.0] : [NSString stringWithFormat:@"%.4g", value];
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
