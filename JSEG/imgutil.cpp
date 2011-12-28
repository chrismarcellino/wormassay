#import <math.h>
#import "mathutil.h"
#import "imgutil.h"

void extendbounduc(unsigned char *img,unsigned char *imgout,int ny,int nx,int offset,int dim)
{
  int iy,ix,i,j,sy,ey,sx,ex,nx2,jump,loc;
  unsigned char f1,f2;

  nx2 = nx+2*offset;
  sy = offset; ey = ny+offset;
  sx = offset; ex = nx+offset;
  jump = 2*offset*dim;

  i = 0;
  loc = LOC(sy,sx,0,nx2,dim);
  for (iy=sy;iy<ey;iy++)
  {
    for (ix=sx;ix<ex;ix++)
    {
      for (j=0;j<dim;j++)
        imgout[loc++]=img[i++];
    }
    loc += jump;
  }

  for (ix=sx;ix<ex;ix++)
  {
    for (j=0;j<dim;j++)
    {
      f1 = imgout[LOC(offset,ix,j,nx2,dim)];
      f2 = imgout[LOC(ny+offset-1,ix,j,nx2,dim)];
      for (iy=0;iy<offset;iy++)
      {
        imgout[LOC(offset-1-iy,ix,j,nx2,dim)]  = f1;
        imgout[LOC(ny+offset+iy,ix,j,nx2,dim)] = f2;
      }
    }
  }

  ey = ny+2*offset;
  for (iy=0;iy<ey;iy++)
  {
    for (j=0;j<dim;j++)
    {
      f1 = imgout[LOC(iy,offset,j,nx2,dim)];
      f2 = imgout[LOC(iy,nx+offset-1,j,nx2,dim)];
      for (ix=0;ix<offset;ix++)
      {
        imgout[LOC(iy,offset-1-ix,j,nx2,dim)]  = f1;
        imgout[LOC(iy,nx+offset+ix,j,nx2,dim)] = f2;
      }
    }
  }
}

void extendboundfloat(float *img,float *imgout,int ny,int nx,int offset,int dim)
{
  int iy,ix,i,j,sy,ey,sx,ex,nx2,jump,loc;
  float f1,f2;

  nx2 = nx+2*offset;
  sy = offset; ey = ny+offset; 
  sx = offset; ex = nx+offset;
  jump = 2*offset*dim;

  i = 0;
  loc = LOC(sy,sx,0,nx2,dim);
  for (iy=sy;iy<ey;iy++)
  {
    for (ix=sx;ix<ex;ix++)
    {
      for (j=0;j<dim;j++)
        imgout[loc++]=img[i++];
    }
    loc += jump;
  }

  for (ix=sx;ix<ex;ix++)
  {
    for (j=0;j<dim;j++)
    {
      f1 = imgout[LOC(offset,ix,j,nx2,dim)];
      f2 = imgout[LOC(ny+offset-1,ix,j,nx2,dim)];
      for (iy=0;iy<offset;iy++)
      {
        imgout[LOC(offset-1-iy,ix,j,nx2,dim)]  = f1;
        imgout[LOC(ny+offset+iy,ix,j,nx2,dim)] = f2;
      }
    }
  }

  ey = ny+2*offset;
  for (iy=0;iy<ey;iy++)
  {
    for (j=0;j<dim;j++)
    {
      f1 = imgout[LOC(iy,offset,j,nx2,dim)];
      f2 = imgout[LOC(iy,nx+offset-1,j,nx2,dim)];
      for (ix=0;ix<offset;ix++)
      {
        imgout[LOC(iy,offset-1-ix,j,nx2,dim)]  = f1;
        imgout[LOC(iy,nx+offset+ix,j,nx2,dim)] = f2;
      }
    }
  }
}

