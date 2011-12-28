#ifndef __IOUTIL_H
#define __IOUTIL_H

#define I_PPM  5

#define P_SEG 1
#define P_QUA 2
#define P_BW  3

void outputEdge(char *fname,char *exten,unsigned char *RGB0,unsigned char *rmap,
    int ny,int nx,int status,int type,int dim,float displayintensity);

void outputresult(int media_type,char *outfname,unsigned char *RGB,int ny,int nx,
    int dim);

void inputimgpm(char *fname,unsigned char **img,int *ny,int *nx);
void outputimgpm(char *fname,unsigned char *img,int ny,int nx,int dim);


#endif

