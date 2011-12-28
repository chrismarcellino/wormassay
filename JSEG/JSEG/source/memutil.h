#ifndef __MEMUTIL_H
#define __MEMUTIL_H

double **dmatrix(int nr, int nc);
void free_dmatrix(double **m, int nr);
float **fmatrix(int nr, int nc);
void free_fmatrix(float **m, int nr);
int **imatrix(int nr, int nc);
void free_imatrix(int **m, int nr);
unsigned char **ucmatrix(int nr, int nc);
void free_ucmatrix(unsigned char **m, int nr);
char **cmatrix(int nr, int nc);
void free_cmatrix(char **m, int nr);

#endif

