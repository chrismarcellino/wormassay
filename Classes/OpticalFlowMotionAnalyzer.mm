//
//  OpticalFlowMotionAnalyzer.mm
//  WormAssay
//
//  Created by Chris Marcellino on 5/12/11.
//  Copyright 2011 Chris Marcellino. All rights reserved.
//

#import "OpticalFlowMotionAnalyzer.h"
#import "PlateData.h"
#import "VideoFrame.h"
#import "CvUtilities.hpp"
#import "opencv2/imgproc/imgproc_c.h"
#import "opencv2/video/tracking.hpp"

// See comments below
static void cvCalcOpticalFlowPyrLK_OpenCV2dot2(const void* arrA, const void* arrB,
                                               void* pyrarrA, void* pyrarrB,
                                               const CvPoint2D32f * featuresA,
                                               CvPoint2D32f * featuresB,
                                               int count, CvSize winSize, int level,
                                               char *status, float *error,
                                               CvTermCriteria criteria, int flags);


static const char* WellOccupancyID = "Well Occupancy";
static const double WellEdgeFindingInsetProportion = 0.8;
static const double MaximumNumberOfFeaturePointsToAreaRatio = 1.0 / 200.0;
static const double DeltaMeanMovementLimit = 20.0;
static const double DeltaStdDevMovementLimit = 10.0;
static const NSTimeInterval MinimumIntervalFrameInterval = 0.100;
static const double MinimumMovementMagnitude = 0.5;


@implementation OpticalFlowMotionAnalyzer

- (id)init
{
    if ((self = [super init])) {
        _lastFrames = [[NSMutableArray alloc] init];
    }
    return self;
}

+ (NSString *)analyzerName
{
    return NSLocalizedString(@"Lucas—Kanade Optical Flow (Velocity, 1 organism per well)", nil);
}

- (BOOL)canProcessInParallel
{
    return YES;
}

- (void)willBeginPlateTrackingWithPlateData:(PlateData *)plateData
{
    [plateData setReportingStyle:(ReportingStyleMean | ReportingStyleStdDev | ReportingStylePercent) forDataColumnID:WellOccupancyID];
}

- (BOOL)willBeginFrameProcessing:(VideoFrame *)videoFrame debugImage:(IplImage*)debugImage plateData:(PlateData *)plateData
{
    // Find the most recent video frame that is at least 100 ms earlier than the current and discard older frames
    _prevFrame = nil;
    for (NSInteger i = (NSInteger)[_lastFrames count] - 1; i >= 0; i--) {
        VideoFrame *aFrame = [_lastFrames objectAtIndex:i];
        if ([videoFrame presentationTime] - [aFrame presentationTime] >= MinimumIntervalFrameInterval) {
            _prevFrame = aFrame;
            // use i, not "i + 1" so we don't delete the one we chose in case we don't get a better one next time
            [_lastFrames removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, i)]];
            break;
        }
    }
        
    if (!_prevFrame) {
        _lastMovementThresholdPresentationTime = -FLT_MAX;
        return NO;
    }
    
    // Calculate the mean inter-frame delta for plate movement/lighting change determination
    IplImage* plateDelta = cvCreateImage(cvGetSize([videoFrame image]), IPL_DEPTH_8U, 4);
    cvAbsDiff([videoFrame image], [_prevFrame image], plateDelta);
    CvScalar mean, stdDev;
    cvAvgSdv(plateDelta, &mean, &stdDev);
    double deltaMean = (mean.val[0] + mean.val[1] + mean.val[2]) / 3.0;
    double deltaStdDevAvg = (stdDev.val[0] + stdDev.val[1] + stdDev.val[2]) / 3.0;
    cvReleaseImage(&plateDelta);

    BOOL overThreshold = deltaMean > DeltaMeanMovementLimit || deltaStdDevAvg > DeltaStdDevMovementLimit;
    if (overThreshold || _lastMovementThresholdPresentationTime == 0) {     // start in moved mode
        _lastMovementThresholdPresentationTime = [videoFrame presentationTime];
    }
    
    if (overThreshold || _lastMovementThresholdPresentationTime + IgnoreFramesPostMovementTimeInterval() > [videoFrame presentationTime]) {
        // Draw the movement text
        CvFont wellFont = fontForNormalizedScale(3.5, debugImage);
        cvPutText(debugImage,
                  "PLATE OR LIGHTING MOVING",
                  cvPoint(debugImage->width * 0.075, debugImage->height * 0.55),
                  &wellFont,
                  CV_RGBA(232, 0, 217, 255));
        return NO;
    }
    
    return YES;
}

