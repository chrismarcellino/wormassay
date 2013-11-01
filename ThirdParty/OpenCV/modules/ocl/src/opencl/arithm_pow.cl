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
//    Jiang Liyuan, jlyuan001.good@163.com
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
typedef double F;
typedef double4 F4;
#define convert_F4 convert_double4;
#else
typedef float F;
typedef float4 F4;
#define convert_F4 convert_float4;
#endif
/************************************** pow **************************************/
__kernel void arithm_pow_D5 (__global float *src1, int src1_step, int src1_offset,
                             __global float *dst,  int dst_step,  int dst_offset,
                             int rows, int cols, int dst_step1,
                             F p)
{

    int x = get_global_id(0);
    int y = get_global_id(1);

    if(x < cols && y < rows)
    {
        int src1_index = mad24(y, src1_step, (x << 2) + src1_offset);
        int dst_index  = mad24(y, dst_step,  (x << 2) + dst_offset);

        float src1_data = *((__global float *)((__global char *)src1 + src1_index));
        float tmp = src1_data > 0 ? exp(p * log(src1_data)) : (src1_data == 0 ? 0 : exp(p * log(fabs(src1_data))));

        *((__global float *)((__global char *)dst + dst_index)) = tmp;
    }

}

#if defined (DOUBLE_SUPPORT)
__kernel void arithm_pow_D6 (__global double *src1, int src1_step, int src1_offset,
                             __global double *dst,  int dst_step,  int dst_offset,
                             int rows, int cols, int dst_step1,
                             F p)
{

    int x = get_global_id(0);
    int y = get_global_id(1);

    if(x < cols && y < rows)
    {
        int src1_index = mad24(y, src1_step, (x << 3) + src1_offset);
        int dst_index  = mad24(y, dst_step,  (x << 3) + dst_offset);

        double src1_data = *((__global double *)((__global char *)src1 + src1_index));
        double tmp = src1_data > 0 ? exp(p * log(src1_data)) : (src1_data == 0 ? 0 : exp(p * log(fabs(src1_data))));
        *((__global double *)((__global char *)dst + dst_index)) = tmp;
    }

}
#endif
