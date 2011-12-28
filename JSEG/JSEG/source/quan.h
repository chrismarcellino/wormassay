#ifndef __QUAN_H
#define __QUAN_H

int quantize(float *B,float **cb,int nt,int ny,int nx,int dim,float thresh);
void getcmap(float *B,unsigned char *cmap,float **cb,int npt,int dim,int N);
int mergecb(float *B,float **cb,unsigned char *P,int npt,int N,float thresh,int dim);
int mergecb1(float **dist,float *B,float **cb,unsigned char *P,int npt,int newN,
    float *thresh,int dim,int *count,int status);
int gla(float *A,int nvec,int ndim,int N,float **codebook,float t,unsigned char *P,
    float *weight);
int greedy(float *A,int nvec,int ndim,int N,float **codebook,float t,unsigned char *P,
    float *weight);
float pga(float *B,float *A,int ny,int nx,int offset,float *weight,int dim);
void pgamap(unsigned char *cmap,int ny,int nx,int offset,int N);

#endif