- (void)processVideoFrameWellSynchronously:(IplImage*)wellImage
                                   forWell:(int)well
                                debugImage:(IplImage*)debugImage
                          presentationTime:(NSTimeInterval)presentationTime
                                 plateData:(PlateData *)plateData
{
    CvSize size = cvGetSize(wellImage);
    // Get the previous well (using a local stack copy of the header for threadsafety)
    IplImage prevWellImage = *[_prevFrame image];
    cvSetImageROI(&prevWellImage, cvGetImageROI(wellImage));
    
    // ======= Contour finding ========
    
    // Create a circle mask with all bits on in the circle using only a portion of the circle to avoid taking the well walls
    int radius = size.width / 2;
    IplImage *insetCircleMask = NULL;
    if (well >= 0) {
        insetCircleMask = cvCreateImage(size, IPL_DEPTH_8U, 1);
        fastZeroImage(insetCircleMask);
        cvCircle(insetCircleMask, cvPoint(insetCircleMask->width / 2, insetCircleMask->height / 2), radius * WellEdgeFindingInsetProportion, cvRealScalar(255), CV_FILLED);
    }
    
    // Find edges in the image
    IplImage* cannyEdges = cvCreateImage(size, IPL_DEPTH_8U, 1);
    cvCanny(wellImage, cannyEdges, 50, 150);
    
    // Mask off the edge pixels that correspond to the wells
    if (insetCircleMask) {
        cvAnd(cannyEdges, insetCircleMask, cannyEdges);
        cvReleaseImage(&insetCircleMask);
    }
    
    // Get the edge points
    std::vector<CvPoint2D32f> featuresCur;
    featuresCur.reserve(1024);
    assert(cannyEdges->depth == IPL_DEPTH_8U);
    uchar *row = (uchar *)cannyEdges->imageData;
    for (int i = 0; i < cannyEdges->height; i++) {
        for (int j = 0; j < cannyEdges->width; j++) {
            if (row[j]) {
                featuresCur.push_back(cvPoint2D32f(j, i));
            }
        }
        row += cannyEdges->widthStep;
    }
    // If we have too many points, randomly shuffle MaximumNumberOfFeaturePoints to the begining and keep that set
    size_t maxNumberOfFeatures = M_PI * radius * radius * MaximumNumberOfFeaturePointsToAreaRatio;
    if (featuresCur.size() > maxNumberOfFeatures) {
        for (size_t i = 0; i < maxNumberOfFeatures; i++) {
            size_t other = random() % featuresCur.size();
            std::swap(featuresCur[i], featuresCur[other]);
        }
        featuresCur.resize(maxNumberOfFeatures);
    }
    
    // Store the pixel counts and draw debugging images
    double occupancyFraction = (double)cvCountNonZero(cannyEdges) / (cannyEdges->width * cannyEdges->height);
    [plateData appendResult:occupancyFraction toDataColumnID:WellOccupancyID forWell:well];
    cvSet(debugImage, CV_RGBA(0, 0, 255, 255), cannyEdges);
    cvReleaseImage(&cannyEdges);
    
    // ======== Motion measurement =========
    
    CvSize pyrSize = cvSize(size.width + 8, size.height / 3);
	IplImage* curPyr = cvCreateImage(pyrSize, IPL_DEPTH_32F, 1);
    IplImage* prevPyr = cvCreateImage(pyrSize, IPL_DEPTH_32F, 1);
    
    CvPoint2D32f* featuresPrev = new CvPoint2D32f[featuresCur.size()];
    char *featuresPrevFound = new char[featuresCur.size()];
    
    // Get grayscale subimages for the previous and current well
    IplImage* grayscalePrevImage = cvCreateImage(cvGetSize(&prevWellImage), IPL_DEPTH_8U, 1);
    cvCvtColor(&prevWellImage, grayscalePrevImage, CV_BGRA2GRAY);
    IplImage* grayscaleCurImage = cvCreateImage(cvGetSize(wellImage), IPL_DEPTH_8U, 1);
    cvCvtColor(wellImage, grayscaleCurImage, CV_BGRA2GRAY);

    // Reverse Optical Flow vector calculation direction (to current frame to previous frame), to make blue edge outline
    // correspond to worm better. Also see comments about the 2.2 version of cvCalcOpticalFlowPyrLK() below.
    cvCalcOpticalFlowPyrLK_OpenCV2dot2(grayscaleCurImage,
                                       grayscalePrevImage,
                                       curPyr,
                                       prevPyr,
                                       &*featuresCur.begin(),
                                       featuresPrev,
                                       (int)featuresCur.size(),
                                       cvSize(15, 15),      // pyramid window size
                                       5,                   // number of pyramid levels
                                       featuresPrevFound,
                                       NULL,
                                       cvTermCriteria(CV_TERMCRIT_ITER | CV_TERMCRIT_EPS, 20, 0.3),
                                       0);
    
    cvReleaseImage(&grayscalePrevImage);
    cvReleaseImage(&grayscaleCurImage);
    
    // Iterate through the feature points and get the average movement
    float averageMovement = 0.0;
    size_t countFound = 0;
    for (size_t i = 0; i < featuresCur.size(); i++) {
        if (featuresPrevFound[i]) {
            CvPoint2D32f delta = { featuresPrev[i].x - featuresCur[i].x, featuresPrev[i].y - featuresCur[i].y };
            float magnitude = sqrtf(delta.x * delta.x + delta.y * delta.y);
            if (magnitude > MinimumMovementMagnitude && magnitude < radius) {
                countFound++;
                averageMovement += magnitude;
                
                // Draw arrows on the debug image
                CvScalar lineColor = CV_RGBA(255, 0, 0, 255);
                const int lineWidth = 2;
                const int arrowLength = 5;
                CvPoint2D32f p = featuresPrev[i];
                CvPoint2D32f c = featuresCur[i];
                p.x += p.x - c.x;       // double the vector length for visibility
                p.y += p.y - c.y;
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
                double angle = atan2(p.y - c.y, p.x - c.x);
                p.x = c.x + arrowLength * cos(angle + M_PI_4);
                p.y = c.y + arrowLength * sin(angle + M_PI_4);
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
                p.x = c.x + arrowLength * cos(angle - M_PI_4);
                p.y = c.y + arrowLength * sin(angle - M_PI_4);
                cvLine(debugImage, cvPointFrom32f(p), cvPointFrom32f(c), lineColor, lineWidth);
            }
        }
    }
    if (countFound > 0) {
        averageMovement /= countFound;
    }
    double averageMovementPerSecond = averageMovement / (presentationTime - [_prevFrame presentationTime]);
    [plateData appendMovementUnit:averageMovementPerSecond atPresentationTime:presentationTime forWell:well];
    
    cvReleaseImage(&curPyr);
    cvReleaseImage(&prevPyr);
    delete[] featuresPrevFound;
    delete[] featuresPrev;
    
    cvResetImageROI(&prevWellImage);
}

