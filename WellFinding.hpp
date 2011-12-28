//
//  WellFinding.hpp
//  WormAssay
//
//  Created by Chris Marcellino on 4/18/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "opencv2/core/core_c.h"

#ifdef __cplusplus
extern "C" {
#endif

// C compatible Circle structure
typedef struct {
    float center[2];
    float radius;
} Circle;

// Returns a vector of all well count configurations known.
extern std::vector<int> knownPlateWellCounts();

// Returns true if wellCount corresponds to a known plate configuration, and in that case returns the well arrangment values.
// Microplates have more columns than rows, by convention. 
extern bool getPlateConfigurationForWellCount(int wellCount, int &rows, int &columns);

// Returns true if the circles found correspond to the intended plate configuration. Well circles are returned in 
// row major order, as (x-center, y-center, radius) triples. The first version determines the well count automatically.
// The second provides a lower latency to failure when the number of wells expected is known. 
extern bool findWellCircles(IplImage* inputImage, std::vector<Circle> &circles, int wellCountHint = -1);
extern bool findWellCirclesForWellCount(IplImage* inputImage, int wellCount, std::vector<Circle> &circlesVec);

// Calcualtes the arithmetic mean of the circles' centers
extern CvPoint plateCenterForWellCircles(const std::vector<Circle> &circles);

// Returns true if the plate corresponding to the circle sets has moved or been removed during two sequential sets of samplings.
extern bool plateSequentialCirclesAppearSameAndStationary(const std::vector<Circle> &circlesPrevious,
                                                          const std::vector<Circle> &circlesCurrent);

// Draws circles and labels on an image
extern void drawWellCirclesAndLabelsOnDebugImage(std::vector<Circle> circles, CvScalar circleColor, bool drawLabels, IplImage* debugImage);

// Returns the canonical identifier string (e.g. "A3") for the index in the given plate type.
extern std::string wellIdentifierStringForIndex(int index, int wellCount);

static inline CvRect boundingSquareForCircle(Circle circle)
{
    float radius = circle.radius;
    return cvRect(circle.center[0] - radius, circle.center[1] - radius, 2 * radius, 2 * radius);
}

#ifdef __cplusplus
}
#endif
