#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <math.h>
#include "mathutil.h"
#include "imgutil.h"
#include "memutil.h"
#include "ioutil.h"
#include "segment.h"


int getrmap3(short *rmap,float *J,int ny,int nx,float *threshJ1,int TR,float RSIZE,
    unsigned char *rmap0,int n2bgrow,float *threshJ2,int oldTR,int *appear)
{
  float *threshJ3;
  short *rmap1[TN];
  int j,k,l,TR2[TN],index[TN],imgsize;

  imgsize = ny*nx;
  threshJ3=(float *)calloc(oldTR+1,sizeof(float));
  for (k=0;k<TN;k++) rmap1[k]=(short *)calloc(imgsize,sizeof(short));

  for (j=1;j<=oldTR;j++) appear[j]=0;
  for (l=0;l<imgsize;l++) { if (rmap[l]==n2bgrow) appear[rmap0[l]]=1; }
  for (j=1;j<=oldTR;j++)
  {
    if (appear[j])
    {
      for (k=0;k<TN;k++) TR2[k]=0;
      for (k=0;k<TN;k++)
      {
        threshJ3[j]=threshJ1[j]-(k-2)*0.2*threshJ2[j];
        for (l=0;l<imgsize;l++) 
        {
          if (rmap0[l]==j) rmap1[k][l]=rmap[l];
          else rmap1[k][l]=-4;
        }
        TR2[k]=getrmap1(rmap1[k],J,ny,nx,threshJ3,TR,RSIZE,rmap0,n2bgrow);
      }
      piksrtint(TN,TR2,index);
      if (TR2[0]>TR) 
      {
        for (l=0;l<imgsize;l++) 
        {
          if (rmap0[l]==j) rmap[l]=rmap1[index[0]][l];
        }
        TR = TR2[0];
      }
      else 
      {
        TR++;
        for (l=0;l<imgsize;l++)
        {
          if (rmap0[l]==j && rmap[l]==n2bgrow) rmap[l]=TR;
        }
      }
    }
  }
  for (k=0;k<TN;k++) free(rmap1[k]);
  free(threshJ3);
  return TR;
}

int getrmap2(short *rmap1,float *J0,int nt,int ny,int nx,int TR,int oldTR,
    unsigned char *rmap00,int **done)
{
  int it,iy,ix,*neigh,*neighn,newTR,loc,loc1,l,imgsize,alldone,alldone2;
  unsigned char *rmap0;
  short *rmap;
  float *J,*threshJ1,*threshJ2;

  threshJ1=(float *)calloc(oldTR+1,sizeof(float));
  threshJ2=(float *)calloc(oldTR+1,sizeof(float));

  rmap0 = rmap00; rmap = rmap1; J = J0;
  imgsize=ny*nx;
  alldone = 0;
  for (it=0;it<nt;it++)
  {
    alldone2=getthreshJ(imgsize,J,rmap,rmap0,threshJ1,threshJ2,oldTR,1,done[it]);
    alldone += alldone2;
    if (alldone2==oldTR) 
    {
      rmap += imgsize; rmap0 += imgsize; J += imgsize;
      continue;
    }

    newTR=getrmap1(rmap,J,ny,nx,threshJ1,TR,0,rmap0,0);

    neighn=(int *)calloc(newTR+1,sizeof(int));
    neigh=(int *)calloc(newTR+1,sizeof(int));
    loc=0;
    for (iy=0;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        if (rmap[loc]>TR)
        {
          if (iy-1>=0) 
          {
            loc1 = loc-nx;
            if (rmap[loc]!=rmap[loc1] && rmap0[loc]==rmap0[loc1]) 
              checkneigh(rmap[loc],rmap[loc1],neigh,neighn);
          }
          if (ix-1>=0) 
          {
            loc1 = loc-1;
            if (rmap[loc]!=rmap[loc1] && rmap0[loc]==rmap0[loc1])  
              checkneigh(rmap[loc],rmap[loc1],neigh,neighn);
          }
          if (ix+1<nx)
          {
            loc1 = loc+1;
            if (rmap[loc]!=rmap[loc1] && rmap0[loc]==rmap0[loc1])
              checkneigh(rmap[loc],rmap[loc1],neigh,neighn);
          }
          if (iy+1<ny) 
          {
            loc1 = loc+nx;
            if (rmap[loc]!=rmap[loc1] && rmap0[loc]==rmap0[loc1])
              checkneigh(rmap[loc],rmap[loc1],neigh,neighn);
          }
        }
        loc++;
      }
    }
    for (l=0;l<imgsize;l++)
    {
      if (rmap[l]>TR)
      {
        if (neighn[rmap[l]]==1) rmap[l]=neigh[rmap[l]];
        else rmap[l]=0;
      }
    }
    free(neigh);
    free(neighn);

    rmap += imgsize; rmap0 += imgsize; J += imgsize;
  }
  free(threshJ1); free(threshJ2);
  return alldone;
}