- (void)didEndFrameProcessing:(VideoFrame *)videoFrame plateData:(PlateData *)plateData
{
    [_lastFrames addObject:videoFrame];
}

- (void)didEndTrackingPlateWithPlateData:(PlateData *)plateData
{
    // nothing
}

- (NSTimeInterval)minimumTimeIntervalProcessedToReportData
{
    return 5.0;
}

- (NSUInteger)minimumSamplesProcessedToReportData
{
    return 5;
}

@end


// This OpenCV 2.2 version of LK has less noise and more accurate output than newer versions, due to
// aggressive refactoring of OpenCV in later versions. We'll keep our own copy of this function to ensure
// score stability and accuracy.


// This license applies to the code BELOW this line:
/*M///////////////////////////////////////////////////////////////////////////////////////
 //
 //  IMPORTANT: READ BEFORE DOWNLOADING, COPYING, INSTALLING OR USING.
 //
 //  By downloading, copying, installing or using the software you agree to this license.
 //  If you do not agree to this license, do not download, install,
 //  copy or use the software.
 //
 //
 //                        Intel License Agreement
 //                For Open Source Computer Vision Library
 //
 // Copyright (C) 2000, Intel Corporation, all rights reserved.
 // Third party copyrights are property of their respective owners.
 //
 // Redistribution and use in source and binary forms, with or without modification,
 // are permitted provided that the following conditions are met:
 //
 //   * Redistribution's of source code must retain the above copyright notice,
 //     this list of conditions and the following disclaimer.
 //
 //   * Redistribution's in binary form must reproduce the above copyright notice,
 //     this list of conditions and the following disclaimer in the documentation
 //     and/or other materials provided with the distribution.
 //
 //   * The name of Intel Corporation may not be used to endorse or promote products
 //     derived from this software without specific prior written permission.
 //
 // This software is provided by the copyright holders and contributors "as is" and
 // any express or implied warranties, including, but not limited to, the implied
 // warranties of merchantability and fitness for a particular purpose are disclaimed.
 // In no event shall the Intel Corporation or contributors be liable for any direct,
 // indirect, incidental, special, exemplary, or consequential damages
 // (including, but not limited to, procurement of substitute goods or services;
 // loss of use, data, or profits; or business interruption) however caused
 // and on any theory of liability, whether in contract, strict liability,
 // or tort (including negligence or otherwise) arising in any way out of
 // the use of this software, even if advised of the possibility of such damage.
 //
 //M*/
#include "precomp.hpp"
#include <float.h>
#include <stdio.h>


static void
intersect( CvPoint2D32f pt, CvSize win_size, CvSize imgSize,
          CvPoint* min_pt, CvPoint* max_pt )
{
    CvPoint ipt;
    
    ipt.x = cvFloor( pt.x );
    ipt.y = cvFloor( pt.y );
    
    ipt.x -= win_size.width;
    ipt.y -= win_size.height;
    
    win_size.width = win_size.width * 2 + 1;
    win_size.height = win_size.height * 2 + 1;
    
    min_pt->x = MAX( 0, -ipt.x );
    min_pt->y = MAX( 0, -ipt.y );
    max_pt->x = MIN( win_size.width, imgSize.width - ipt.x );
    max_pt->y = MIN( win_size.height, imgSize.height - ipt.y );
}


static int icvMinimalPyramidSize( CvSize imgSize )
{
    return cvAlign(imgSize.width,8) * imgSize.height / 3;
}


