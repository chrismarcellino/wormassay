#import <math.h>
#import <stdlib.h>
#import <stddef.h>
#import "mathutil.h"

void genwindow(float **window,int wsize)
{
  float a2=1.0,total=0.0;
  int iy,ix;

  for (iy=0;iy<wsize;iy++)
  {
    for (ix=0;ix<wsize;ix++)
    {
      window[iy][ix] = exp (-(sqr(iy-wsize/2)+sqr(ix-wsize/2))/(2*a2));
      total += window[iy][ix];
    }
  }
  for (iy=0;iy<wsize;iy++)
  {
    for (ix=0;ix<wsize;ix++)
    {
      window[iy][ix] = window[iy][ix]/total;
    }
  }
}

/* sort float from large to small */
void piksrt(int n, float *num, int *index)
{
  int i,j;
  int indextmp;
  float numtmp;

  for (i=0;i<n;i++) index[i]= i;
  for (j=1;j<n;j++)
  {
    numtmp=num[j];
    indextmp=index[j];
    i=j-1;
    while (i>=0 && num[i]<numtmp)
    {
      num[i+1]=num[i];
      index[i+1]=index[i];
      i--;
    }
    num[i+1]=numtmp;
    index[i+1]=indextmp;
  }
}

/* sort float from small to large */
void piksrtS2B(int n, float *num, int *index)
{
  int i,j;
  int indextmp;
  float numtmp;

  for (i=0;i<n;i++) index[i]= i;
  for (j=1;j<n;j++)
  {
    numtmp=num[j];
    indextmp=index[j];
    i=j-1;
    while (i>=0 && num[i]>numtmp)
    {
      num[i+1]=num[i];
      index[i+1]=index[i];
      i--;
    }
    num[i+1]=numtmp;
    index[i+1]=indextmp;
  }
}

/* sort int from large to small */
void piksrtint(int n, int *num, int *index)
{
  int i,j;
  int indextmp;
  int numtmp;

  for (i=0;i<n;i++) index[i]= i;
  for (j=1;j<n;j++)
  {
    numtmp=num[j];
    indextmp=index[j];
    i=j-1;
    while (i>=0 && num[i]<numtmp)
    {
      num[i+1]=num[i];
      index[i+1]=index[i];
      i--;
    }
    num[i+1]=numtmp;
    index[i+1]=indextmp;
  }
}

/* sort int from small to large */
void piksrtintS2B(int n, int *num, int *index)
{
  int i,j;
  int indextmp;
  int numtmp;

  for (i=0;i<n;i++) index[i]= i;
  for (j=1;j<n;j++)
  {
    numtmp=num[j];
    indextmp=index[j];
    i=j-1;
    while (i>=0 && num[i]>numtmp)
    {
      num[i+1]=num[i];
      index[i+1]=index[i];
      i--;
    }
    num[i+1]=numtmp;
    index[i+1]=indextmp;
  }
}

/* sort array of int from small to large */
void piksrtarray(int n, int **num, int *index,int m)
{
  int i,j,k,indextmp,*numtmp,bigger;

  numtmp=(int *)calloc(m,sizeof(int));
  for (i=0;i<n;i++) index[i]= i;
  for (j=1;j<n;j++)
  {
    for (k=0;k<m;k++) numtmp[k]=num[j][k];
    indextmp=index[j];
    i=j-1;
    bigger=0;
    if (i>=0)
    {
      for (k=0;k<m;k++)
      {
        if (num[i][k]>numtmp[k]) { bigger=1; break; }
        else if (num[i][k]<numtmp[k]) { break; }
      }
    }
    while (bigger)
    {
      for (k=0;k<m;k++) num[i+1][k]=num[i][k];
      index[i+1]=index[i];
      i--;
      bigger=0;
      if (i>=0)
      {
        for (k=0;k<m;k++)
        {
          if (num[i][k]>numtmp[k]) { bigger=1; break; }
          else if (num[i][k]<numtmp[k]) { break; }
        }
      }
    }
    for (k=0;k<m;k++) num[i+1][k]=numtmp[k];
    index[i+1]=indextmp;
  }
  free(numtmp);
}

float distance(float *a,float *b,int dim)
{
  int i;
  float dist=0.0;

  for (i=0;i<dim;i++) dist+=sqr(a[i]-b[i]);
  dist = sqrt(dist);
  return dist;
}

float distance2(float *a,float *b,int dim)
{
  int i;
  float dist=0.0;

  for (i=0;i<dim;i++) dist+=sqr(a[i]-b[i]);
  return dist;
}

int LOC(int iy,int ix,int id,int nx,int nd)
{
  return ((iy*nx+ix)*nd+id);
}

int LOC2(int iy,int ix,int nx)
{
  return (iy*nx+ix);
}

int LOC3(int it,int iy,int ix,int ny,int nx)
{
  return ((it*ny+iy)*nx+ix);
}


