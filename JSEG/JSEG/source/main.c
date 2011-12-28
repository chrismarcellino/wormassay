

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "segment.h"
#include "ioutil.h"
#include "imgutil.h"
#include "mathutil.h"
#include "quan.h"
#include "memutil.h"

#include <ctype.h>


float TQUAN,displayintensity,threshcolor;
int proc_type,media_type,rmap_type,NSCALE,NY,NX;
char *infname,*outfname,*rmapfname,*verbosefname;
int inimg_flag,type_flag,outimg_flag,outmap_flag,size_flag,verbose_flag;

void process_image(void);
void parse_arg(int argc, char *argv[]);

int main (int argc, char *argv[])
{
  parse_arg(argc,argv);
  if (media_type<20) process_image();
    
    return 0;
}

void process_image(void)
{
  unsigned char *RGB,*cmap,*RGB2;
  int dim,N,i,j,k,TR,imgsize,mapsize,l;
  float *LUV,**cb;
  char fname[200], exten[10];
  unsigned char *rmap;

  switch (media_type)
  {
    case I_PPM:
      sprintf(exten,"ppm");
      inputimgpm(infname,&RGB,&NY,&NX);
      dim = 3; imgsize = NY*NX*dim;
      break;
    default:
      printf("Unknown media type \n");
      exit (-1);
  }

  mapsize = NY*NX;
  switch (proc_type)
  {
    case P_SEG: case P_QUA:

      cb = (float **)fmatrix(256,dim);
      LUV = (float *) malloc(imgsize*sizeof(float));
      if (dim==3) rgb2luv(RGB,LUV,imgsize);
      else if (dim==1) { for (l=0;l<imgsize;l++) LUV[l]=RGB[l]; }
      else { printf("don't know how to handle dim=%d\n",dim); exit(0); }
      
      N=quantize(LUV,cb,1,NY,NX,dim,TQUAN);
      printf("N=%d\n",N);
      cmap = (unsigned char *) calloc(mapsize,sizeof(unsigned char));
     if (dim==3) rgb2luv(RGB,LUV,imgsize);
      else if (dim==1) { for (l=0;l<imgsize;l++) LUV[l]=RGB[l]; }
      getcmap(LUV,cmap,cb,mapsize,dim,N);
      if (verbose_flag || proc_type == P_QUA)
      {
        j=0;
        for (i=0;i<mapsize;i++) 
          for (k=0;k<dim;k++) LUV[j++] = cb[cmap[i]][k];
        RGB2 = (unsigned char *)malloc(imgsize*sizeof(unsigned char));
        if (dim==3) luv2rgb(RGB2,LUV,imgsize);
        else if (dim==1) { for (l=0;l<imgsize;l++) RGB2[l]=(unsigned char) LUV[l]; }
        sprintf(fname,"%s.qua.%s",verbosefname,exten);
        outputresult(media_type,fname,RGB2,NY,NX,dim);
        free(RGB2);
      }
      free_fmatrix(cb,256);
      free (LUV);

      if (proc_type == P_QUA) { free(cmap); free(RGB); exit(0); }

      rmap = (unsigned char *)calloc(NY*NX,sizeof(unsigned char));
      TR = segment(rmap,cmap,N,1,NY,NX,RGB,verbosefname,exten,media_type,dim,NSCALE,
          displayintensity,verbose_flag,1);
      TR = merge1(rmap,cmap,N,1,NY,NX,TR,threshcolor);
      printf("merge TR=%d\n",TR);
      free(cmap);

      if (outimg_flag)
        outputEdge(outfname,exten,RGB,rmap,NY,NX,-1,media_type,dim,displayintensity);
      if (outmap_flag)
      {
        switch(rmap_type)
        {
          default:
            printf("Unknown rmap type \n");
            exit (-1);
        }
      }
      free(RGB);
      free(rmap);

      break;

    case P_BW:
      N=2;
      cmap = (unsigned char *) calloc(mapsize,sizeof(unsigned char));
      for (i=0;i<imgsize;i++) 
      { 
        if (RGB[i]>=128) cmap[i]=1;
        else cmap[i]=0;
      }
      rmap = (unsigned char *)calloc(NY*NX,sizeof(unsigned char));
      TR = segment(rmap,cmap,N,1,NY,NX,RGB,verbosefname,exten,media_type,dim,NSCALE,
          displayintensity,verbose_flag,1);
      TR = merge1(rmap,cmap,N,1,NY,NX,TR,threshcolor);
      printf("merge TR=%d\n",TR);
      free(cmap);

      if (outimg_flag)
        outputEdge(outfname,exten,RGB,rmap,NY,NX,-1,media_type,dim,displayintensity);
      if (outmap_flag)
      {
        switch(rmap_type)
        {
          default:
            printf("Unknown rmap type \n");
            exit (-1);
        }
      }
      free(RGB);
      free(rmap);

      break;

    default:
      printf("Unknown process type \n");
      exit (-1);
  }
}