static void
icvInitPyramidalAlgorithm( const CvMat* imgA, const CvMat* imgB,
                          CvMat* pyrA, CvMat* pyrB,
                          int level, CvTermCriteria * criteria,
                          int max_iters, int flags,
                          uchar *** imgI, uchar *** imgJ,
                          int **step, CvSize** size,
                          double **scale, cv::AutoBuffer<uchar>* buffer )
{
    const int ALIGN = 8;
    int pyrBytes, bufferBytes = 0, elem_size;
    int level1 = level + 1;
    
    int i;
    CvSize imgSize, levelSize;
    
    *imgI = *imgJ = 0;
    *step = 0;
    *scale = 0;
    *size = 0;
    
    /* check input arguments */
    if( ((flags & CV_LKFLOW_PYR_A_READY) != 0 && !pyrA) ||
       ((flags & CV_LKFLOW_PYR_B_READY) != 0 && !pyrB) )
        CV_Error( CV_StsNullPtr, "Some of the precomputed pyramids are missing" );
    assert(pyrA && pyrB);   // CRM 8/15/2014: silence static analyzer
    
    if( level < 0 )
        CV_Error( CV_StsOutOfRange, "The number of pyramid levels is negative" );
    
    switch( criteria->type )
    {
        case CV_TERMCRIT_ITER:
            criteria->epsilon = 0.f;
            break;
        case CV_TERMCRIT_EPS:
            criteria->max_iter = max_iters;
            break;
        case CV_TERMCRIT_ITER | CV_TERMCRIT_EPS:
            break;
        default:
            assert( 0 );
            CV_Error( CV_StsBadArg, "Invalid termination criteria" );
    }
    
    /* compare squared values */
    criteria->epsilon *= criteria->epsilon;
    
    /* set pointers and step for every level */
    pyrBytes = 0;
    
    imgSize = cvGetSize(imgA);
    elem_size = CV_ELEM_SIZE(imgA->type);
    levelSize = imgSize;
    
    for( i = 1; i < level1; i++ )
    {
        levelSize.width = (levelSize.width + 1) >> 1;
        levelSize.height = (levelSize.height + 1) >> 1;
        
        int tstep = cvAlign(levelSize.width,ALIGN) * elem_size;
        pyrBytes += tstep * levelSize.height;
    }
    
    assert( pyrBytes <= imgSize.width * imgSize.height * elem_size * 4 / 3 );
    
    /* buffer_size = <size for patches> + <size for pyramids> */
    bufferBytes = (int)((level1 >= 0) * ((pyrA->data.ptr == 0) +
                                         (pyrB->data.ptr == 0)) * pyrBytes +
                        (sizeof(imgI[0][0]) * 2 + sizeof(step[0][0]) +
                         sizeof(size[0][0]) + sizeof(scale[0][0])) * level1);
    
    buffer->allocate( bufferBytes );
    
    *imgI = (uchar **) (uchar*)(*buffer);
    *imgJ = *imgI + level1;
    *step = (int *) (*imgJ + level1);
    *scale = (double *) (*step + level1);
    *size = (CvSize *)(*scale + level1);
    
    imgI[0][0] = imgA->data.ptr;
    imgJ[0][0] = imgB->data.ptr;
    step[0][0] = imgA->step;
    scale[0][0] = 1;
    size[0][0] = imgSize;
    
    if( level > 0 )
    {
        uchar *bufPtr = (uchar *) (*size + level1);
        uchar *ptrA = pyrA->data.ptr;
        uchar *ptrB = pyrB->data.ptr;
        
        if( !ptrA )
        {
            ptrA = bufPtr;
            bufPtr += pyrBytes;
        }
        
        if( !ptrB )
            ptrB = bufPtr;
        
        levelSize = imgSize;
        
        /* build pyramids for both frames */
        for( i = 1; i <= level; i++ )
        {
            int levelBytes;
            CvMat prev_level, next_level;
            
            levelSize.width = (levelSize.width + 1) >> 1;
            levelSize.height = (levelSize.height + 1) >> 1;
            
            size[0][i] = levelSize;
            step[0][i] = cvAlign( levelSize.width, ALIGN ) * elem_size;
            scale[0][i] = scale[0][i - 1] * 0.5;
            
            levelBytes = step[0][i] * levelSize.height;
            imgI[0][i] = (uchar *) ptrA;
            ptrA += levelBytes;
            
            if( !(flags & CV_LKFLOW_PYR_A_READY) )
            {
                prev_level = cvMat( size[0][i-1].height, size[0][i-1].width, CV_8UC1 );
                next_level = cvMat( size[0][i].height, size[0][i].width, CV_8UC1 );
                cvSetData( &prev_level, imgI[0][i-1], step[0][i-1] );
                cvSetData( &next_level, imgI[0][i], step[0][i] );
                cvPyrDown( &prev_level, &next_level );
            }
            
            imgJ[0][i] = (uchar *) ptrB;
            ptrB += levelBytes;
            
            if( !(flags & CV_LKFLOW_PYR_B_READY) )
            {
                prev_level = cvMat( size[0][i-1].height, size[0][i-1].width, CV_8UC1 );
                next_level = cvMat( size[0][i].height, size[0][i].width, CV_8UC1 );
                cvSetData( &prev_level, imgJ[0][i-1], step[0][i-1] );
                cvSetData( &next_level, imgJ[0][i], step[0][i] );
                cvPyrDown( &prev_level, &next_level );
            }
        }
    }
}