void flood(short *rmap1,float *J0,int nt,int ny,int nx,unsigned char *rmap00,
    int oldTR,int **done)
{
  int it,iy,ix,*x,*y,M,M0,*index,i,j,k,l,imgsize,loc,loc1;
  float *buf,*J;
  BOUND *bd;
  short *neigh,*rmap;
  unsigned char *rmap0;

  rmap = rmap1; rmap0 = rmap00; J = J0;
  imgsize = ny*nx;
  neigh=(short *)calloc(imgsize,sizeof(short));
  for (it=0;it<nt;it++)
  {
    M0=0;
    for (l=0;l<imgsize;l++) 
    { 
      neigh[l] = 0;
      if (rmap[l]==0) M0++; 
    }

    for (k=1;k<=oldTR;k++)
    {
      if (done[it][k]) continue;
      buf = (float *)calloc(M0,sizeof(float));
      x = (int *)calloc(M0,sizeof(int));
      y = (int *)calloc(M0,sizeof(int));
      M=0; loc=0;
      for (iy=0;iy<ny;iy++)
      {
        for (ix=0;ix<nx;ix++)
        {
          if (rmap0[loc]==k)
          {
            if (rmap[loc]==0) 
            {
              getneigh(neigh,J,ny,nx,iy,ix,rmap,rmap0,loc);
              if (neigh[loc]>0)
              {
                buf[M]=J[loc]; y[M]=iy; x[M]=ix; M++;
              }
            }
            else neigh[loc]=rmap[loc];
          }
          loc ++;
        }
      }
      index = (int *)calloc(M,sizeof(int));
      piksrtS2B(M,buf,index);

      bd = (BOUND *)calloc(M0,sizeof(BOUND));
      for (i=0;i<M;i++)
      {
        bd[i].bJ=buf[i]; bd[i].by=y[index[i]]; bd[i].bx=x[index[i]];
      }
      free(index);
      free(buf); free(x); free(y); 

      while (M>0)
      {
        iy=bd[0].by; ix=bd[0].bx;
        loc = LOC2(iy,ix,nx);
        rmap[loc]=neigh[loc];
        for (i=1;i<M;i++) bd[i-1]=bd[i];
        M--;
        if (iy-1>=0) 
        {
          loc1 = loc-nx;
          if (neigh[loc1]==0 && rmap0[loc]==rmap0[loc1])
          {
            neigh[loc1]=rmap[loc]; 
            for (i=0;i<M;i++) { if (bd[i].bJ>J[loc1]) break; }  
            for (j=M-1;j>=i;j--) bd[j+1]=bd[j];
            bd[i].bJ=J[loc1]; bd[i].by=iy-1; bd[i].bx=ix; M++;
          }
        }
        if (ix-1>=0) 
        {
          loc1 = loc-1;
          if (neigh[loc1]==0 && rmap0[loc]==rmap0[loc1])
          {
            neigh[loc1]=rmap[loc];
            for (i=0;i<M;i++) { if (bd[i].bJ>J[loc1]) break; } 
            for (j=M-1;j>=i;j--) bd[j+1]=bd[j];
            bd[i].bJ=J[loc1]; bd[i].by=iy; bd[i].bx=ix-1; M++;
          }
        }
        if (ix+1<nx)
        {
          loc1 = loc+1;
          if (neigh[loc1]==0 && rmap0[loc]==rmap0[loc1])
          {
            neigh[loc1]=rmap[loc];
            for (i=0;i<M;i++) { if (bd[i].bJ>J[loc1]) break; }
            for (j=M-1;j>=i;j--) bd[j+1]=bd[j];
            bd[i].bJ=J[loc1]; bd[i].by=iy; bd[i].bx=ix+1; M++;
          }
        }
        if (iy+1<ny) 
        {
          loc1 = loc+nx;
          if (neigh[loc1]==0 && rmap0[loc]==rmap0[loc1])
          {
            neigh[loc1]=rmap[loc];
            for (i=0;i<M;i++) { if (bd[i].bJ>J[loc1]) break; } 
            for (j=M-1;j>=i;j--) bd[j+1]=bd[j];
            bd[i].bJ=J[loc1]; bd[i].by=iy+1; bd[i].bx=ix; M++;
          }
        }
      }
      free(bd);
    }
    rmap += imgsize; rmap0 += imgsize; J += imgsize;
  }
  free(neigh);
}

