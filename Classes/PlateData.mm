//
//  PlateData.mm
//  WormAssay
//
//  Created by Chris Marcellino on 4/16/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "PlateData.h"
#import "WellFinding.hpp"
#import <string>
#import <map>

// Required data column identifiers
static const char* MovementUnitID = "Movement Units";
static const char* PresentationTimeID = "Timestamp";

static bool meanAndStdDev(const std::vector<double>& vec, double &mean, double &stddev, size_t firstIndex = 0);
static inline NSString *valueAsString(double value, bool asPercent);
static inline void appendCSVElement(NSMutableString *output, NSString *element);

@interface PlateData () {
    NSTimeInterval _startPresentationTime;
    NSTimeInterval _lastPresentationTime;
    BOOL _nonWellPlate;
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

@synthesize startPresentationTime = _startPresentationTime;
@synthesize lastPresentationTime = _lastPresentationTime;
@synthesize receivedFrameCount = _receivedFrameCount;
@synthesize frameDropCount = _frameDropCount;
@synthesize sampleCount = _sampleCount;

- (id)initWithWellCount:(NSUInteger)wellCount startPresentationTime:(NSTimeInterval)presentationTime
{
    if ((self = [super init])) {
        if (wellCount <= 0) {
            wellCount = 1;
            _nonWellPlate = YES;
        }
        _startPresentationTime = _lastPresentationTime = presentationTime;
        _valuesByWellAndDataColumn.resize(wellCount);
        
        [self setReportingStyle:(ReportingStyleMean | ReportingStyleStdDev | ReportingStyleRaw) forDataColumnID:MovementUnitID];
    }
    return self;
}

- (void)appendMovementUnit:(double)movementUnit atPresentationTime:(NSTimeInterval)presentationTime forWell:(int)well
{
    @synchronized(self) {
        NSAssert(presentationTime >= _lastPresentationTime, @"out of order presentation times");
        if (_lastPresentationTime != presentationTime) {
            _sampleCount++;
            _lastPresentationTime = presentationTime;
        }
        if (well == -1) {
            well = 0;
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
        if (well == -1) {
            well = 0;
        }
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
        if (well == -1) {
            well = 0;
        }
        return meanAndStdDev(_valuesByWellAndDataColumn[well][std::string(MovementUnitID)], *mean, *stddev);
    }
}

- (BOOL)movementUnitsMean:(double *)mean stdDev:(double *)stddev forWell:(int)well inLastSeconds:(NSTimeInterval)seconds
{
    @synchronized(self) {
        if (well == -1) {
            well = 0;
        }
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
    NSInteger numSamples = vec.size() - firstIndex;
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
        for (std::map<std::string, std::vector<double> >::iterator it = _valuesByWellAndDataColumn[0].begin(); it != _valuesByWellAndDataColumn[0].end(); it++) {
            NSString *columnID = [[NSString alloc] initWithUTF8String:(it->first).c_str()];
            [columnIDs addObject:columnID];
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
        
        NSTimeInterval elapsedTime = [self lastPresentationTime] - [self startPresentationTime];
        appendCSVElement(output, [NSString stringWithFormat:@"Elapsed time: %lu:%lu", (long)floor(elapsedTime / 60), lrint(fmod(elapsedTime, 60))]);
        appendCSVElement(output, [NSString stringWithFormat:@"Assay: %@, version %@",
                                  [analyzerName stringByReplacingOccurrencesOfString:@"—" withString:@"-"],
                                  [[NSBundle mainBundle] objectForInfoDictionaryKey:(id)kCFBundleVersionKey]]);
        [output appendString:@"\n"];
        
        // Get the assay date/time
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateStyle:NSDateFormatterFullStyle];
        [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
        NSString *assayDateTime = [dateFormatter stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-elapsedTime]];
        
        // Write stats for each well
        for (int i = 0; i < (int)_valuesByWellAndDataColumn.size(); i++) {
            int well;
            if (columnMajorOrder) {
                int rows, columns;
                getPlateConfigurationForWellCount((int)_valuesByWellAndDataColumn.size(), rows, columns);
                well = (i % rows) * columns + i / rows;
            } else {
                well = i;
            }
            
            @autoreleasepool {
                // Output the plate-well ID
                NSString *wellIDString;
                NSString *plateAndWellID;
                if (_nonWellPlate) {
                    wellIDString = @"entire plate";
                    plateAndWellID = [NSString stringWithFormat:@"%@ %@", plateID, wellIDString];
                } else {
                    std::string wellID = wellIdentifierStringForIndex(well, (int)_valuesByWellAndDataColumn.size());
                    wellIDString = [NSString stringWithUTF8String:wellID.c_str()];
                    plateAndWellID = [NSString stringWithFormat:@"%@ Well %@", plateID, wellIDString];
                }
                appendCSVElement(output, plateAndWellID);
                
                // Output the scan ID and well by themselves
                appendCSVElement(output, scanID);
                appendCSVElement(output, wellIDString);
                
                // Output the assay date/time
                appendCSVElement(output, assayDateTime);
                
                for (NSString *columnID in dataColumnIDs) {
                    @autoreleasepool {
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
                                
                                // Write out the header row with labels and times
                                appendCSVElement(rawLine, @"Plate and Well");
                                appendCSVElement(rawLine, @"Scan ID");
                                appendCSVElement(rawLine, @"Well/Times");
                                const std::vector<double>* rawTimes = &_valuesByWellAndDataColumn[well][std::string(PresentationTimeID)];
                                for (size_t i = 0; i < rawTimes->size(); i++) {
                                    @autoreleasepool {
                                        appendCSVElement(rawLine, [NSString stringWithFormat:@"%.3f", rawTimes->at(i)]);
                                    }
                                }
                                [rawLine appendString:@"\n"];
                            }
                            
                            appendCSVElement(rawLine, plateAndWellID);
                            appendCSVElement(rawLine, scanID);
                            appendCSVElement(rawLine, wellIDString);
                            const std::vector<double>* rawValues = &_valuesByWellAndDataColumn[well][columnIDStdStr];
                            for (size_t i = 0; i < rawValues->size(); i++) {
                                @autoreleasepool {
                                    appendCSVElement(rawLine, valueAsString(rawValues->at(i), style & ReportingStylePercent));
                                }
                            }
                            [rawLine appendString:@"\n"];
                        }
                        
                    }
                }
                [output appendString:@"\n"];
            }
        }
        [output appendString:@"\n"];
        
        // Append the additional information from the analyzer or the video processor
        if (_additionalResultsText) {
            [output appendString:@"\n"];
            appendCSVElement(output, _additionalResultsText);
            [output appendString:@"\n"];
        }
        
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