/* compute dI/dx and dI/dy */
static void
icvCalcIxIy_32f( const float* src, int src_step, float* dstX, float* dstY, int dst_step,
                CvSize src_size, const float* smooth_k, float* buffer0 )
{
    int src_width = src_size.width, dst_width = src_size.width-2;
    int x, height = src_size.height - 2;
    float* buffer1 = buffer0 + src_width;
    
    src_step /= sizeof(src[0]);
    dst_step /= sizeof(dstX[0]);
    
    for( ; height--; src += src_step, dstX += dst_step, dstY += dst_step )
    {
        const float* src2 = src + src_step;
        const float* src3 = src + src_step*2;
        
        for( x = 0; x < src_width; x++ )
        {
            float t0 = (src3[x] + src[x])*smooth_k[0] + src2[x]*smooth_k[1];
            float t1 = src3[x] - src[x];
            buffer0[x] = t0; buffer1[x] = t1;
        }
        
        for( x = 0; x < dst_width; x++ )
        {
            float t0 = buffer0[x+2] - buffer0[x];
            float t1 = (buffer1[x] + buffer1[x+2])*smooth_k[0] + buffer1[x+1]*smooth_k[1];
            dstX[x] = t0; dstY[x] = t1;
        }
    }
}


#undef CV_8TO32F
#define CV_8TO32F(a) (a)

static const void*
icvAdjustRect( const void* srcptr, int src_step, int pix_size,
              CvSize src_size, CvSize win_size,
              CvPoint ip, CvRect* pRect )
{
    CvRect rect;
    const char* src = (const char*)srcptr;
    
    if( ip.x >= 0 )
    {
        src += ip.x*pix_size;
        rect.x = 0;
    }
    else
    {
        rect.x = -ip.x;
        if( rect.x > win_size.width )
            rect.x = win_size.width;
    }
    
    if( ip.x + win_size.width < src_size.width )
        rect.width = win_size.width;
    else
    {
        rect.width = src_size.width - ip.x - 1;
        if( rect.width < 0 )
        {
            src += rect.width*pix_size;
            rect.width = 0;
        }
        assert( rect.width <= win_size.width );
    }
    
    if( ip.y >= 0 )
    {
        src += ip.y * src_step;
        rect.y = 0;
    }
    else
        rect.y = -ip.y;
    
    if( ip.y + win_size.height < src_size.height )
        rect.height = win_size.height;
    else
    {
        rect.height = src_size.height - ip.y - 1;
        if( rect.height < 0 )
        {
            src += rect.height*src_step;
            rect.height = 0;
        }
    }
    
    *pRect = rect;
    return src - rect.x*pix_size;
}


static CvStatus CV_STDCALL icvGetRectSubPix_8u32f_C1R_OpenCV2dot2
( const uchar* src, int src_step, CvSize src_size,
 float* dst, int dst_step, CvSize win_size, CvPoint2D32f center )
{
    CvPoint ip;
    float  a12, a22, b1, b2;
    float a, b;
    double s = 0;
    int i, j;
    
    center.x -= (win_size.width-1)*0.5f;
    center.y -= (win_size.height-1)*0.5f;
    
    ip.x = cvFloor( center.x );
    ip.y = cvFloor( center.y );
    
    if( win_size.width <= 0 || win_size.height <= 0 )
        return CV_BADRANGE_ERR;
    
    a = center.x - ip.x;
    b = center.y - ip.y;
    a = MAX(a,0.0001f);
    a12 = a*(1.f-b);
    a22 = a*b;
    b1 = 1.f - b;
    b2 = b;
    s = (1. - a)/a;
    
    src_step /= sizeof(src[0]);
    dst_step /= sizeof(dst[0]);
    
    if( 0 <= ip.x && ip.x + win_size.width < src_size.width &&
       0 <= ip.y && ip.y + win_size.height < src_size.height )
    {
        // extracted rectangle is totally inside the image
        src += ip.y * src_step + ip.x;
        
#if 0
        if( icvCopySubpix_8u32f_C1R_p &&
           icvCopySubpix_8u32f_C1R_p( src, src_step, dst,
                                     dst_step*sizeof(dst[0]), win_size, a, b ) >= 0 )
            return CV_OK;
#endif
        
        for( ; win_size.height--; src += src_step, dst += dst_step )
        {
            float prev = (1 - a)*(b1*CV_8TO32F(src[0]) + b2*CV_8TO32F(src[src_step]));
            for( j = 0; j < win_size.width; j++ )
            {
                float t = a12*CV_8TO32F(src[j+1]) + a22*CV_8TO32F(src[j+1+src_step]);
                dst[j] = prev + t;
                prev = (float)(t*s);
            }
        }
    }
    else
    {
        CvRect r;
        
        src = (const uchar*)icvAdjustRect( src, src_step*sizeof(*src),
                                          sizeof(*src), src_size, win_size,ip, &r);
        
        for( i = 0; i < win_size.height; i++, dst += dst_step )
        {
            const uchar *src2 = src + src_step;
            
            if( i < r.y || i >= r.height )
                src2 -= src_step;
            
            for( j = 0; j < r.x; j++ )
            {
                float s0 = CV_8TO32F(src[r.x])*b1 +
                CV_8TO32F(src2[r.x])*b2;
                
                dst[j] = (float)(s0);
            }
            
            if( j < r.width )
            {
                float prev = (1 - a)*(b1*CV_8TO32F(src[j]) + b2*CV_8TO32F(src2[j]));
                
                for( ; j < r.width; j++ )
                {
                    float t = a12*CV_8TO32F(src[j+1]) + a22*CV_8TO32F(src2[j+1]);
                    dst[j] = prev + t;
                    prev = (float)(t*s);
                }
            }
            
            for( ; j < win_size.width; j++ )
            {
                float s0 = CV_8TO32F(src[r.width])*b1 +
                CV_8TO32F(src2[r.width])*b2;
                
                dst[j] = (float)(s0);
            }
            
            if( i < r.height )
                src = src2;
        }
    }
    
    return CV_OK;
}

