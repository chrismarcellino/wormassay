#ifndef __SEGMENT_H
#define __SEGMENT_H

typedef struct bound
{
  int bx,by;
  float bJ;
} BOUND;

#endif

#define TN 6

int segment(unsigned char *rmap,unsigned char *cmap,int N,int nt,int ny,int nx,
    unsigned char *RGB,char *outfname,char *exten,int type,int dim,int NSCALEi,
    float displayintensity,int verbose,int tt);
int segment2(unsigned char *rmap0,short *rmap,int i,unsigned char *cmap,int N,int nt,
    int ny,int nx,int tt,int oldTR,float *MINRSIZE,int *offset,int *step,int verbose);
int segment1(unsigned char *cmap,int N,int nt,int ny,int nx,int *offset,int *step,
    short *rmap,unsigned char *rmap0,int oldTR,int i,float MINRSIZE,int redo,int tt);
int track(short *rmap,float *J0,float *JT0,int nt,int ny,int nx,float **threshJ1,
    float MINRSIZE,unsigned char *rmap00,int n2bgrow,int tt,float **threshJ2,
    int oldTR);
int track1(int **tracklen,int TR,int TR2,int imgsize,short *rmap1,short *rmap2,
    float *JT,unsigned char *rmap0,int *convert,int *TR1,int *newTR);
void tempofilt(unsigned char *rmap,int nt,int ny,int nx,int N,unsigned char *cmap,
    int *offset,int *step);
int merge(unsigned char *rmap,unsigned char *cmap,int N,int nt,int ny,int nx,int TR,
    float threshcolor,int threshtr);
int merge1(unsigned char *rmap,unsigned char *cmap,int N,int nt,int ny,int nx,int TR,
    float threshcolor);

int getrmap3(short *rmap,float *J,int ny,int nx,float *threshJ1,int TR,float RSIZE,
    unsigned char *rmap0,int n2bgrow,float *threshJ2,int oldTR,int *appear);
int getrmap1(short *rmap,float *J,int ny,int nx,float *threshJ,int TR,float RSIZE,
    unsigned char *rmap0,int n2bgrow);
int rmapgrow1(short *rmap,int *ky,int *kx,int i,int j,int ny,int nx,float *J,
    float threshJ,unsigned char *rmap0,int imgsize,int *kl);
void removehole(short *rmap11,int nt,int ny,int nx,unsigned char *rmap00);
void checkneigh(short rmap2,short rmap2n,int *neigh,int *neighn);
int getrmap2(short *rmap1,float *J0,int nt,int ny,int nx,int TR,int oldTR,
    unsigned char *rmap00,int **done);
int rmapgrow2(short *rmap2,int *ky,int *kx,int j,int ny,int nx,unsigned char *rmap0,
    int *kl);
void flood(short *rmap1,float *J0,int nt,int ny,int nx,unsigned char *rmap00,
    int oldTR,int **done);
void getneigh(short *neigh,float *J,int ny,int nx,int iy,int ix,short *rmap,
    unsigned char *rmap0,int loc);


void getJ(unsigned char *cmap,int N,int ny,int nx,float *J,int offset,int step,
    short *rmap,unsigned char *rmap0,int TR);
int getthreshJ(int datasize,float *J,short *rmap,unsigned char *rmap0,
    float *threshJ1,float *threshJ2,int TR,int status,int *done);
void showJ(float *J0,float **threshJ1,float **threshJ2,unsigned char *rmap00,
    int nt,int ny,int nx);
void getJT(unsigned char *cmap,int N,int ny,int nx,float *JT,int offset,int step,
    short *rmap,unsigned char *rmap0,int TR);
float gettotalJS(unsigned char *cmap,int N,int ny,int nx,unsigned char *rmap,int TR,
    float *totalJ,float **mapmatrix,int oldTR);
float gettotalJC(float *B,unsigned char *cmap,int N,float **cb,int dim,int npt,
    float ST);

