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
//    Zhang Ying, zhangying913@gmail.com
//	  Niko Li, newlife20080214@gmail.com
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//   * Redistribution's of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//
//   * Redistribution's in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other GpuMaterials provided with the distribution.
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


// resize kernel
// Currently, CV_8UC1  CV_8UC4  CV_32FC1 and CV_32FC4are supported.
// We shall support other types later if necessary.

#if defined DOUBLE_SUPPORT
#pragma OPENCL EXTENSION cl_khr_fp64:enable
#define F double
#else
#define F float
#endif


#define INTER_RESIZE_COEF_BITS 11
#define INTER_RESIZE_COEF_SCALE (1 << INTER_RESIZE_COEF_BITS)
#define CAST_BITS (INTER_RESIZE_COEF_BITS << 1)
#define CAST_SCALE (1.0f/(1<<CAST_BITS))
#define INC(x,l) ((x+1) >= (l) ? (x):((x)+1))

__kernel void resizeLN_C1_D0(__global uchar * dst, __global uchar const * restrict src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, float ifx, float ify )
{
    int gx = get_global_id(0);
    int dy = get_global_id(1);

    float4  sx, u, xf;
    int4 x, DX;
    gx = (gx<<2) - (dstoffset_in_pixel&3);
    DX = (int4)(gx, gx+1, gx+2, gx+3);
    sx = (convert_float4(DX) + 0.5f) * ifx - 0.5f;
    xf = floor(sx);
    x = convert_int4(xf);
    u = sx - xf;
    float sy = ((dy+0.5f) * ify - 0.5f);
    int y = floor(sy);
    float v = sy - y;

    u = x < 0 ? 0 : u;
    u = (x >= src_cols) ? 0 : u;
    x = x < 0 ? 0 : x;
    x = (x >= src_cols) ? src_cols-1 : x;

    y<0 ? y=0,v=0 : y;
    y>=src_rows ? y=src_rows-1,v=0 : y;

    int4 U, U1;
    int V, V1;
    float4 utmp1, utmp2;
    float vtmp;
    float4 scale_vec = INTER_RESIZE_COEF_SCALE;
    utmp1 = u * scale_vec;
    utmp2 = scale_vec - utmp1;
    U = convert_int4(rint(utmp1));
    U1 = convert_int4(rint(utmp2));
    vtmp = v * INTER_RESIZE_COEF_SCALE;
    V = rint(vtmp);
    V1= rint(INTER_RESIZE_COEF_SCALE - vtmp);

    int y_ = INC(y,src_rows);
    int4 x_;
    x_ =  ((x+1 >= src_cols) != 0) ? x : x+1;

    int4 val1, val2, val;
    int4 sdata1, sdata2, sdata3, sdata4;

    int4 pos1 = mad24((int4)y, (int4)srcstep_in_pixel, x+(int4)srcoffset_in_pixel);
    int4 pos2 = mad24((int4)y, (int4)srcstep_in_pixel, x_+(int4)srcoffset_in_pixel);
    int4 pos3 = mad24((int4)y_, (int4)srcstep_in_pixel, x+(int4)srcoffset_in_pixel);
    int4 pos4 = mad24((int4)y_, (int4)srcstep_in_pixel, x_+(int4)srcoffset_in_pixel);

    sdata1.s0 = src[pos1.s0];
    sdata1.s1 = src[pos1.s1];
    sdata1.s2 = src[pos1.s2];
    sdata1.s3 = src[pos1.s3];

    sdata2.s0 = src[pos2.s0];
    sdata2.s1 = src[pos2.s1];
    sdata2.s2 = src[pos2.s2];
    sdata2.s3 = src[pos2.s3];

    sdata3.s0 = src[pos3.s0];
    sdata3.s1 = src[pos3.s1];
    sdata3.s2 = src[pos3.s2];
    sdata3.s3 = src[pos3.s3];

    sdata4.s0 = src[pos4.s0];
    sdata4.s1 = src[pos4.s1];
    sdata4.s2 = src[pos4.s2];
    sdata4.s3 = src[pos4.s3];

    val1 = mul24(U1 , sdata1) + mul24(U , sdata2);
    val2 = mul24(U1 , sdata3) + mul24(U , sdata4);
    val = mul24((int4)V1 , val1) + mul24((int4)V , val2);

    val = ((val + (1<<(CAST_BITS-1))) >> CAST_BITS);

    pos4 = mad24(dy, dststep_in_pixel, gx+dstoffset_in_pixel);
    pos4.y++;
    pos4.z+=2;
    pos4.w+=3;
    uchar4 uval = convert_uchar4_sat(val);
        int con = (gx >= 0 && gx+3 < dst_cols && dy >= 0 && dy < dst_rows && (dstoffset_in_pixel&3)==0);
    if(con)
    {
        *(__global uchar4*)(dst + pos4.x)=uval;
    }
    else
    {
        if(gx >= 0 && gx < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos4.x]=uval.x;
        }
        if(gx+1 >= 0 && gx+1 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos4.y]=uval.y;
        }
        if(gx+2 >= 0 && gx+2 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos4.z]=uval.z;
        }
        if(gx+3 >= 0 && gx+3 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos4.w]=uval.w;
        }
    }
}