namespace cv
{
    
    struct LKTrackerInvoker
    {
        LKTrackerInvoker( const CvMat* _imgI, const CvMat* _imgJ,
                         const CvPoint2D32f* _featuresA,
                         CvPoint2D32f* _featuresB,
                         char* _status, float* _error,
                         CvTermCriteria _criteria,
                         CvSize _winSize, int _level, int _flags )
        {
            imgI = _imgI;
            imgJ = _imgJ;
            featuresA = _featuresA;
            featuresB = _featuresB;
            status = _status;
            error = _error;
            criteria = _criteria;
            winSize = _winSize;
            level = _level;
            flags = _flags;
        }
        
        void operator()(const BlockedRange& range) const
        {
            static const float smoothKernel[] = { 0.09375, 0.3125, 0.09375 };  // 3/32, 10/32, 3/32
            
            int i, i1 = range.begin(), i2 = range.end();
            
            CvSize patchSize = cvSize( winSize.width * 2 + 1, winSize.height * 2 + 1 );
            int patchLen = patchSize.width * patchSize.height;
            int srcPatchLen = (patchSize.width + 2)*(patchSize.height + 2);
            
            AutoBuffer<float> buf(patchLen*3 + srcPatchLen);
            float* patchI = buf;
            float* patchJ = patchI + srcPatchLen;
            float* Ix = patchJ + patchLen;
            float* Iy = Ix + patchLen;
            float scaleL = 1.f/(1 << level);
            CvSize levelSize = cvGetMatSize(imgI);
            
            // find flow for each given point
            for( i = i1; i < i2; i++ )
            {
                CvPoint2D32f v;
                CvPoint minI, maxI, minJ, maxJ;
                CvSize isz, jsz;
                int pt_status;
                CvPoint2D32f u;
                CvPoint prev_minJ = { -1, -1 }, prev_maxJ = { -1, -1 };
                double Gxx = 0, Gxy = 0, Gyy = 0, D = 0, minEig = 0;
                float prev_mx = 0, prev_my = 0;
                int j, x, y;
                
                v.x = featuresB[i].x*2;
                v.y = featuresB[i].y*2;
                
                pt_status = status[i];
                if( !pt_status )
                    continue;
                
                minI = maxI = minJ = maxJ = cvPoint(0, 0);
                
                u.x = featuresA[i].x * scaleL;
                u.y = featuresA[i].y * scaleL;
                
                intersect( u, winSize, levelSize, &minI, &maxI );
                isz = jsz = cvSize(maxI.x - minI.x + 2, maxI.y - minI.y + 2);
                u.x += (minI.x - (patchSize.width - maxI.x + 1))*0.5f;
                u.y += (minI.y - (patchSize.height - maxI.y + 1))*0.5f;
                
                if( isz.width < 3 || isz.height < 3 ||
                   icvGetRectSubPix_8u32f_C1R_OpenCV2dot2( imgI->data.ptr, imgI->step, levelSize,
                                              patchI, isz.width*sizeof(patchI[0]), isz, u ) < 0 )
                {
                    // point is outside the first image. take the next
                    status[i] = 0;
                    continue;
                }
                
                icvCalcIxIy_32f( patchI, isz.width*sizeof(patchI[0]), Ix, Iy,
                                (isz.width-2)*sizeof(patchI[0]), isz, smoothKernel, patchJ );
                
                for( j = 0; j < criteria.max_iter; j++ )
                {
                    double bx = 0, by = 0;
                    float mx, my;
                    CvPoint2D32f _v;
                    
                    intersect( v, winSize, levelSize, &minJ, &maxJ );
                    
                    minJ.x = MAX( minJ.x, minI.x );
                    minJ.y = MAX( minJ.y, minI.y );
                    
                    maxJ.x = MIN( maxJ.x, maxI.x );
                    maxJ.y = MIN( maxJ.y, maxI.y );
                    
                    jsz = cvSize(maxJ.x - minJ.x, maxJ.y - minJ.y);
                    
                    _v.x = v.x + (minJ.x - (patchSize.width - maxJ.x + 1))*0.5f;
                    _v.y = v.y + (minJ.y - (patchSize.height - maxJ.y + 1))*0.5f;
                    
                    if( jsz.width < 1 || jsz.height < 1 ||
                       icvGetRectSubPix_8u32f_C1R_OpenCV2dot2( imgJ->data.ptr, imgJ->step, levelSize, patchJ,
                                                  jsz.width*sizeof(patchJ[0]), jsz, _v ) < 0 )
                    {
                        // point is outside of the second image. take the next
                        pt_status = 0;
                        break;
                    }
                    
                    if( maxJ.x == prev_maxJ.x && maxJ.y == prev_maxJ.y &&
                       minJ.x == prev_minJ.x && minJ.y == prev_minJ.y )
                    {
                        for( y = 0; y < jsz.height; y++ )
                        {
                            const float* pi = patchI +
                            (y + minJ.y - minI.y + 1)*isz.width + minJ.x - minI.x + 1;
                            const float* pj = patchJ + y*jsz.width;
                            const float* ix = Ix +
                            (y + minJ.y - minI.y)*(isz.width-2) + minJ.x - minI.x;
                            const float* iy = Iy + (ix - Ix);
                            
                            for( x = 0; x < jsz.width; x++ )
                            {
                                double t0 = pi[x] - pj[x];
                                bx += t0 * ix[x];
                                by += t0 * iy[x];
                            }
                        }
                    }
                    else
                    {
                        Gxx = Gyy = Gxy = 0;
                        for( y = 0; y < jsz.height; y++ )
                        {
                            const float* pi = patchI +
                            (y + minJ.y - minI.y + 1)*isz.width + minJ.x - minI.x + 1;
                            const float* pj = patchJ + y*jsz.width;
                            const float* ix = Ix +
                            (y + minJ.y - minI.y)*(isz.width-2) + minJ.x - minI.x;
                            const float* iy = Iy + (ix - Ix);
                            
                            for( x = 0; x < jsz.width; x++ )
                            {
                                double t = pi[x] - pj[x];
                                bx += (double) (t * ix[x]);
                                by += (double) (t * iy[x]);
                                Gxx += ix[x] * ix[x];
                                Gxy += ix[x] * iy[x];
                                Gyy += iy[x] * iy[x];
                            }
                        }
                        
                        D = Gxx * Gyy - Gxy * Gxy;
                        if( D < DBL_EPSILON )
                        {
                            pt_status = 0;
                            break;
                        }
                        
                        // Adi Shavit - 2008.05
                        if( flags & CV_LKFLOW_GET_MIN_EIGENVALS )
                            minEig = (Gyy + Gxx - sqrt((Gxx-Gyy)*(Gxx-Gyy) + 4.*Gxy*Gxy))/(2*jsz.height*jsz.width);
                        
                        D = 1. / D;
                        
                        prev_minJ = minJ;
                        prev_maxJ = maxJ;
                    }
                    
                    mx = (float) ((Gyy * bx - Gxy * by) * D);
                    my = (float) ((Gxx * by - Gxy * bx) * D);
                    
                    v.x += mx;
                    v.y += my;
                    
                    if( mx * mx + my * my < criteria.epsilon )
                        break;
                    
                    if( j > 0 && fabs(mx + prev_mx) < 0.01 && fabs(my + prev_my) < 0.01 )
                    {
                        v.x -= mx*0.5f;
                        v.y -= my*0.5f;
                        break;
                    }
                    prev_mx = mx;
                    prev_my = my;
                }
                
                featuresB[i] = v;
                status[i] = (char)pt_status;
                if( level == 0 && error && pt_status )
                {
                    // calc error
                    double err = 0;
                    if( flags & CV_LKFLOW_GET_MIN_EIGENVALS )
                        err = minEig;
                    else
                    {
                        for( y = 0; y < jsz.height; y++ )
                        {
                            const float* pi = patchI +
                            (y + minJ.y - minI.y + 1)*isz.width + minJ.x - minI.x + 1;
                            const float* pj = patchJ + y*jsz.width;
                            
                            for( x = 0; x < jsz.width; x++ )
                            {
                                double t = pi[x] - pj[x];
                                err += t * t;
                            }
                        }
                        err = sqrt(err);
                    }
                    error[i] = (float)err;
                }
            } // end of point processing loop (i)
        }
        