void getneigh(short *neigh,float *J,int ny,int nx,int iy,int ix,short *rmap,
    unsigned char *rmap0,int loc)
{
  float diff,neighJ=100.0;
  int loc1;

  if (iy-1>=0)
  {
    loc1 = loc-nx;
    if (rmap[loc1]>0 && rmap0[loc]==rmap0[loc1])
    {
      if (neigh[loc]>0)
      {
        diff = fabs(J[loc]-J[loc1]);
        if (diff<neighJ)
        {
          neighJ=diff;
          if (neigh[loc]!=rmap[loc1]) neigh[loc]=rmap[loc1];
        }
      }
      else
      {
        neigh[loc]=rmap[loc1];
        neighJ=fabs(J[loc]-J[loc1]);
      }
    }
  }
  if (ix-1>=0)
  {
    loc1 = loc-1;
    if (rmap[loc1]>0 && rmap0[loc]==rmap0[loc1])
    {
      if (neigh[loc]>0)
      {
        diff = fabs(J[loc]-J[loc1]);
        if (diff<neighJ)
        {
          neighJ=diff;
          if (neigh[loc]!=rmap[loc1]) neigh[loc]=rmap[loc1];
        }
      }
      else
      {
        neigh[loc]=rmap[loc1];
        neighJ=fabs(J[loc]-J[loc1]);
      }
    }
  }
  if (ix+1<nx)
  {
    loc1 = loc+1;
    if (rmap[loc1]>0 && rmap0[loc]==rmap0[loc1])
    {
      if (neigh[loc]>0)
      {
        diff = fabs(J[loc]-J[loc1]);
        if (diff<neighJ)
        {
          if (neigh[loc]!=rmap[loc1]) neigh[loc]=rmap[loc1];
        }
      }
      else 
      {
        neigh[loc]=rmap[loc1];
        neighJ=fabs(J[loc]-J[loc1]);
      }
    }
  }
  if (iy+1<ny)
  {
    loc1 = loc+nx;
    if (rmap[loc1]>0 && rmap0[loc]==rmap0[loc1])
    {
      if (neigh[loc]>0)
      {
        diff = fabs(J[loc]-J[loc1]);
        if (diff<neighJ)
        {
          if (neigh[loc]!=rmap[loc1]) neigh[loc]=rmap[loc1];
        }
      }
      else
      {
        neigh[loc]=rmap[loc1];
      }
    }
  }
}

