#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <math.h>
#include "mathutil.h"
#include "imgutil.h"
#include "memutil.h"
#include "ioutil.h"
#include "quan.h" 
#include "segment.h"

void getJ(unsigned char *cmap,int N,int ny,int nx,float *J,int offset,int step,
    short *rmap,unsigned char *rmap0,int TR)
{
  int iy,ix,jy,jx,i,*p,StN,StN1,corner[3];
  float St1,St,Sb,Sw,Stmeanx,Stmeany,*avgy,*avgx,*Jtmp,total,**weight;
  unsigned char *cmap1,*rmap1;
  int l,imgsize,imgsize2,ny2,nx2,loc,loc1,loc2,sy,ey,sx,ex,cornerI,cornerT[6];

  imgsize = ny*nx;
  ny2 = ny+2*offset; nx2 = nx+2*offset;
  imgsize2 = ny2*nx2;
  cmap1 = (unsigned char *) calloc (imgsize2,sizeof(unsigned char)); 
  rmap1 = (unsigned char *) calloc (imgsize2,sizeof(unsigned char));
  extendbounduc(cmap,cmap1,ny,nx,offset,1);
  extendbounduc(rmap0,rmap1,ny,nx,offset,1);
  corner[0]=0; corner[1]=step; corner[2]=3*step;

  cornerT[0]=-offset;        cornerT[1]=offset;
  cornerT[2]=-offset+step;   cornerT[3]=offset-step;
  cornerT[4]=-offset+2*step; cornerT[5]=offset-2*step;

  StN1=sqr(2*offset/step+1)-20;
  St1=0; 
  for (jy=-offset;jy<=offset;jy+=step)
  {
    if (jy==cornerT[0] || jy==cornerT[1]) cornerI = 2;
    else if (jy==cornerT[2] || jy==cornerT[3]) cornerI = 1;
    else if (jy==cornerT[4] || jy==cornerT[5]) cornerI = 1;
    else cornerI = 0;
    sx = -offset+corner[cornerI]; ex = offset-corner[cornerI];
    for (jx=sx;jx<=ex;jx+=step) St1 += sqr(jy)+sqr(jx);
  }

  for (l=0;l<imgsize;l++) J[l]=0;

  avgy=(float *)calloc(N,sizeof(float));
  avgx=(float *)calloc(N,sizeof(float));
  p=(int *)calloc(N,sizeof(int));

  loc = 0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      loc2 = LOC2(iy+offset,ix+offset,nx2);
      if (rmap[loc]==0) 
      {
        cornerT[0]=iy-offset;        cornerT[1]=iy+offset;
        cornerT[2]=iy-offset+step;   cornerT[3]=iy+offset-step;
        cornerT[4]=iy-offset+2*step; cornerT[5]=iy+offset-2*step;

        St = St1; Stmeanx=0; Stmeany=0; StN=StN1;
        for (i=0;i<N;i++) { avgy[i]=0; avgx[i]=0; p[i]=0; }
        sy = iy-offset; ey = iy+offset;
        for (jy=sy;jy<=ey;jy+=step)
        {
          if      (jy==cornerT[0] || jy==cornerT[1]) cornerI = 2;
          else if (jy==cornerT[2] || jy==cornerT[3]) cornerI = 1;
          else if (jy==cornerT[4] || jy==cornerT[5]) cornerI = 1;
          else cornerI = 0;
          sx = ix-offset+corner[cornerI]; ex = ix+offset-corner[cornerI];
          for (jx=sx;jx<=ex;jx+=step)
          {
            loc1 = LOC2(jy+offset,jx+offset,nx2);
            if (rmap1[loc1]==rmap1[loc2])
            {
              avgy[cmap1[loc1]] += jy-iy;
              avgx[cmap1[loc1]] += jx-ix;
              p[cmap1[loc1]] ++;
            }
            else
            {
              St -= (sqr(jy-iy-Stmeany) + sqr(jx-ix-Stmeanx)) *StN/(StN-1);
              Stmeany -= (jy-iy-Stmeany)/(StN-1);
              Stmeanx -= (jx-ix-Stmeanx)/(StN-1);
              StN --;
            }
          }
        }
        for (i=0;i<N;i++) 
        {
          if (p[i]>0) { avgy[i]/=p[i]; avgx[i]/=p[i]; }
        }
        Sw=0;
        sy = iy-offset; ey = iy+offset;
        for (jy=sy;jy<=ey;jy+=step)
        {
          if      (jy==cornerT[0] || jy==cornerT[1]) cornerI = 2;
          else if (jy==cornerT[2] || jy==cornerT[3]) cornerI = 1;
          else if (jy==cornerT[4] || jy==cornerT[5]) cornerI = 1;
          else cornerI= 0;
          sx = ix-offset+corner[cornerI]; ex = ix+offset-corner[cornerI];
          for (jx=sx;jx<=ex;jx+=step)
          {
            loc1 = LOC2(jy+offset,jx+offset,nx2);
            if (rmap1[loc1]==rmap1[loc2])
              Sw += sqr(jy-iy-avgy[cmap1[loc1]]) + sqr(jx-ix-avgx[cmap1[loc1]]);
          }
        }
        if (Sw==0) J[loc]=2;
        else 
        {
          Sb = St- Sw;
          if (Sb<0) Sb=0;
          J[loc] = Sb/Sw;
          if (J[loc]>2) J[loc]=2;
        }
      }
      loc ++;
    }
  }
  free(cmap1);
  free(rmap1);
  free(avgy); free(avgx); free(p);

  if (step>1)
  {
    step /=2;
    Jtmp=(float *)calloc(imgsize,sizeof(float));
    weight = (float **)fmatrix(2*step+1,2*step+1);
    genwindow(weight,2*step+1);
    for (i=0;i<2;i++)
    {
      for (l=0;l<imgsize;l++) Jtmp[l]=J[l];
      loc = 0;
      for (iy=0;iy<ny;iy++)
      {
        for (ix=0;ix<nx;ix++)
        {
          if (rmap[loc]==0)
          {
            J[loc]=0; total=0;
            for (jy=iy-step;jy<=iy+step;jy++)
            {
              for (jx=ix-step;jx<=ix+step;jx++) 
              {
                if (jy>=0 && jy<ny && jx>=0 && jx<nx)
                {
                  loc1 = LOC2(jy,jx,nx);
                  if (rmap0[loc]==rmap0[loc1]) 
                  {
                    J[loc] += weight[jy-iy+step][jx-ix+step]*Jtmp[loc1];
                    total += weight[jy-iy+step][jx-ix+step];
                  }
                }
              }
            }
            J[loc] /= total;
          }
          loc ++;
        }
      }
    }
    free(Jtmp);
    free_fmatrix(weight,2*step+1);
  }
}