__kernel void resizeLN_C4_D0(__global uchar4 * dst, __global uchar4 * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, float ifx, float ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);

    float sx = ((dx+0.5f) * ifx - 0.5f), sy = ((dy+0.5f) * ify - 0.5f);
    int x = floor(sx), y = floor(sy);
    float u = sx - x, v = sy - y;

    x<0 ? x=0,u=0 : x,u;
    x>=src_cols ? x=src_cols-1,u=0 : x,u;
    y<0 ? y=0,v=0 : y,v;
    y>=src_rows ? y=src_rows-1,v=0 : y,v;

    u = u * INTER_RESIZE_COEF_SCALE;
    v = v * INTER_RESIZE_COEF_SCALE;

    int U = rint(u);
    int V = rint(v);
    int U1= rint(INTER_RESIZE_COEF_SCALE - u);
    int V1= rint(INTER_RESIZE_COEF_SCALE - v);

    int y_ = INC(y,src_rows);
    int x_ = INC(x,src_cols);
    int4 srcpos;
    srcpos.x = mad24(y, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.y = mad24(y, srcstep_in_pixel, x_+srcoffset_in_pixel);
    srcpos.z = mad24(y_, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.w = mad24(y_, srcstep_in_pixel, x_+srcoffset_in_pixel);
    int4 data0 = convert_int4(src[srcpos.x]);
    int4 data1 = convert_int4(src[srcpos.y]);
    int4 data2 = convert_int4(src[srcpos.z]);
    int4 data3 = convert_int4(src[srcpos.w]);
    int4 val = mul24((int4)mul24(U1, V1) ,  data0) + mul24((int4)mul24(U, V1) ,  data1)
               +mul24((int4)mul24(U1, V) ,  data2)+mul24((int4)mul24(U, V) ,  data3);
    int dstpos = mad24(dy, dststep_in_pixel, dx+dstoffset_in_pixel);
    uchar4 uval =   convert_uchar4((val + (1<<(CAST_BITS-1)))>>CAST_BITS);
    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
         dst[dstpos] = uval;
}

__kernel void resizeLN_C1_D5(__global float * dst, __global float * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, float ifx, float ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);

    float sx = ((dx+0.5f) * ifx - 0.5f), sy = ((dy+0.5f) * ify - 0.5f);
    int x = floor(sx), y = floor(sy);
    float u = sx - x, v = sy - y;

    x<0 ? x=0,u=0 : x,u;
    x>=src_cols ? x=src_cols-1,u=0 : x,u;
    y<0 ? y=0,v=0 : y,v;
    y>=src_rows ? y=src_rows-1,v=0 : y,v;

    int y_ = INC(y,src_rows);
    int x_ = INC(x,src_cols);
    float u1 = 1.f-u;
    float v1 = 1.f-v;
    int4 srcpos;
    srcpos.x = mad24(y, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.y = mad24(y, srcstep_in_pixel, x_+srcoffset_in_pixel);
    srcpos.z = mad24(y_, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.w = mad24(y_, srcstep_in_pixel, x_+srcoffset_in_pixel);
    float data0 = src[srcpos.x];
    float data1 = src[srcpos.y];
    float data2 = src[srcpos.z];
    float data3 = src[srcpos.w];
    float val1 = u1 *  data0 +
                u  *  data1 ;
    float val2 = u1 *  data2 +
                u *  data3;
    float val = v1 * val1 + v * val2;
    int dstpos = mad24(dy, dststep_in_pixel, dx+dstoffset_in_pixel);
    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
         dst[dstpos] = val;
}

__kernel void resizeLN_C4_D5(__global float4 * dst, __global float4 * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, float ifx, float ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);

    float sx = ((dx+0.5f) * ifx - 0.5f), sy = ((dy+0.5f) * ify - 0.5f);
    int x = floor(sx), y = floor(sy);
    float u = sx - x, v = sy - y;

    x<0 ? x=0,u=0 : x;
    x>=src_cols ? x=src_cols-1,u=0 : x;
    y<0 ? y=0,v=0 : y;
    y>=src_rows ? y=src_rows-1,v=0 : y;

    int y_ = INC(y,src_rows);
    int x_ = INC(x,src_cols);
    float u1 = 1.f-u;
    float v1 = 1.f-v;
    int4 srcpos;
    srcpos.x = mad24(y, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.y = mad24(y, srcstep_in_pixel, x_+srcoffset_in_pixel);
    srcpos.z = mad24(y_, srcstep_in_pixel, x+srcoffset_in_pixel);
    srcpos.w = mad24(y_, srcstep_in_pixel, x_+srcoffset_in_pixel);
    float4 s_data1, s_data2, s_data3, s_data4;
    s_data1 = src[srcpos.x];
    s_data2 = src[srcpos.y];
    s_data3 = src[srcpos.z];
    s_data4 = src[srcpos.w];
    float4 val = u1 * v1 * s_data1 + u * v1 * s_data2
              +u1 * v *s_data3 + u * v *s_data4;
    int dstpos = mad24(dy, dststep_in_pixel, dx+dstoffset_in_pixel);

    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
         dst[dstpos] = val;
}

__kernel void resizeNN_C1_D0(__global uchar * dst, __global uchar * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, F ifx, F ify )
{
    int gx = get_global_id(0);
    int dy = get_global_id(1);

    gx = (gx<<2) - (dstoffset_in_pixel&3);
    //int4 GX = (int4)(gx, gx+1, gx+2, gx+3);

    int4 sx;
    int sy;
    F ss1 = gx*ifx;
    F ss2 = (gx+1)*ifx;
    F ss3 = (gx+2)*ifx;
    F ss4 = (gx+3)*ifx;
    F s5 = dy * ify;
    sx.s0 = min((int)floor(ss1), src_cols-1);
    sx.s1 = min((int)floor(ss2), src_cols-1);
    sx.s2 = min((int)floor(ss3), src_cols-1);
    sx.s3 = min((int)floor(ss4), src_cols-1);
    sy = min((int)floor(s5), src_rows-1);

    uchar4 val;
    int4 pos = mad24((int4)sy, (int4)srcstep_in_pixel, sx+(int4)srcoffset_in_pixel);
    val.s0 = src[pos.s0];
    val.s1 = src[pos.s1];
    val.s2 = src[pos.s2];
    val.s3 = src[pos.s3];

    //__global uchar4* d = (__global uchar4*)(dst + dstoffset_in_pixel + dy * dststep_in_pixel + gx);
    //uchar4 dVal = *d;
    pos = mad24(dy, dststep_in_pixel, gx+dstoffset_in_pixel);
    pos.y++;
    pos.z+=2;
    pos.w+=3;

        int con = (gx >= 0 && gx+3 < dst_cols && dy >= 0 && dy < dst_rows && (dstoffset_in_pixel&3)==0);
    if(con)
    {
        *(__global uchar4*)(dst + pos.x)=val;
    }
    else
    {
        if(gx >= 0 && gx < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos.x]=val.x;
        }
        if(gx+1 >= 0 && gx+1 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos.y]=val.y;
        }
        if(gx+2 >= 0 && gx+2 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos.z]=val.z;
        }
        if(gx+3 >= 0 && gx+3 < dst_cols && dy >= 0 && dy < dst_rows)
        {
            dst[pos.w]=val.w;
        }
    }
}