void removehole(short *rmap11,int nt,int ny,int nx,unsigned char *rmap00)
{
  int jj,it,iy,ix,*neigh,*neighn,imgsize,l,loc,loc1,jy,jx,grow,grow1,ky,kx,kl;
  short *rmap2,*rmap1;
  unsigned char *rmap0;

  imgsize = ny*nx;
  rmap2=(short *)calloc(imgsize,sizeof(short));
  rmap1 = rmap11; rmap0 = rmap00;
  for (it=0;it<nt;it++)
  {
    for (l=0;l<imgsize;l++)
    {
      if (rmap1[l]==0) rmap2[l]=-1;
      else rmap2[l]=0;
    }
    jj=0;
    loc = 0;
    for (iy=0;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        if (rmap2[loc]==-1)
        {
          jj++;
          rmap2[loc] = -100;
          grow = 0;
          ky=iy; kx=ix; kl=loc;
          do 
          {
            grow1 = rmapgrow2(rmap2,&ky,&kx,jj,ny,nx,rmap0,&kl);
            grow += grow1;
          } while (grow1);
          while(grow)
          {
            grow = 0;
            loc1 = loc;
            jy=iy;
            for (jx=ix+1;jx<nx;jx++)
            {
              loc1 ++;
              if (rmap2[loc1] == -100)
              {
                ky=jy; kx=jx; kl=loc1;
                do 
                {
                  grow1 = rmapgrow2(rmap2,&ky,&kx,jj,ny,nx,rmap0,&kl);
                  grow += grow1;
                } while (grow1);
              }
            }
            for (jy=iy+1;jy<ny;jy++)
            {
              for (jx=0;jx<nx;jx++) 
              {
                loc1 ++;
                if (rmap2[loc1] == -100)
                {
                  ky=jy; kx=jx; kl=loc1;
                  do 
                  {
                    grow1 = rmapgrow2(rmap2,&ky,&kx,jj,ny,nx,rmap0,&kl);
                    grow += grow1;
                  } while (grow1);
                }
              }
            }
          }
        }
        loc ++;
      }
    }

    neighn=(int *)calloc(jj+1,sizeof(int));
    neigh=(int *)calloc(jj+1,sizeof(int));

    loc = 0;
    for (iy=0;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        if (rmap2[loc]>0)
        {
          if (iy-1>=0) 
          {
            loc1 = loc-nx;
            if (rmap0[loc]==rmap0[loc1])
              checkneigh(rmap2[loc],rmap1[loc1],neigh,neighn);
          } 
          if (ix-1>=0) 
          {
            loc1 = loc-1;
            if (rmap0[loc]==rmap0[loc1]) 
              checkneigh(rmap2[loc],rmap1[loc1],neigh,neighn);
          }
          if (ix+1<nx)
          {
            loc1 = loc+1;
            if (rmap0[loc]==rmap0[loc1])
              checkneigh(rmap2[loc],rmap1[loc1],neigh,neighn);
          }
          if (iy+1<ny) 
          {
            loc1 = loc+nx;
            if (rmap0[loc]==rmap0[loc1])
              checkneigh(rmap2[loc],rmap1[loc1],neigh,neighn);
          }
        }
        loc ++;
      }
    }
    for (l=0;l<imgsize;l++)
    {
      if (rmap2[l]>0)
      {
        if (neighn[rmap2[l]]==1) rmap1[l]=neigh[rmap2[l]];
      }
    }
    free(neigh);
    free(neighn);
    rmap1 += imgsize; rmap0 += imgsize;
  }
  free(rmap2);
}