int getthreshJ(int datasize,float *J,short *rmap,unsigned char *rmap0,
    float *threshJ1,float *threshJ2,int TR,int status,int *done)
{
  float *avgJ,*varJ; 
  int *count,i,l,alldone;

  count=(int *)calloc(TR+1,sizeof(int)); 
  avgJ=(float *)calloc(TR+1,sizeof(float)); 
  for (l=0;l<datasize;l++)
  {
    if (rmap[l]==0)
    {
      avgJ[rmap0[l]] += J[l]; 
      count[rmap0[l]]++;
    }
  }

  alldone = 0;
  for (i=1;i<=TR;i++)
  {
    if (count[i]>0) { avgJ[i] = avgJ[i]/count[i]; done[i]=0; }
    else done[i]=1; 
    alldone += done[i];
  }

  varJ = (float *)calloc(TR+1,sizeof(float));
  for (l=0;l<datasize;l++)
  {
    if (rmap[l]==0) varJ[rmap0[l]] += sqr(J[l]-avgJ[rmap0[l]]);
  }
  for (i=1;i<=TR;i++)
  {
    if (count[i]>0) varJ[i] = sqrt(varJ[i]/count[i]);
    if (status==0) threshJ1[i] = avgJ[i] + 0.1*varJ[i]; 
    else if (status==1) threshJ1[i] = avgJ[i] - 0.35*varJ[i];
    threshJ2[i] = varJ[i];
  }
  free(varJ);

  free(count); free(avgJ);
  return alldone;
}

void showJ(float *J0,float **threshJ1,float **threshJ2,unsigned char *rmap00,
    int nt,int ny,int nx)
{
  float *J1,*J;
  int i,imgsize,it;
  unsigned char *rmap0;
  char fname[200];

  J = J0; rmap0 = rmap00;
  imgsize = ny*nx;
  J1=(float *)calloc(imgsize,sizeof(float));
  for (it=0;it<nt;it++)
  {
    for (i=0;i<imgsize;i++) J1[i] = 1000*J[i];
    if (nt==1) sprintf(fname,"J.seg.gray");
    else sprintf(fname,"J.%d.seg.gray",it);

/*
    for (i=0;i<imgsize;i++)
    { 
      if (J[i]>(threshJ1[it][rmap0[i]]-0.8*threshJ2[it][rmap0[i]])) J1[i]=200;
      else if (J[i]==0) J1[i]=100;
    }
    if (nt==1) sprintf(fname,"J1.seg.gray");
    else sprintf(fname,"J1.%d.seg.gray",it);
    outfloat2raw(fname,J1,ny,nx,1);
*/

    J += imgsize; rmap0 += imgsize;
  }
  free(J1);
}

