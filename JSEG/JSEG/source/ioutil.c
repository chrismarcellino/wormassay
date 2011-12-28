#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "ioutil.h"
#include "mathutil.h"
#include "imgutil.h"

void outputEdge(char *fname,char *exten,unsigned char *RGB0,unsigned char *rmap,
    int ny,int nx,int status,int type,int dim,float displayintensity)
{
  int iy,ix,i,j,datasize,l1,l2,mapsize;
  char outfname[200];
  unsigned char *RGB;

  mapsize = ny*nx;
  datasize = ny*nx*dim;
  RGB = (unsigned char *) malloc(datasize*sizeof(unsigned char));
  for (i=0;i<datasize;i++) RGB[i] = RGB0[i]*displayintensity;

  l1 = 0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx-1;ix++)
    {
      l2 = l1+1;
      if (rmap[l1]!=rmap[l2])
      {
        for (j=0;j<dim;j++) { RGB[dim*l1+j]=255; RGB[dim*l2+j]=255; }
      }
      l1++;
    }
    l1++;
  }
  l1 = 0;
  for (iy=0;iy<ny-1;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      l2 = l1+nx;
      if (rmap[l1]!=rmap[l2])
      {
        for (j=0;j<dim;j++) { RGB[dim*l1+j]=255; RGB[dim*l2+j]=255; }
      }
      l1++;
    }
  }

  for (i=0;i<mapsize;i++)
  {
    if (rmap[i]==0)
    {
      for (j=0;j<dim;j++) RGB[dim*i+j]=0;
    }
  }

  if (status==-1) sprintf(outfname,"%s",fname);
  else sprintf(outfname,"%s.%d.seg.%s",fname,status,exten);

  outputresult(type,outfname,RGB,ny,nx,dim);

  free(RGB);
}

void outputresult(int media_type,char *outfname,unsigned char *RGB,int ny,int nx,
    int dim)
{
  switch (media_type)
  {
    case I_PPM:
      outputimgpm(outfname,RGB,ny,nx,dim);
      break;
    default:
      printf("Unknown media type \n");
      exit (-1);
  }
}

void inputimgpm(char *fname,unsigned char **img,int *ny,int *nx)
{
  FILE *fimg;
  int c,bufsize=1000,imagesize;
  char buf[1000];

  fimg=fopen(fname,"rb");
  if (!fimg)
  {
    printf("unable to read %s\n",fname);
    exit(-1);
  }

/* get the header, lines of discription */
  fgets(buf,bufsize,fimg);
  if (buf[0] == 'P')
  {
    if (buf[1] == '5') imagesize = 1;
    else if (buf[1] == '6') imagesize = 3;
    else 
    {
      printf("input image %s, unknown type\n",fname);
      exit (-1);
    }
  }
  else
  {
    printf("input image %s, unknown type\n",fname);
    exit (-1);
  }

  c=fgetc(fimg);
  while (c=='#')
  {
    fgets(buf,bufsize,fimg); /* remarks */
    c=fgetc(fimg);
  }
  fseek(fimg,-1,SEEK_CUR);
  fscanf(fimg,"%d %d\n",nx,ny);
  fgets(buf,bufsize,fimg); /* color map info */

  imagesize = imagesize * (*ny) * (*nx);
  *img = (unsigned char *) malloc(imagesize*sizeof(unsigned char));
  fread(*img, sizeof(unsigned char), imagesize, fimg);
  fclose (fimg);
}

void outputimgpm(char *fname,unsigned char *img,int ny,int nx,int dim)
{
  FILE *fimg;

  fimg=fopen(fname,"wb");
  if (dim==3)
  {
    fprintf(fimg,"P6\n");
    fprintf(fimg,"%d %d\n",nx,ny);
    fprintf(fimg,"255\n");
  }
  else if (dim==1)
  {
    fprintf(fimg,"P5\n");
    fprintf(fimg,"%d %d\n",nx,ny);
    fprintf(fimg,"255\n");
  }
  else 
  {
    printf("output image, unknown type\n");
    exit (-1);
  }
  fwrite(img, sizeof(unsigned char), ny*nx*dim, fimg);
  fclose(fimg);
}


