#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "memutil.h"

double **dmatrix(int nr, int nc)
{
  int i,j;
  double **m;

  m=(double **) malloc(nr*sizeof(double *));
  if (!m) return NULL;
  for(i=0;i<nr;i++)
  {
    m[i]=(double *) malloc(nc*sizeof(double));
    if (!m[i]) return NULL;
    for (j=0;j<nc;j++) m[i][j]=0;
  }
  return m;
}

void free_dmatrix(double **m, int nr)
{
  int i;

  for (i=0;i<nr;i++) free(m[i]);
  free(m);
}

float **fmatrix(int nr, int nc)
{
  int i,j;
  float **m;

  m=(float **) malloc(nr*sizeof(float *));
  if (!m) return NULL;
  for(i=0;i<nr;i++)
  {
    m[i]=(float *) malloc(nc*sizeof(float));
    if (!m[i]) return NULL;
    for (j=0;j<nc;j++) m[i][j]=0;
  }
  return m;
}

void free_fmatrix(float **m, int nr)
{
  int i;

  for (i=0;i<nr;i++) free(m[i]);
  free(m);
}

int **imatrix(int nr, int nc)
{
  int i,j;
  int **m;

  m=(int **) malloc(nr*sizeof(int *));
  if (!m) return NULL;
  for(i=0;i<nr;i++)
  {
    m[i]=(int *) malloc(nc*sizeof(int));
    if (!m[i]) return NULL;
    for (j=0;j<nc;j++) m[i][j]=0;
  }
  return m;
}

void free_imatrix(int **m, int nr)
{
  int i;

  for (i=0;i<nr;i++) free(m[i]);
  free(m);
}

unsigned char **ucmatrix(int nr, int nc)
{
  int i,j;
  unsigned char **m;

  m=(unsigned char **) malloc(nr*sizeof(unsigned char *));
  if (!m) return NULL;
  for(i=0;i<nr;i++)
  {
    m[i]=(unsigned char *) malloc(nc*sizeof(unsigned char));
    if (!m[i]) return NULL;
    for (j=0;j<nc;j++) m[i][j]=0;
  }
  return m;
}

void free_ucmatrix(unsigned char **m, int nr)
{
  int i;

  for (i=0;i<nr;i++) free(m[i]);
  free(m);
}

char **cmatrix(int nr, int nc)
{
  int i,j;
  char **m;

  m=(char **) malloc(nr*sizeof(char *));
  if (!m) return NULL;
  for(i=0;i<nr;i++)
  {
    m[i]=(char *) malloc(nc*sizeof(char));
    if (!m[i]) return NULL;
    for (j=0;j<nc;j++) m[i][j]=0;
  }
  return m;
}

void free_cmatrix(char **m, int nr)
{
  int i;

  for (i=0;i<nr;i++) free(m[i]);
  free(m);
}