int rmapgrow2(short *rmap,int *ky,int *kx,int j,int ny,int nx,unsigned char *rmap0,
    int *kl)
{
  int loc1,grow,iy,ix,loc;

  iy = *ky; ix = *kx; loc = *kl;
  grow = 0;
  rmap[loc]=j;
  if (iy-1>=0)
  {
    loc1 = loc-nx;
    if (rmap[loc1]==-1 && rmap0[loc]==rmap0[loc1]) 
    { 
      if (grow == 0) { *ky = iy-1; *kx = ix; *kl = loc1; grow = 1; } 
      rmap[loc1] = -100; 
    }
  }
  if (ix-1>=0)
  {
    loc1 = loc-1;
    if (rmap[loc1]==-1 && rmap0[loc]==rmap0[loc1]) 
    { 
      if (grow == 0) { *ky = iy; *kx = ix-1; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  if (ix+1<nx)
  {
    loc1 = loc+1;
    if (rmap[loc1]==-1 && rmap0[loc]==rmap0[loc1]) 
    { 
      if (grow == 0) { *ky = iy; *kx = ix+1; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  if (iy+1<ny)
  {
    loc1 = loc+nx;
    if (rmap[loc1]==-1 && rmap0[loc]==rmap0[loc1]) 
    { 
      if (grow == 0) { *ky = iy+1; *kx = ix; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  return grow;
}

void checkneigh(short rmap2,short rmap1,int *neigh,int *neighn)
{
  if (rmap1>0)
  {
    if (neighn[rmap2]==0)
    {
      neigh[rmap2]=rmap1;
      neighn[rmap2]=1;
    }
    else if (neighn[rmap2]==1)
    {
      if (rmap1!=neigh[rmap2]) neighn[rmap2]=-1;
    }
  }
}

int getrmap1(short *rmap,float *J,int ny,int nx,float *threshJ,int TR,float RSIZE,
    unsigned char *rmap0,int n2bgrow)
{
  int i,j,k,l,iy,ix,*count,*convert,newTR,loc,loc1,imgsize,grow,jy,jx;
  int grow1,ky,kx,kl;
  float threshJ1;

  imgsize = ny*nx;
  j=0; loc=0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      if (rmap[loc]==n2bgrow && J[loc]<=threshJ[rmap0[loc]])
      {
        threshJ1 = threshJ[rmap0[loc]];
        j++; 
        rmap[loc] = -100;
        grow = 0;
        ky=iy; kx=ix; kl=loc;
        do 
        {
          grow1 = rmapgrow1(rmap,&ky,&kx,n2bgrow,j+TR,ny,nx,J,threshJ1,rmap0,
              imgsize,&kl);
          grow += grow1;
        } while (grow1);
        while(grow)
        {
          grow = 0;
          loc1 = loc;
          jy=iy;
          for (jx=ix+1;jx<nx;jx++)
          {
            loc1 ++;
            if (rmap[loc1] == -100)
            {
              ky=jy; kx=jx; kl=loc1;
              do
              {
                grow1 = rmapgrow1(rmap,&ky,&kx,n2bgrow,j+TR,ny,nx,J,threshJ1,rmap0,
                    imgsize,&kl);
                grow += grow1;
              } while (grow1);
            }
          }
          for (jy=iy+1;jy<ny;jy++)
          {
            for (jx=0;jx<nx;jx++)
            {
              loc1 ++;
              if (rmap[loc1] == -100)
              {
                ky=jy; kx=jx; kl=loc1;
                do 
                {
                  grow1 = rmapgrow1(rmap,&ky,&kx,n2bgrow,j+TR,ny,nx,J,threshJ1,rmap0,
                      imgsize,&kl);
                  grow += grow1;
                } while (grow1);
              }
            }
          }
        }
      }
      loc ++;
    }
  }
  newTR=j+TR;

  if (j>0) 
  {
    count = (int *) calloc(newTR+1,sizeof(int));
    for (l=0;l<imgsize;l++)
    {
      if (rmap[l]>TR) count[rmap[l]]++;
    }
    convert=(int *)calloc(newTR+1,sizeof(int));
    for (i=1;i<=newTR;i++) convert[i]=i;
    for (i=TR+1;i<=j+TR;i++)
    {
      if (count[i]<RSIZE) 
      {
        for (k=i+1;k<=j+TR;k++) 
        {
          if (convert[k]>convert[i]) convert[k]--;
        }
        convert[i]=n2bgrow;
        newTR--;
      }
    }

    for (l=0;l<imgsize;l++)
    {
      if (rmap[l]>TR) rmap[l]=convert[rmap[l]];
    }
    free(convert);
    free(count); 
  }
  return newTR;
}

int rmapgrow1(short *rmap,int *ky,int *kx,int i,int j,int ny,int nx,float *J,
    float threshJ,unsigned char *rmap0,int imgsize,int *kl)
{
  int loc1,grow,iy,ix,loc;

  iy = *ky; ix = *kx; loc = *kl;
  grow = 0;
  rmap[loc]=j;
  if (iy-1>=0)
  {
    loc1 = loc-nx;
    if (rmap[loc1]==i && J[loc1]<=threshJ && rmap0[loc]==rmap0[loc1]) 
    {
      if (grow == 0) { *ky = iy-1; *kx = ix; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  if (ix-1>=0)
  {
    loc1 = loc-1;
    if (rmap[loc1]==i && J[loc1]<=threshJ && rmap0[loc]==rmap0[loc1]) 
    {
      if (grow == 0) { *ky = iy; *kx = ix-1; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  if (ix+1<nx)
  {
    loc1 = loc+1;
    if (rmap[loc1]==i && J[loc1]<=threshJ && rmap0[loc]==rmap0[loc1]) 
    {
      if (grow == 0) { *ky = iy; *kx = ix+1; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  if (iy+1<ny)
  {
    loc1 = loc+nx;
    if (rmap[loc1]==i && J[loc1]<=threshJ && rmap0[loc]==rmap0[loc1]) 
    {
      if (grow == 0) { *ky = iy+1; *kx = ix; *kl = loc1; grow = 1; }
      rmap[loc1] = -100; 
    }
  }
  return grow;
}