void parse_arg(int argc, char *argv[])
{
  int i, LastArg, NextArg;
  if (argc<2)
  {
    printf("\n\
Segmentation   \n\
usage: %s {arguments} {options}              \n\
\n\
arguments must be provided: \n\
-i file  input media filename     \n\
-t type input media type:        \n\
           type 1,2,3 must provide image size \n\
           1:  image yuv            \n\
           2:  image raw rgb        \n\
           3:  image raw gray       \n\
           4:  image pgm            \n\
           5:  image ppm            \n\
options: \n\
-o file factor   output image (region boundary superimposed} filename \n\
                 output image format same as input image              \n\
                 factor: dim original image to show boundaries, 0-1.0 \n\
-rn file         output region map filename, n type                   \n\
                 3: image raw gray \n\
-s height width  image height and width                               \n\
-q thresh        color quantization threshold, 0-600, default automatic  \n\
-l scale         number of scales, default automatic                     \n\
-m thresh        region merge threshold, 0-1.0, default 0.4 \n\
\n\
Example:  \n\
%s -i test.rgb -t 2 -o test.seg.rgb 0.9 -s 128 192 -r3 test.map -v test -q 255  \n\
\n",argv[0],argv[0]);
    exit(0);
  }

  inimg_flag = 0;
  type_flag = 0;
  outimg_flag = 0;
  outmap_flag = 0;
  size_flag = 0;
  verbose_flag = 0;
  TQUAN = -1; 
  NSCALE = -1;
  threshcolor = 0.4;

  i = 1;
  while (i<argc)
  {
    LastArg = ((argc-i)==1);
    if(!LastArg) NextArg = (argv[i+1][0]=='-');
    else NextArg = 0;

    /* second character, [1], after '-' is the switch */
    if (argv[i][0]=='-')
    {
      switch(toupper(argv[i][1]))
      {
        /* third character. [2], is the value */
      case 'I':

        if(NextArg || LastArg)
        {
          printf("ERROR: -i argument error \n");
          exit (-1);
        }
        else
        {
          infname = argv[++i];
          inimg_flag = 1;
        }
        break;

      case 'T':

        proc_type = 1;
        if (proc_type>0 && proc_type<=9)
        {
          if (NextArg || LastArg) 
          {
            printf("ERROR: -t argument error\n");
            exit (-1);
          }
          else 
          {
            media_type = atoi(argv[++i]);
            type_flag = 1;
          }
        }
        else 
        {
          printf("ERROR: -t argument error\n");
          exit (-1);
        }
        break;

      case 'O':

        if (NextArg || LastArg) 
        {
          printf("ERROR: -o argument error \n");
          exit (-1);
        }
        else
        {
          outfname = argv[++i];
          LastArg = ((argc-i)==1);
          if(!LastArg) NextArg = (argv[i+1][0]=='-');
          else NextArg = 0;
          if (NextArg || LastArg) 
          {
            printf("ERROR: -o argument error \n");
            exit (-1);
          }
          else 
          {
            displayintensity = atof(argv[++i]);
            outimg_flag = 1;
          }
        }
        break;

      case 'R':
 
        rmap_type = atoi(&argv[i][2]);
        if (rmap_type>0 && rmap_type<=9)
        {
          if (NextArg || LastArg) 
          {
            printf("ERROR: -r argument error \n");
            exit (-1);
          }
          else
          {
            rmapfname = argv[++i];
            outmap_flag = 1;
          }
        }
        else 
        {
          printf("ERROR: -rn argument error\n");
          exit (-1);
        }
        break;

      case 'S':

        if (NextArg || LastArg) 
        {
          printf("ERROR: -s argument error \n");
          exit (-1);
        }
        else
        {
          NY = atoi(argv[++i]);
          LastArg = ((argc-i)==1);
          if(!LastArg) NextArg = (argv[i+1][0]=='-');
          else NextArg = 0;
          if (NextArg || LastArg)
          {
            printf("ERROR: -s argument error \n");
            exit (-1);
          }
          else
          {
            NX = atoi(argv[++i]);
            size_flag = 1;
          }
        }
        break;

      case 'Q':

        if (NextArg || LastArg) 
        {
          printf("ERROR: -q argument error \n");
          exit (-1);
        }
        else TQUAN = atof(argv[++i]);
        break;

      case 'L':

        if (NextArg || LastArg)
        {
          printf("ERROR: -l argument error \n");
          exit (-1);
        }
        else NSCALE = atoi(argv[++i]);
        break;

      case 'M':

        if (NextArg || LastArg)
        {
          printf("ERROR: -m argument error \n");
          exit (-1);
        }
        else threshcolor = atof(argv[++i]);
        break;

      default:

        printf("undefined option -%c ignored. Exiting program\n", argv[i][1]);
        exit(-1);

      } /* switch() */
    } /* if argv[i][0] == '-' */

    i++;
  }

  if (inimg_flag)
    printf("input media filename: %s\n",infname);
  else 
  {
    printf("must provide input filename\n");
    exit (-1);
  }

  switch (media_type)
  {
    case I_PPM:
      printf("input media type: image ppm \n");
      break;
    default:
      printf("Unknown media type \n");
      exit (-1);
  }

  switch (proc_type)
  {
    case P_SEG:
      if (media_type>=20 && verbose_flag)
      {
        printf("no verbose for video\n");
        exit (-1);
      }
      printf("process type: segmentation \n");
      break;
    case P_QUA:
      if (!verbose_flag) 
      {
        printf("must provide -v option \n");
        exit (-1);
      }
      printf("process type: quantization only \n");
      break;
    case P_BW:
      printf("process type: b/w segmentation \n");
      break;
    default:
      printf("Unknown process type \n");
      exit (-1);
  }

  if (outimg_flag)
    printf("output image: %s %f \n",outfname,displayintensity);
  if (outmap_flag)
  {
    printf("output rmap: %s; ",rmapfname);
    switch(rmap_type)
    {
      case 1:
        printf("logic map\n");
        break;
      default:
        printf("Unknown rmap type \n");
        exit (-1);
    }
  }
  if (!outimg_flag && !outmap_flag && proc_type!=P_QUA) 
  {
    printf("must provide output \n");
    exit (-1);
  }

  if (size_flag)
    printf("image dimension: %d %d\n",NY,NX);

  if (verbose_flag)
    printf("output intermediate results, filename: %s\n",verbosefname);

  if (TQUAN>0 || TQUAN==-1) printf("color quantization threshold: %f\n",TQUAN);
  else { printf("unknown color quantization threshold: %f\n",TQUAN); exit(-1); }
  if (NSCALE==-1 || NSCALE>0) printf("number of scales: %d\n",NSCALE);
  else { printf("unknown scales:  %d\n",NSCALE); exit(-1); }
  if (media_type>=20 && threshcolor==-1) threshcolor=0.3;
  printf("region merge threshold: %f\n",threshcolor);
  printf("\n");
}


