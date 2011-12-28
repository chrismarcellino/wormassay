//
//  ImageProcessing.h
//  WormAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
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

// Returns the canonical identifier string (e.g. "A3") for the index in the given plate type.
extern std::string wellIdentifierStringForIndex(int index, int wellCount);

// Returns true if the circles found correspond to the intended plate configuration. Well circles are returned in 
// row major order, as (x-center, y-center, radius) triples. The first version determines the well count automatically. 
extern bool findWellCircles(IplImage *inputImage, std::vector<Circle> &circles, int wellCountHint = 0);
extern bool findWellCirclesForPlateCount(IplImage *inputImage, int wellCount, std::vector<Circle> &circlesVec, float *score = NULL);

// Calcualtes the arithmetic mean of the circles' centers
extern CvPoint plateCenterForWellCircles(const std::vector<Circle> &circles);

// Returns true if the plate corresponding to the circle sets has moved or been removed during two sequential sets of samplings.
extern bool plateSequentialCirclesAppearSameAndStationary(const std::vector<Circle> &circlesPrevious,
                                                          const std::vector<Circle> &circlesCurrent);

// Draws circles and labels on an image
extern void drawWellCirclesAndLabelsOnDebugImage(std::vector<Circle> circles, CvScalar circleColor, bool drawLabels, IplImage *debugImage);

// Counts the proportion of pixels that represent moved well contents between two frames. An empty vector is returned if the plate
// (or camera) has physically moved between the prev and cur images. 
extern std::vector<float> calculateMovedWellFractionPerSecondForWellsFromImages(IplImage *plateImagePrev,
                                                                                IplImage *plateImageCur,
                                                                                float timeDelta,
                                                                                const std::vector<Circle> &circles,
                                                                                IplImage *debugImage);

// Calculates the proportion of edge pixels in the image using the Canny edge detector. This can be used to determine well occupancy. 
extern std::vector<float> calculateCannyEdgePixelProportionForWellsFromImages(IplImage *plateImage, const std::vector<Circle> &circles, IplImage *debugImage);

// Returns a font with drawing size proportional to the image provided with respect to normalizedScale.
extern CvFont fontForNormalizedScale(double normalizedScale, IplImage *image);

#define CV_RGBA( r, g, b, a )  cvScalar( (b), (g), (r), (a) )

#ifdef __cplusplus
}
#endif