void getJT(unsigned char *cmap,int N,int ny,int nx,float *JT,int offset,int step,
    short *rmap,unsigned char *rmap0,int TR)
{
  int iy,ix,jy,jx,i,*p,StN1,corner[3];
  float St1,St,Sb,Sw,*avgt,*Jtmp,total,**weight;
  unsigned char *cmap1;
  int l,imgsize,imgsize2,ny2,nx2,loc,loc1,sy,ey,sx,ex,cornerI,cornerT[6];

  imgsize = ny*nx;
  ny2 = ny+2*offset; nx2 = nx+2*offset;
  imgsize2 = ny2*nx2;
  cmap1 = (unsigned char *) calloc (2*imgsize2,sizeof(unsigned char));
  extendbounduc(cmap,cmap1,ny,nx,offset,1);
  extendbounduc(cmap+imgsize,cmap1+imgsize2,ny,nx,offset,1);
  corner[0]=0; corner[1]=step; corner[2]=3*step;

  cornerT[0]=-offset;        cornerT[1]=offset;
  cornerT[2]=-offset+step;   cornerT[3]=offset-step;
  cornerT[4]=-offset+2*step; cornerT[5]=offset-2*step;

  StN1=2*(sqr(2*offset/step+1)-20); 
  St1=StN1*sqr(1);
  for (l=0;l<imgsize;l++) JT[l]=0;

  avgt=(float *)calloc(N,sizeof(float));
  p=(int *)calloc(N,sizeof(int));

  loc = 0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      if (rmap[loc]!=0 && rmap[loc+imgsize]!=0) JT[loc]=2;
      else 
      {
        cornerT[0]=iy-offset;        cornerT[1]=iy+offset;
        cornerT[2]=iy-offset+step;   cornerT[3]=iy+offset-step;
        cornerT[4]=iy-offset+2*step; cornerT[5]=iy+offset-2*step;

        St = St1;
        for (i=0;i<N;i++) { avgt[i]=0; p[i]=0; }
        sy = iy-offset; ey = iy+offset;
        for (jy=sy;jy<=ey;jy+=step)
        {
          if      (jy==cornerT[0] || jy==cornerT[1]) cornerI = 2;
          else if (jy==cornerT[2] || jy==cornerT[3]) cornerI = 1;
          else if (jy==cornerT[4] || jy==cornerT[5]) cornerI = 1;
          else cornerI = 0;
          sx = ix-offset+corner[cornerI]; ex = ix+offset-corner[cornerI];
          for (jx=sx;jx<=ex;jx+=step)
          {
            loc1 = LOC2(jy+offset,jx+offset,nx2);
            p[cmap1[loc1]] ++;
            avgt[cmap1[loc1]] -= 1;
            p[cmap1[loc1+imgsize2]] ++;
            avgt[cmap1[loc1+imgsize2]] += 1;
          }
        }
        for (i=0;i<N;i++)
        {
          if (p[i]>0) avgt[i]/=p[i]; 
        }
        Sw=0;
        sy = iy-offset; ey = iy+offset;
        for (jy=sy;jy<=ey;jy+=step)
        {
          if      (jy==cornerT[0] || jy==cornerT[1]) cornerI = 2;
          else if (jy==cornerT[2] || jy==cornerT[3]) cornerI = 1;
          else if (jy==cornerT[4] || jy==cornerT[5]) cornerI = 1;
          else cornerI= 0;
          sx = ix-offset+corner[cornerI]; ex = ix+offset-corner[cornerI];
          for (jx=sx;jx<=ex;jx+=step)
          {
            loc1 = LOC2(jy+offset,jx+offset,nx2);
            Sw += sqr(-1-avgt[cmap1[loc1]]);
            Sw += sqr(1-avgt[cmap1[loc1+imgsize2]]);
          }
        }
        if (Sw==0) JT[loc]=2;
        else
        {
          Sb = St- Sw;
          if (Sb<0) Sb=0;
          JT[loc] = Sb/Sw;
          if (JT[loc]>2) JT[loc]=2;
        }
      }
      loc ++;
    }
  }
  free(cmap1);

  free(avgt); free(p);

  if (step>1)
  {
    step /=2;
    Jtmp=(float *)calloc(imgsize,sizeof(float));
    weight = (float **)fmatrix(2*step+1,2*step+1);
    genwindow(weight,2*step+1);
    for (i=0;i<2;i++)
    {
      for (l=0;l<imgsize;l++) Jtmp[l]=JT[l];
      loc = 0;
      for (iy=0;iy<ny;iy++)
      {
        for (ix=0;ix<nx;ix++)
        {
          if (rmap[loc]==0)
          {
            JT[loc]=0; total=0;
            for (jy=iy-step;jy<=iy+step;jy++)
            {
              for (jx=ix-step;jx<=ix+step;jx++)
              {
                if (jy>=0 && jy<ny && jx>=0 && jx<nx)
                {
                  loc1 = LOC2(jy,jx,nx);
                  if (rmap0[loc]==rmap0[loc1])
                  {
                    JT[loc] += weight[jy-iy+step][jx-ix+step]*Jtmp[loc1];
                    total += weight[jy-iy+step][jx-ix+step];
                  }
                }
              }
            }
            JT[loc] /= total;
          }
          loc ++;
        }
      }
    }
    free(Jtmp);
    free_fmatrix(weight,2*step+1);
  }
}

