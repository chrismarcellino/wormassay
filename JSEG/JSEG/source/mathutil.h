#ifndef __MATHUTIL_H
#define __MATHUTIL_H

#ifndef MAX
  #define MAX(x, y) (((x) > (y)) ? (x) : (y))
#endif
#ifndef MIN
  #define MIN(x, y) (((x) < (y)) ? (x) : (y))
#endif
#define sqr(x) ((x)*(x))
#define sgn(x) ((x)>0 ? 1 : -1)
#define PI 3.1415927

void genwindow(float **window,int wsize);
void piksrt(int n, float *num, int *index);
void piksrtS2B(int n, float *num, int *index);
void piksrtint(int n, int *num, int *index);
void piksrtintS2B(int n, int *num, int *index);
void piksrtarray(int n, int **num, int *index,int m);
float distance(float *a,float *b,int dim);
float distance2(float *a,float *b,int dim);
int LOC(int iy,int ix,int id,int nx,int nd);
int LOC2(int iy,int ix,int nx);
int LOC3(int it,int iy,int ix,int ny,int nx);

#endif