        const CvMat* imgI;
        const CvMat* imgJ;
        const CvPoint2D32f* featuresA;
        CvPoint2D32f* featuresB;
        char* status;
        float* error;
        CvTermCriteria criteria;
        CvSize winSize;
        int level;
        int flags;
    };
    
    
}


static void cvCalcOpticalFlowPyrLK_OpenCV2dot2(const void* arrA, const void* arrB,
                                               void* pyrarrA, void* pyrarrB,
                                               const CvPoint2D32f * featuresA,
                                               CvPoint2D32f * featuresB,
                                               int count, CvSize winSize, int level,
                                               char *status, float *error,
                                               CvTermCriteria criteria, int flags)
{
    cv::AutoBuffer<uchar> pyrBuffer;
    cv::AutoBuffer<uchar> buffer;
    cv::AutoBuffer<char> _status;
    
    const int MAX_ITERS = 100;
    
    CvMat stubA, *imgA = (CvMat*)arrA;
    CvMat stubB, *imgB = (CvMat*)arrB;
    CvMat pstubA, *pyrA = (CvMat*)pyrarrA;
    CvMat pstubB, *pyrB = (CvMat*)pyrarrB;
    CvSize imgSize;
    
    uchar **imgI = 0;
    uchar **imgJ = 0;
    int *step = 0;
    double *scale = 0;
    CvSize* size = 0;
    
    int i, l;
    
    imgA = cvGetMat( imgA, &stubA );
    imgB = cvGetMat( imgB, &stubB );
    
    if( CV_MAT_TYPE( imgA->type ) != CV_8UC1 )
        CV_Error( CV_StsUnsupportedFormat, "" );
    
    if( !CV_ARE_TYPES_EQ( imgA, imgB ))
        CV_Error( CV_StsUnmatchedFormats, "" );
    
    if( !CV_ARE_SIZES_EQ( imgA, imgB ))
        CV_Error( CV_StsUnmatchedSizes, "" );
    
    if( imgA->step != imgB->step )
        CV_Error( CV_StsUnmatchedSizes, "imgA and imgB must have equal steps" );
    
    imgSize = cvGetMatSize( imgA );
    
    if( pyrA )
    {
        pyrA = cvGetMat( pyrA, &pstubA );
        
        if( pyrA->step*pyrA->height < icvMinimalPyramidSize( imgSize ) )
            CV_Error( CV_StsBadArg, "pyramid A has insufficient size" );
    }
    else
    {
        pyrA = &pstubA;
        pyrA->data.ptr = 0;
    }
    
    if( pyrB )
    {
        pyrB = cvGetMat( pyrB, &pstubB );
        
        if( pyrB->step*pyrB->height < icvMinimalPyramidSize( imgSize ) )
            CV_Error( CV_StsBadArg, "pyramid B has insufficient size" );
    }
    else
    {
        pyrB = &pstubB;
        pyrB->data.ptr = 0;
    }
    
    if( count == 0 )
        return;
    
    if( !featuresA || !featuresB )
        CV_Error( CV_StsNullPtr, "Some of arrays of point coordinates are missing" );
    
    if( count < 0 )
        CV_Error( CV_StsOutOfRange, "The number of tracked points is negative or zero" );
    
    if( winSize.width <= 1 || winSize.height <= 1 )
        CV_Error( CV_StsBadSize, "Invalid search window size" );
    
    icvInitPyramidalAlgorithm( imgA, imgB, pyrA, pyrB,
                              level, &criteria, MAX_ITERS, flags,
                              &imgI, &imgJ, &step, &size, &scale, &pyrBuffer );
    
    if( !status )
    {
        _status.allocate(count);
        status = _status;
    }
    
    memset( status, 1, count );
    if( error )
        memset( error, 0, count*sizeof(error[0]) );
    
    if( !(flags & CV_LKFLOW_INITIAL_GUESSES) )
        memcpy( featuresB, featuresA, count*sizeof(featuresA[0]));
    
    for( i = 0; i < count; i++ )
    {
        featuresB[i].x = (float)(featuresB[i].x * scale[level] * 0.5);
        featuresB[i].y = (float)(featuresB[i].y * scale[level] * 0.5);
    }
    
    /* do processing from top pyramid level (smallest image)
     to the bottom (original image) */
    for( l = level; l >= 0; l-- )
    {
        CvMat imgI_l, imgJ_l;        
        cvInitMatHeader(&imgI_l, size[l].height, size[l].width, imgA->type, imgI[l], step[l]);
        cvInitMatHeader(&imgJ_l, size[l].height, size[l].width, imgB->type, imgJ[l], step[l]);
        
        cv::parallel_for(cv::BlockedRange(0, count),
                         cv::LKTrackerInvoker(&imgI_l, &imgJ_l, featuresA,
                                              featuresB, status, error,
                                              criteria, winSize, l, flags));
    } // end of pyramid levels loop (l)
}