__kernel void resizeNN_C4_D0(__global uchar4 * dst, __global uchar4 * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, F ifx, F ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);

    F s1 = dx*ifx;
    F s2 = dy*ify;
    int sx = fmin((float)floor(s1), (float)src_cols-1);
    int sy = fmin((float)floor(s2), (float)src_rows-1);
    int dpos = mad24(dy, dststep_in_pixel, dx + dstoffset_in_pixel);
    int spos = mad24(sy, srcstep_in_pixel, sx + srcoffset_in_pixel);

    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
        dst[dpos] = src[spos];

}

__kernel void resizeNN_C1_D5(__global float * dst, __global float * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, F ifx, F ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);

    F s1 = dx*ifx;
    F s2 = dy*ify;
    int sx = fmin((float)floor(s1), (float)src_cols-1);
    int sy = fmin((float)floor(s2), (float)src_rows-1);

    int dpos = mad24(dy, dststep_in_pixel, dx + dstoffset_in_pixel);
    int spos = mad24(sy, srcstep_in_pixel, sx + srcoffset_in_pixel);
    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
        dst[dpos] = src[spos];

}

__kernel void resizeNN_C4_D5(__global float4 * dst, __global float4 * src,
                     int dstoffset_in_pixel, int srcoffset_in_pixel,int dststep_in_pixel, int srcstep_in_pixel,
                     int src_cols, int src_rows, int dst_cols, int dst_rows, F ifx, F ify )
{
    int dx = get_global_id(0);
    int dy = get_global_id(1);
    F s1 = dx*ifx;
    F s2 = dy*ify;
    int s_col = floor(s1);
    int s_row = floor(s2);
    int sx = min(s_col, src_cols-1);
    int sy = min(s_row, src_rows-1);
    int dpos = mad24(dy, dststep_in_pixel, dx + dstoffset_in_pixel);
    int spos = mad24(sy, srcstep_in_pixel, sx + srcoffset_in_pixel);

    if(dx>=0 && dx<dst_cols && dy>=0 && dy<dst_rows)
        dst[dpos] = src[spos];

}
