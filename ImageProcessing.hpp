//
//  ImageProcessing.h
//  NematodeAssay
//
//  Created by Chris Marcellino on 4/4/11.
//  Copyright 2011 Regents of the University of California. All rights reserved.
//

#import "opencv2/core/core_c.h"

#ifdef __cplusplus
extern "C" {
#endif

// Returns a vector of all well count configurations known.
extern std::vector<int> knownPlateWellCounts();

// Returns true if wellCount corresponds to a known plate configuration, and in that case returns the well arrangment values.
// Microplates have more columns than rows, by convention. 
extern bool getPlateConfigurationForWellCount(int wellCount, int &rows, int &columns);

// Returns the canonical identifier string (e.g. "A3") for the index in the given plate type.
extern std::string wellIdentifierStringForIndex(int index, int wellCount);

// Returns true if the circles found correspond to the intended plate configuration. Well circles are returned in 
// row major order, as (x-center, y-center, radius) triples. The first version determines the well count automatically. 
extern bool findWellCircles(IplImage *inputImage, int &wellCount, std::vector<cv::Vec3f> &circles,  int wellCountHint = 0);
extern bool findWellCirclesForPlateCount(IplImage *inputImage, int wellCount, std::vector<cv::Vec3f> &circlesVec, float &score);

// Calcualtes the arithmetic mean of the circles' centers
extern CvPoint plateCenterForWellCircles(std::vector<cv::Vec3f> &circles);

// Returns true if the plate corresponding to the circle sets has moved or been removed during two sequential sets of samplings.
extern bool plateSequentialCirclesAppearSameAndStationary(std::vector<cv::Vec3f> &circlesPrevious, std::vector<cv::Vec3f> &circlesNext);

#ifdef __cplusplus
}
#endif
