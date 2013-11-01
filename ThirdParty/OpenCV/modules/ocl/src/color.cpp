/*M///////////////////////////////////////////////////////////////////////////////////////
//
//  IMPORTANT: READ BEFORE DOWNLOADING, COPYING, INSTALLING OR USING.
//
//  By downloading, copying, installing or using the software you agree to this license.
//  If you do not agree to this license, do not download, install,
//  copy or use the software.
//
//
//                           License Agreement
//                For Open Source Computer Vision Library
//
// Copyright (C) 2010-2012, Institute Of Software Chinese Academy Of Science, all rights reserved.
// Copyright (C) 2010-2012, Advanced Micro Devices, Inc., all rights reserved.
// Third party copyrights are property of their respective owners.
//
// @Authors
//    Wang Weiyan, wangweiyanster@gmail.com
//    Peng Xiao, pengxiao@multicorewareinc.com
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//   * Redistribution's of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//   * Redistribution's in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other oclMaterials provided with the distribution.
//
//   * The name of the copyright holders may not be used to endorse or promote products
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

using namespace cv;
using namespace cv::ocl;

#ifndef CV_DESCALE
#define CV_DESCALE(x, n) (((x) + (1 << ((n)-1))) >> (n))
#endif

#ifndef FLT_EPSILON
#define FLT_EPSILON     1.192092896e-07F
#endif

namespace cv
{
namespace ocl
{
extern const char *cvt_color;
}
}

namespace
{
void RGB2Gray_caller(const oclMat &src, oclMat &dst, int bidx)
{
    vector<pair<size_t , const void *> > args;
    int channels = src.oclchannels();
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&channels));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&bidx));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {src.cols, src.rows, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "RGB2Gray", gt, lt, args, -1, -1, build_options);
}
void Gray2RGB_caller(const oclMat &src, oclMat &dst)
{
    vector<pair<size_t , const void *> > args;
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {src.cols, src.rows, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "Gray2RGB", gt, lt, args, -1, -1, build_options);
}
void RGB2YUV_caller(const oclMat &src, oclMat &dst, int bidx)
{
    vector<pair<size_t , const void *> > args;
    int channels = src.oclchannels();
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&channels));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&bidx));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {src.cols, src.rows, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "RGB2YUV", gt, lt, args, -1, -1, build_options);
}
void YUV2RGB_caller(const oclMat &src, oclMat &dst, int bidx)
{
    vector<pair<size_t , const void *> > args;
    int channels = src.oclchannels();
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&channels));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&bidx));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {src.cols, src.rows, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "YUV2RGB", gt, lt, args, -1, -1, build_options);
}
void YUV2RGB_NV12_caller(const oclMat &src, oclMat &dst, int bidx)
{
    vector<pair<size_t , const void *> > args;
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&bidx));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.rows));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {dst.cols / 2, dst.rows / 2, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "YUV2RGBA_NV12", gt, lt, args, -1, -1, build_options);
}
void RGB2YCrCb_caller(const oclMat &src, oclMat &dst, int bidx)
{
    vector<pair<size_t , const void *> > args;
    int channels = src.oclchannels();
    char build_options[50];
    sprintf(build_options, "-D DEPTH_%d", src.depth());
    //printf("depth:%d,channels:%d,bidx:%d\n",src.depth(),src.oclchannels(),bidx);
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.cols));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.rows));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&src.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&dst.step));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&channels));
    args.push_back( make_pair( sizeof(cl_int) , (void *)&bidx));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&src.data));
    args.push_back( make_pair( sizeof(cl_mem) , (void *)&dst.data));
    size_t gt[3] = {src.cols, src.rows, 1}, lt[3] = {16, 16, 1};
    openCLExecuteKernel(src.clCxt, &cvt_color, "RGB2YCrCb", gt, lt, args, -1, -1, build_options);
}
void cvtColor_caller(const oclMat &src, oclMat &dst, int code, int dcn)
{
    Size sz = src.size();
    int scn = src.oclchannels(), depth = src.depth(), bidx;

    CV_Assert(depth == CV_8U || depth == CV_16U || depth == CV_32F);

    switch (code)
    {
        /*
        case CV_BGR2BGRA: case CV_RGB2BGRA: case CV_BGRA2BGR:
        case CV_RGBA2BGR: case CV_RGB2BGR: case CV_BGRA2RGBA:
        case CV_BGR2BGR565: case CV_BGR2BGR555: case CV_RGB2BGR565: case CV_RGB2BGR555:
        case CV_BGRA2BGR565: case CV_BGRA2BGR555: case CV_RGBA2BGR565: case CV_RGBA2BGR555:
        case CV_BGR5652BGR: case CV_BGR5552BGR: case CV_BGR5652RGB: case CV_BGR5552RGB:
        case CV_BGR5652BGRA: case CV_BGR5552BGRA: case CV_BGR5652RGBA: case CV_BGR5552RGBA:
        */
    case CV_BGR2GRAY:
    case CV_BGRA2GRAY:
    case CV_RGB2GRAY:
    case CV_RGBA2GRAY:
    {
        CV_Assert(scn == 3 || scn == 4);
        bidx = code == CV_BGR2GRAY || code == CV_BGRA2GRAY ? 0 : 2;
        dst.create(sz, CV_MAKETYPE(depth, 1));
        RGB2Gray_caller(src, dst, bidx);
        break;
    }
    case CV_GRAY2BGR:
    case CV_GRAY2BGRA:
    {
        CV_Assert(scn == 1);
        dcn  = code == CV_GRAY2BGRA ? 4 : 3;
        dst.create(sz, CV_MAKETYPE(depth, dcn));
        Gray2RGB_caller(src, dst);
        break;
    }
    case CV_BGR2YUV:
    case CV_RGB2YUV:
    {
        CV_Assert(scn == 3 || scn == 4);
        bidx = code == CV_BGR2YUV ? 0 : 2;
        dst.create(sz, CV_MAKETYPE(depth, 3));
        RGB2YUV_caller(src, dst, bidx);
        break;
    }
    case CV_YUV2BGR:
    case CV_YUV2RGB:
    {
        CV_Assert(scn == 3 || scn == 4);
        bidx = code == CV_YUV2BGR ? 0 : 2;
        dst.create(sz, CV_MAKETYPE(depth, 3));
        YUV2RGB_caller(src, dst, bidx);
        break;
    }
    case CV_YUV2RGB_NV12:
    case CV_YUV2BGR_NV12:
    case CV_YUV2RGBA_NV12:
    case CV_YUV2BGRA_NV12:
    {
        CV_Assert(scn == 1);
        CV_Assert( sz.width % 2 == 0 && sz.height % 3 == 0 && depth == CV_8U );
        dcn  = code == CV_YUV2BGRA_NV12 || code == CV_YUV2RGBA_NV12 ? 4 : 3;
        bidx = code == CV_YUV2BGRA_NV12 || code == CV_YUV2BGR_NV12 ? 0 : 2;

        Size dstSz(sz.width, sz.height * 2 / 3);
        dst.create(dstSz, CV_MAKETYPE(depth, dcn));
        YUV2RGB_NV12_caller(src, dst, bidx);
        break;
    }
    case CV_BGR2YCrCb:
    case CV_RGB2YCrCb:
    {
        CV_Assert(scn == 3 || scn == 4);
        bidx = code == CV_BGR2YCrCb ? 0 : 2;
        dst.create(sz, CV_MAKETYPE(depth, 3));
        RGB2YCrCb_caller(src, dst, bidx);
        break;
    }
    case CV_YCrCb2BGR:
    case CV_YCrCb2RGB:
    {
        break;
    }
    /*
    case CV_BGR5652GRAY: case CV_BGR5552GRAY:
    case CV_GRAY2BGR565: case CV_GRAY2BGR555:
    case CV_BGR2YCrCb: case CV_RGB2YCrCb:
    case CV_BGR2XYZ: case CV_RGB2XYZ:
    case CV_XYZ2BGR: case CV_XYZ2RGB:
    case CV_BGR2HSV: case CV_RGB2HSV: case CV_BGR2HSV_FULL: case CV_RGB2HSV_FULL:
    case CV_BGR2HLS: case CV_RGB2HLS: case CV_BGR2HLS_FULL: case CV_RGB2HLS_FULL:
    case CV_HSV2BGR: case CV_HSV2RGB: case CV_HSV2BGR_FULL: case CV_HSV2RGB_FULL:
    case CV_HLS2BGR: case CV_HLS2RGB: case CV_HLS2BGR_FULL: case CV_HLS2RGB_FULL:
    */
    default:
        CV_Error( CV_StsBadFlag, "Unknown/unsupported color conversion code" );
    }
}
}

void cv::ocl::cvtColor(const oclMat &src, oclMat &dst, int code, int dcn)
{
    cvtColor_caller(src, dst, code, dcn);
}