float gettotalJS(unsigned char *cmap,int N,int ny,int nx,unsigned char *rmap,int TR,
     float *totalJ,float **mapmatrix,int oldTR)
{
  int iy,ix,i,j,*StN,**avgN,l;
  float *St,*Sb,*Sw,*Stmeanx,*Stmeany,**avgy,**avgx,overallJ,**var;
int debug=0;

  St = (float *)calloc(TR+1,sizeof(float));
  Sb = (float *)calloc(TR+1,sizeof(float));
  Sw = (float *)calloc(TR+1,sizeof(float));
  Stmeanx = (float *)calloc(TR+1,sizeof(float));
  Stmeany = (float *)calloc(TR+1,sizeof(float));
  StN = (int *)calloc(TR+1,sizeof(int));

  avgy = (float **)fmatrix(TR+1,N);
  avgx = (float **)fmatrix(TR+1,N);
  avgN = (int **)imatrix(TR+1,N);
  var = (float **)fmatrix(TR+1,N);

  l=0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      if (rmap[l]>0)
      {
        i=rmap[l]; j=cmap[l];
        Stmeanx[i] += ix; Stmeany[i] += iy;
        StN[i] ++;
        avgx[i][j] += ix; avgy[i][j] += iy;
        avgN[i][j] ++;
      }
      l++;
    }
  }

  for (i=1;i<=TR;i++)
  {
    Stmeanx[i] /= StN[i]; Stmeany[i] /= StN[i];
    for (j=0;j<N;j++)
    {
      if (avgN[i][j]>0) { avgx[i][j] /= avgN[i][j]; avgy[i][j] /= avgN[i][j]; }
    }
  }

  l=0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      if (rmap[l]>0)
      {
        i=rmap[l]; j=cmap[l];
        St[i] += sqr(iy-Stmeany[i]) + sqr(ix-Stmeanx[i]);
        var[i][j] += sqr(iy-avgy[i][j]) + sqr(ix-avgx[i][j]);
      }
      l++;
    }
  }
  for (i=1;i<=TR;i++)
  {
    for (j=0;j<N;j++) Sw[i] += var[i][j];
  }

  overallJ=0;
  for (i=1;i<=TR;i++)
  {
    if (Sw[i]==0) printf("Sw[%d]=0\n",i);
    else
    {
      Sb[i]=St[i]-Sw[i];
      totalJ[i] = Sb[i]/Sw[i];
      overallJ += StN[i]*totalJ[i];
    }
/*
if (debug) printf("%5.3f ",totalJ[i]);
*/
  }
  overallJ = overallJ/ny/nx;
if (debug) printf("\n%5.3f\n",overallJ);

  if (oldTR>0)
  {
    for (i=1;i<=TR;i++)
    {
      for (j=0;j<N;j++) mapmatrix[i][j] = var[i][j];
      mapmatrix[i][N] = St[i];
    }
  }

  free(Stmeanx); free(Stmeany); free(StN); free(St); free(Sb); free(Sw);
  free_fmatrix(avgx,TR+1); free_fmatrix(avgy,TR+1); free_imatrix(avgN,TR+1);
  free_fmatrix(var,TR+1);
  return overallJ;
}

float gettotalJC(float *B,unsigned char *cmap,int N,float **cb,int dim,int npt,
    float ST)
{
  float SW,J,*var,*A;
  int i,l;

  getcmap(B,cmap,cb,npt,dim,N);

  var = (float *)calloc(N,sizeof(float));
  A=B;
  for (l=0;l<npt;l++) 
  {
    var[cmap[l]] += distance2(A,cb[cmap[l]],dim);
    A += dim;
  }
  SW=0;
  for (i=0;i<N;i++) SW += var[i]; 
  J=(ST-SW)/SW;

  free(var);
  return J;
}

