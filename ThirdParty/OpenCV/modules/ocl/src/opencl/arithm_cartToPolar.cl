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
//    Jia Haipeng, jiahaipeng95@gmail.com
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
// This software is provided by the copyright holders and contributors as is and
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

#if defined (DOUBLE_SUPPORT)
#pragma OPENCL EXTENSION cl_khr_fp64:enable
#endif

#define CV_PI   3.1415926535897932384626433832795

#ifndef DBL_EPSILON
#define DBL_EPSILON 0x1.0p-52
#endif

__kernel void arithm_cartToPolar_D5 (__global float *src1, int src1_step, int src1_offset,
                                     __global float *src2, int src2_step, int src2_offset,
                                     __global float *dst1, int dst1_step, int dst1_offset, //magnitude
                                     __global float *dst2, int dst2_step, int dst2_offset, //cartToPolar
                                     int rows, int cols, int angInDegree)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (x < cols && y < rows)
    {
        int src1_index = mad24(y, src1_step, (x << 2) + src1_offset);
        int src2_index = mad24(y, src2_step, (x << 2) + src2_offset);

        int dst1_index = mad24(y, dst1_step, (x << 2) + dst1_offset);
        int dst2_index = mad24(y, dst2_step, (x << 2) + dst2_offset);

        float x = *((__global float *)((__global char *)src1 + src1_index));
        float y = *((__global float *)((__global char *)src2 + src2_index));

        float x2 = x * x;
        float y2 = y * y;

        float magnitude = sqrt(x2 + y2);
        float cartToPolar;

        float tmp = y >= 0 ? 0 : CV_PI*2;
        tmp = x < 0 ? CV_PI : tmp;

        float tmp1 = y >= 0 ? CV_PI*0.5 : CV_PI*1.5;
        cartToPolar = y2 <= x2 ? x*y/(x2 + 0.28f*y2 + (float)DBL_EPSILON)  + tmp :
                                 tmp1 - x*y/(y2 + 0.28f*x2 + (float)DBL_EPSILON);

        cartToPolar = angInDegree == 0 ? cartToPolar : cartToPolar * (float)(180/CV_PI);

        *((__global float *)((__global char *)dst1 + dst1_index)) = magnitude;
        *((__global float *)((__global char *)dst2 + dst2_index)) = cartToPolar;
    }
}

#if defined (DOUBLE_SUPPORT)
__kernel void arithm_cartToPolar_D6 (__global double *src1, int src1_step, int src1_offset,
                                     __global double *src2, int src2_step, int src2_offset,
                                     __global double *dst1, int dst1_step, int dst1_offset,
                                     __global double *dst2, int dst2_step, int dst2_offset,
                                     int rows, int cols, int angInDegree)
{
    int x = get_global_id(0);
    int y = get_global_id(1);

    if (x < cols && y < rows)
    {
        int src1_index = mad24(y, src1_step, (x << 3) + src1_offset);
        int src2_index = mad24(y, src2_step, (x << 3) + src2_offset);

        int dst1_index = mad24(y, dst1_step, (x << 3) + dst1_offset);
        int dst2_index = mad24(y, dst2_step, (x << 3) + dst2_offset);

        double x = *((__global double *)((__global char *)src1 + src1_index));
        double y = *((__global double *)((__global char *)src2 + src2_index));

        double x2 = x * x;
        double y2 = y * y;

        double magnitude = sqrt(x2 + y2);
        double cartToPolar;

        float tmp = y >= 0 ? 0 : CV_PI*2;
        tmp = x < 0 ? CV_PI : tmp;

        float tmp1 = y >= 0 ? CV_PI*0.5 : CV_PI*1.5;
        cartToPolar = y2 <= x2 ? x*y/(x2 + 0.28f*y2 + (float)DBL_EPSILON)  + tmp :
                                 tmp1 - x*y/(y2 + 0.28f*x2 + (float)DBL_EPSILON);

        cartToPolar = angInDegree == 0 ? cartToPolar : cartToPolar * (float)(180/CV_PI);

        *((__global double *)((__global char *)dst1 + dst1_index)) = magnitude;
        *((__global double *)((__global char *)dst2 + dst2_index)) = cartToPolar;
    }
}
#endif
