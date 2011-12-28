#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <math.h>
#include "mathutil.h"
#include "imgutil.h"
#include "memutil.h"
#include "ioutil.h"
#include "segment.h"

int MM=0;
unsigned char *rmap9;
char tmpfname[200];

int segment(unsigned char *rmap0,unsigned char *cmap,int N,int nt,int ny,int nx,
    unsigned char *RGB,char *outfname,char *exten,int type,int dim,int NSCALE,
    float displayintensity,int verbose,int tt)
{
  float MINRSIZE[5];
  int scale[5],offset[5],step[5],MAXSCALE,MINSCALE,*count,TR,i,j,k,l;
  int oldTR,extraTR,*reg,*reg2,*convert,datasize,autoscale;
  short *rmap;

  printf("start segmentation\n");
  scale[0]=32;  offset[0]=2;  step[0]=1;  /* not used */
  scale[1]=64;  offset[1]=4;  step[1]=1;
  scale[2]=128; offset[2]=8;  step[2]=2;
  scale[3]=256; offset[3]=16; step[3]=4;
  scale[4]=512; offset[4]=32; step[4]=8;
  for (i=4;i>=1;i--)
  {
    if (ny*nx>=sqr(scale[i])) { MAXSCALE=i; break; }
  }

  if (i==0) { printf("minimum image size 64x64\n"); return 0; }
  if (nt==1)
  {
    for (i=0;i<=MAXSCALE;i++) MINRSIZE[i]=2.0*sqr(offset[i]);
  }
  if (nt>1) 
  {
    for (i=0;i<=MAXSCALE;i++) MINRSIZE[i]=sqr(offset[i]);
  }

  if (NSCALE>0) 
  {
    autoscale=0;
    MINSCALE=MAXSCALE-NSCALE+1;
    if (MINSCALE<=0) { MINSCALE=1; NSCALE=MAXSCALE-MINSCALE+1; }
  }
  else if (NSCALE==-1)
  {
    autoscale=1;
    if (MAXSCALE>=2)
    {
      MINSCALE = 2;
      NSCALE=MAXSCALE-MINSCALE+1;
      if (NSCALE>2)
      {
        NSCALE = 2;
        MINSCALE=MAXSCALE-NSCALE+1;
      }
    }
    else { MINSCALE = 1; NSCALE = 1; }
  }

  datasize = nt*ny*nx;
  rmap=(short *)calloc(datasize,sizeof(short));
  for (l=0;l<datasize;l++) rmap0[l]=1;
  oldTR=1;

  for (i=MAXSCALE;i>=MINSCALE;i--)
  {
    for (l=0;l<datasize;l++) rmap[l]=0;
    TR=segment1(cmap,N,nt,ny,nx,offset,step,rmap,rmap0,oldTR,i,MINRSIZE[i],0,tt);
    if (verbose || nt>1) printf("init %d TR=%d %f\n",i,TR,MINRSIZE[i]);

    reg = (int *) calloc(oldTR+1,sizeof(int));
    reg2 = (int *) calloc(TR+1,sizeof(int));
    for (l=0;l<datasize;l++) 
    {
      j = rmap0[l]; k=rmap[l];
      if (reg[j]==0) reg[j] = k; 
      else if (reg[j]==-1) reg2[k]=-1;
      else if (reg[j]!=k) { reg2[k]=-1; reg2[reg[j]]=-1; reg[j]=-1; }
      rmap0[l]=k;
    }
    free(reg); 

    if (nt>1) tempofilt(rmap0,nt,ny,nx,N,cmap,offset,step);
    count = (int *)calloc(TR+1,sizeof(int));
    for (l=0;l<datasize;l++) count[rmap0[l]]++;

    do
    {
      if (i<=MAXSCALE-2 || i==1) break;
      if (verbose || nt>1) printf("redo ");
      oldTR=TR;
      convert = (int *)calloc(oldTR+1,sizeof(int));
      for (j=1;j<=oldTR;j++) convert[j] = j;

      for (j=1;j<=oldTR;j++)
      {
        if (count[j]>tt*sqr(scale[i])/8 && reg2[j]==-1) 
        {
          if (verbose || nt>1) printf("j=%d ",j);
          convert[j]=0;
          TR --; 
          for (k=j+1;k<=oldTR;k++) convert[k]--;
        }
      }
      if (TR<oldTR)
      {
        for (l=0;l<datasize;l++)
        {
          if (convert[rmap0[l]]==0) rmap[l]=0;
          else rmap[l]=-1;
        }
        extraTR=segment1(cmap,N,nt,ny,nx,offset,step,rmap,rmap0,oldTR,i,MINRSIZE[i],
            oldTR,tt);
        if (extraTR>oldTR-TR)
        {
          reg2 = (int *) realloc(reg2,(TR+extraTR+1)*sizeof(int));
          reg = (int *)calloc(oldTR+1,sizeof(int));
          for (j=1;j<=oldTR;j++) reg2[convert[j]]=reg2[j];
          for (j=TR+1;j<=TR+extraTR;j++) reg2[j]=0; 
        
          for (l=0;l<datasize;l++)
          {
            j = rmap0[l];
            if (rmap[l]>0) 
            {
              k = TR+rmap[l];
              rmap0[l] = k;
              if (reg[j]==0) reg[j] = k; 
              else if (reg[j]==-1) reg2[k]=-1; 
              else if (reg[j]!=k) { reg2[k]=-1; reg2[reg[j]]=-1; reg[j]=-1; }
            }
            else if (rmap[l]==0) rmap0[l]=0;
            else rmap0[l] = convert[j];
          }
          free(reg);
        }
        TR+=extraTR;
      }
      free (convert);

      if (TR>oldTR)
      {
        if (nt>1) tempofilt(rmap0,nt,ny,nx,N,cmap,offset,step);
        count = (int *)realloc(count,(TR+1)*sizeof(int));
        for (j=1;j<=TR;j++) count[j]=0;
        for (l=0;l<datasize;l++) count[rmap0[l]]++;
      }
      if (verbose || nt>1) printf("TR=%d \n",TR);
    } while (oldTR!=TR);
    free(count); free(reg2);
    oldTR=TR;
    if (verbose)
      outputEdge(outfname,exten,RGB,rmap0,ny,nx,i,type,dim,displayintensity);
    printf("%d TR=%d\n",i,TR);
  }

  if (autoscale==1 && MINSCALE>1 && NSCALE<3 && nt==1)
  {
    i = MINSCALE-1;
    TR=segment2(rmap0,rmap,i,cmap,N,nt,ny,nx,tt,oldTR,MINRSIZE,offset,step,verbose);
    if (verbose)
    {
      if (verbose || nt>1) printf("TR=%d \n",TR);
      outputEdge(outfname,exten,RGB,rmap0,ny,nx,i,type,dim,displayintensity);
    }
  }

  free(rmap);
  return TR;
}

int segment2(unsigned char *rmap0,short *rmap,int i,unsigned char *cmap,int N,int nt,
    int ny,int nx,int tt,int oldTR,float *MINRSIZE,int *offset,int *step,int verbose)
{
  float oldJ[256],**mapmatrix,*change,**P;
  int TR,j,k,l,*convert,imgsize,*count,extraTR;
  int debug=0;

  imgsize = ny*nx;
  for (k=0;k<256;k++) oldJ[k]=0;
  mapmatrix = (float **)fmatrix(oldTR+1,N+1);
  gettotalJS(cmap,N,ny,nx,rmap0,oldTR,oldJ,mapmatrix,oldTR);

  count = (int *)calloc(oldTR+1,sizeof(int));
  P = (float **)fmatrix(oldTR+1,N);
  for (l=0;l<imgsize;l++) 
  {
    P[rmap0[l]][cmap[l]] += 1.0;
    count[rmap0[l]] ++;
  }
  for (j=1;j<=oldTR;j++) 
  {
    for (k=0;k<N;k++) mapmatrix[j][k] /= P[j][k];
    mapmatrix[j][N] /= count[j];
  }

  change = (float *)calloc(oldTR+1,sizeof(float));
  convert = (int *)calloc(oldTR+1,sizeof(int));
  for (j=1;j<=oldTR;j++) 
  {
    for (k=0;k<N;k++) 
    {
      if (mapmatrix[j][k]<mapmatrix[j][N]/4 && P[j][k]>2*MINRSIZE[i])
        change[j]=1.0;
    }
if (debug) 
{
  if (change[j]>1.0 || oldJ[j]>1.0)
  {
    printf("%d ",j);
    for (k=0;k<N;k++) 
    { 
      if (P[j][k]>0.01) printf("%1.0f %1.0f; ",mapmatrix[j][k],P[j][k]); 
    }
    printf("%1.0f %4.2f \n",mapmatrix[j][N],oldJ[j]);
  }  
}
  }
/*
printf("%d %d %d\n",rmap0[60*352+140],rmap0[151*352+112],rmap0[202*352+348]);
*/

  TR=oldTR;
  for (j=1;j<=oldTR;j++) convert[j]=j; 
  for (j=1;j<=oldTR;j++)
  {
    if (change[j]>=1.0 || oldJ[j]>1.0) 
    {
      convert[j]=0;
      for (k=j+1;k<=oldTR;k++) convert[k]--;
      TR--;
    }
  }

  for (l=0;l<imgsize;l++) 
  {
    if (convert[rmap0[l]]>0) rmap[l]=-1; 
    else rmap[l]=0;
  }
  extraTR=segment1(cmap,N,nt,ny,nx,offset,step,rmap,rmap0,oldTR,i,MINRSIZE[i],0,tt);
  for (l=0;l<imgsize;l++)  
  { 
    if (rmap[l]>0) rmap0[l]=rmap[l]+TR; 
    else rmap0[l]=convert[rmap0[l]];
  }
  TR += extraTR;
  if (verbose) printf("init %d TR=%d %f\n",i,TR,MINRSIZE[i]);

  free(count);
  free(convert);
  free(change);
  free_fmatrix(P,oldTR+1);
  free_fmatrix(mapmatrix,oldTR+1);
  return TR;
}

int segment1(unsigned char *cmap,int N,int nt,int ny,int nx,int *offset,int *step, 
    short *rmap,unsigned char *rmap0,int oldTR,int i,float MINRSIZE,int redo,int tt)
{
  float *J,*JT,**threshJ1,**threshJ2;
  int j,TR,**done,alldone,datasize,it,imgsize;

  imgsize = ny*nx;
  datasize = nt*ny*nx;
  J = (float *)calloc(datasize,sizeof(float));

  for (it=0;it<nt;it++)
    getJ(cmap+it*imgsize,N,ny,nx,J+it*imgsize,offset[i],step[i],rmap+it*imgsize,
        rmap0+it*imgsize,oldTR);

  if (nt>1)
  {
    JT = (float *)calloc(datasize-imgsize,sizeof(float));
    for (it=0;it<nt-1;it++)
    {
      getJT(cmap+it*imgsize,N,ny,nx,JT+it*imgsize,offset[1],step[1],rmap+it*imgsize,
        rmap0+it*imgsize,oldTR);

/*
if (it==0) 
{
  showJ(JT,threshJ1,threshJ2,rmap0,1,ny,nx);
  exit(-1);
}
*/
    }
  }

  done = (int **)imatrix(nt,oldTR+1);
  threshJ1 = (float **)fmatrix(nt,oldTR+1);
  threshJ2 = (float **)fmatrix(nt,oldTR+1);
  for (it=0;it<nt;it++) 
  {
    getthreshJ(imgsize,J+it*imgsize,rmap+it*imgsize,rmap0+it*imgsize,threshJ1[it],
        threshJ2[it],oldTR,0,done[it]);
  }

/*
  if (redo==0 && i==2)
  {
    showJ(J,threshJ1,threshJ2,rmap0,nt,ny,nx);
  }
*/

  TR=track(rmap,J,JT,nt,ny,nx,threshJ1,MINRSIZE,rmap0,0,tt,threshJ2,oldTR);

  free_fmatrix(threshJ1,nt); free_fmatrix(threshJ2,nt);
  if (nt>1) free(JT);

  removehole(rmap,nt,ny,nx,rmap0);
  alldone=getrmap2(rmap,J,nt,ny,nx,TR,oldTR,rmap0,done);
  if (alldone<nt*oldTR) 
  {
    removehole(rmap,nt,ny,nx,rmap0);
    for (j=i-1;j>=MAX(i-2,1);j--)
    {
      for (it=0;it<nt;it++)
        getJ(cmap+it*imgsize,N,ny,nx,J+it*imgsize,offset[j],step[j],rmap+it*imgsize,
            rmap0+it*imgsize,oldTR);
      alldone=getrmap2(rmap,J,nt,ny,nx,TR,oldTR,rmap0,done);
      if (alldone==nt*oldTR) break;
      removehole(rmap,nt,ny,nx,rmap0);
    }
    flood(rmap,J,nt,ny,nx,rmap0,oldTR,done);
  }
  free_imatrix(done,nt);
  free(J);

  return TR; 
}

int track(short *rmap,float *J0,float *JT0,int nt,int ny,int nx,float **threshJ1,
    float MINRSIZE,unsigned char *rmap00,int n2bgrow,int tt,float **threshJ2,
    int oldTR)
{
  unsigned char *rmap0;
  short *rmap1,*rmap2[TN];
  float *J,*JT,**threshJ3;
  int imgsize,datasize,TR,TR1[TN],TR2,*tracklen,*convert[TN],newTR[TN],**appear;
  int index[TN];
  int i,j,k,l,st,it,*tracklen1[TN],*convert1,TR3,TR4[TN],TR5[TN];

  imgsize = ny*nx;
  rmap1 = rmap; rmap0 = rmap00; J=J0; JT=JT0;
  appear = (int **)imatrix(nt,oldTR+1);
  TR=getrmap3(rmap1,J,ny,nx,threshJ1[0],0,MINRSIZE,rmap0,n2bgrow,threshJ2[0],
      oldTR,appear[0]);
  if (nt==1) return TR;

/*
if (MM==1)
{
  rmap9=(unsigned char *)calloc(imgsize,sizeof(unsigned char));
  sprintf(tmpfname,"rmap.0.gray");
  for (l=0;l<imgsize;l++)
  {
    if (rmap1[l]>0) rmap9[l]=rmap1[l]+1;
    else if (rmap1[l]==0) rmap9[l]=1;
  }
  outputimgraw(tmpfname,rmap9,ny,nx,1);
  free(rmap9);
}
*/
 
  rmap1 += imgsize; rmap0 += imgsize; J += imgsize;
  st=1;
  while (TR==0 && st<=nt-tt)
  {
    TR=getrmap3(rmap1,J,ny,nx,threshJ1[st],0,MINRSIZE,rmap0,n2bgrow,threshJ2[st],
        oldTR,appear[st]);
    rmap1 += imgsize; rmap0 += imgsize; J += imgsize; JT += imgsize;
    st++;
  }
  if (st>nt-tt+1) return TR;
  tracklen = (int *) calloc(TR+1,sizeof(int));
  for (i=1;i<=TR;i++) tracklen[i]=1;

  threshJ3 = (float **)fmatrix(TN,oldTR+1);
  for (k=0;k<TN;k++) rmap2[k]=(short *)calloc(imgsize,sizeof(short));

  for (it=st;it<nt;it++)
  {
    for (j=1;j<=oldTR;j++) appear[it][j]=0; 
    for (l=0;l<imgsize;l++) { if (rmap1[l]==n2bgrow) appear[it][rmap0[l]]=1; }
    for (j=1;j<=oldTR;j++)
    {
      if (appear[it][j]) 
      {
if (MM==1) printf("\nit=%d j=%d TR=%d \n",it,j,TR);
        for (k=0;k<TN;k++) 
        {
          TR4[k]=-1000;
          tracklen1[k]=(int *)calloc(TR+1,sizeof(int));
          for (i=1;i<=TR;i++) tracklen1[k][i]=tracklen[i];
          threshJ3[k][j]=threshJ1[it][j]-(k-2)*0.2*threshJ2[it][j];
          for (l=0;l<imgsize;l++)
          {
            if (rmap0[l]==j) rmap2[k][l]=rmap1[l];
            else rmap2[k][l]=-4;
          }
          TR2=getrmap1(rmap2[k],J,ny,nx,threshJ3[k],TR,MINRSIZE,rmap0,n2bgrow);
          convert[k] = (int *)calloc(TR2+1,sizeof(int));
          for (i=1;i<=TR2;i++) convert[k][i]=i;
          if (TR2>TR)
            TR4[k]=track1(&(tracklen1[k]),TR,TR2,imgsize,rmap1-imgsize,rmap2[k],
                JT,rmap0,convert[k],&(TR1[k]),&(newTR[k]));

/*
if (MM==1) 
{
  printf("k=%d TR2=%d TR1=%d newTR=%d TR4=%d\n",k,TR2,TR1[k],newTR[k],TR4[k]);
  for (i=1;i<=TR2;i++) printf("%d ",convert[k][i]);
  printf("\n");
}
*/

        }
        piksrtint(TN,TR4,index);
        if (TR4[0]>=0)
        {
          for (k=0;k<TN;k++)
          {
            if (TR4[k]==TR4[0]) TR5[index[k]]=TR1[index[k]];
            else TR5[index[k]]=-1;
          }
          piksrtint(TN,TR5,index);
        }
        else if (TR4[0]<0)
        {
          k = index[0]; 
          for (i=1;i<=TR;i++) tracklen1[k][i]=tracklen[i];
          threshJ3[k][j] = threshJ3[k][j] - 0.1*threshJ2[it][j];
          for (l=0;l<imgsize;l++)
          {
            if (rmap0[l]==j) rmap2[k][l]=rmap1[l];
            else rmap2[k][l]=-4;
          }
          TR2=getrmap1(rmap2[k],J,ny,nx,threshJ3[k],TR,MINRSIZE,rmap0,n2bgrow);
          if (TR2==TR)
          {
            TR2++;
            for (l=0;l<imgsize;l++) 
            { 
              if (rmap0[l]==j && rmap1[l]==n2bgrow) rmap2[k][l]=TR2; 
              else rmap2[k][l]=-4;
            }
          }
          convert[k] = (int *)realloc(convert[k],(TR2+1)*sizeof(int));
          for (i=1;i<=TR2;i++) convert[k][i]=i;
          if (TR2>TR)
            TR4[k]=track1(&(tracklen1[k]),TR,TR2,imgsize,rmap1-imgsize,rmap2[k],
                JT,rmap0,convert[k],&(TR1[k]),&(newTR[k]));
        }

/*
if (MM==1)
{
  rmap9=(unsigned char *)calloc(imgsize,sizeof(unsigned char));
  sprintf(tmpfname,"rmap.%d.%d.gray",it,j);
  for (l=0;l<imgsize;l++) 
  {
    if (rmap2[index[0]][l]>0) rmap9[l]=200;
    else if (rmap0[l]==j) rmap9[l]=100;
  }
  outputimgraw(tmpfname,rmap9,ny,nx,1);
  free(rmap9);  
}
*/

        if (TR1[index[0]]>0)
        {
          if (newTR[index[0]]<TR)
          {
            datasize = it*imgsize;
            for (l=0;l<datasize;l++)
            {
              if (rmap[l]>0) rmap[l]=convert[index[0]][rmap[l]];
            }
            for (l=0;l<imgsize;l++)
            {
              if (rmap1[l]>0) rmap1[l]=convert[index[0]][rmap1[l]];
            }
          }
          for (l=0;l<imgsize;l++)
          {
            if (rmap2[index[0]][l]>0) 
              rmap1[l]=convert[index[0]][rmap2[index[0]][l]];
          }
          tracklen=(int *) realloc(tracklen,(TR1[index[0]]+1)*sizeof(int));
          for (i=1;i<=TR1[index[0]];i++) tracklen[i]=tracklen1[index[0]][i];
          TR = TR1[index[0]];
if (MM==1)
{
  printf("index=%d TR=%d Track ",index[0],TR);
  for (i=1;i<=TR;i++) printf("%d ",tracklen[i]);
  printf("\n");
}
        }
        for (k=0;k<TN;k++) free(tracklen1[k]);
        for (k=0;k<TN;k++) free(convert[k]);
      }
    }

/*
if (MM==1)
{
  rmap9=(unsigned char *)calloc(imgsize,sizeof(unsigned char));
  sprintf(tmpfname,"rmap.%d.gray",it);
  for (l=0;l<imgsize;l++)
  {
    if (rmap1[l]>0) rmap9[l]=rmap1[l]+1;
    else if (rmap1[l]==0) rmap9[l]=1;
  }
  outputimgraw(tmpfname,rmap9,ny,nx,1);
  free(rmap9);
}
*/
    rmap1 += imgsize; rmap0 += imgsize; J += imgsize; JT += imgsize;
  }
  free_fmatrix(threshJ3,TN);
  for (k=0;k<TN;k++) free(rmap2[k]);

  convert1 = (int *)calloc(TR+1,sizeof(int));
  for (i=1;i<=TR;i++) convert1[i]=i;
  TR3 = TR;
  for (i=1;i<=TR;i++)
  {
    if (tracklen[i]<tt)
    {
      for (j=i+1;j<=TR;j++) convert1[j]--;
      convert1[i] = n2bgrow;
      TR3--;
    }
  }

  if (TR3<TR)
  {
    datasize = nt*imgsize;
    for (l=0;l<datasize;l++)
    {
      if (rmap[l]>0) rmap[l]=convert1[rmap[l]];
    }
  }
  free(convert1);
  free(tracklen);

/*
rmap1 = rmap; rmap0 = rmap00;
check1=(int *) calloc(oldTR+1,sizeof(int));
printf("recheck\n");
for (it=0;it<nt;it++)
{
  for (i=1;i<=oldTR;i++) check1[i]=0;
  for (l=0;l<imgsize;l++)
  {
    if (rmap1[l]>0) check1[rmap0[l]]=1;
  }
  for (i=1;i<=oldTR;i++)
  {
    if (appear[it][i] && check1[i]==0) printf("it=%d %d\n",it,i);
  }
  rmap1 += imgsize; rmap0 += imgsize;
}
free(check1);
*/

  free_imatrix(appear,nt); 
  return TR3;
}

int track1(int **tracklen,int TR,int TR2,int imgsize,short *rmap1,short *rmap2,
    float *JT,unsigned char *rmap0,int *convert,int *TR1,int *newTR)
{
  int **neigh,i,j,k,l,l1,m,TR4,*appear,Tappear,*tracked;

/*
printf("TR=%d TR2=%d \n",TR,TR2);
*/

  appear = (int *)calloc(TR+1,sizeof(int));
  neigh = (int **)imatrix(TR+1,TR2+1);
  for (l=0;l<imgsize;l++)
  {
    l1 = l-imgsize;
    if (rmap1[l]>0) 
    {
      appear[rmap1[l]]=1;
      if (rmap2[l]>0 && JT[l]<0.2)
      {
        if (rmap0[l]==rmap0[l1]) neigh[rmap1[l]][rmap2[l]] = 1;
      }
    }
  }

  tracked = (int *)calloc(TR+1,sizeof(int));
  TR4=0; Tappear=0;
  for (i=1;i<=TR;i++)
  {
    Tappear+=appear[i];
    for (j=TR+1;j<=TR2;j++)
    {
      if (neigh[i][j] == 1) { (*tracklen)[i]++; TR4++; tracked[i]=1; break; }
    }
  }
  free(appear);
  TR4 = TR4-Tappear;
  *TR1 = TR2;
  for (i=1;i<=TR;i++)
  {
    for (j=TR+1;j<=TR2;j++)
    {
      if (neigh[i][j] == 1)
      {
        for (k=j+1;k<=TR2;k++)
        {
          if (convert[k]>convert[j]) convert[k]--;
        }
        convert[j] = i;
        for (k=i+1;k<=TR;k++)
        {
          if (neigh[k][j] == 1)
          {
            neigh[i][k] = neigh[k][i] = 1;
            neigh[k][j] = 0;
          }
        }
        (*TR1)--;
      }
    }
  }

/*
printf("TR4=%d\n",TR4);
*/
  *tracklen = (int *) realloc(*tracklen,((*TR1)+1)*sizeof(int));
  for (i=TR+1;i<=(*TR1);i++) (*tracklen)[i]=1;
  *newTR=TR;
  do
  {
    m=0;
    for (i=1;i<(*newTR);i++)
    {
      for (j=i+1;j<=(*newTR);j++)
      {
        if (neigh[i][j]==1)
        {
/*
          if (tracked[j]) TR4--;
*/
          TR4--;
          for (k=1;k<=TR2;k++)
          {
            if (convert[k]==j) convert[k]=i;
            else if (convert[k]>j) convert[k]--;
          }
          (*tracklen)[i] = MAX((*tracklen)[i],(*tracklen)[j]);
          for (k=j+1;k<=(*TR1);k++) (*tracklen)[k-1] = (*tracklen)[k];
          for (k=1;k<=(*newTR);k++)
          {
            if (k!=i && k!=j)
            {
              if (neigh[j][k]==1) { neigh[i][k] = neigh[k][i] = 1; }
            }
          }
          for (k=1;k<=(*newTR);k++)
            for (l=j+1;l<=(*newTR);l++) neigh[k][l-1]=neigh[k][l];
          for (k=j+1;k<=(*newTR);k++)
          {
            for (l=1;l<=(*newTR)-1;l++) neigh[k-1][l]=neigh[k][l];
            tracked[k-1]=tracked[k];
          }
          (*newTR)--; (*TR1)--; 
          m = 1;
        }
      }
    }
  } while (m==1);
  free(tracked);
  free_imatrix(neigh,TR+1);
  return TR4;
}

int merge1(unsigned char *rmap,unsigned char *cmap,int N,int nt,int ny,int nx,int TR,
    float threshcolor)
{
  int it,iy,ix,ir,jr,i,mini,minj,newtr,*npt,npttotal;
  float *currentJ,*mergeJ,mindist,**distnpt,**distcolor,**distJ,**unused,**P;
  int loc,loc1,l,datasize,imgsize,*convert,threshtr;
  unsigned char *rmap1;
  float oldoverallJ,overallJ;
int debug=0;

  if (threshcolor>=0) 
  {
    TR=merge(rmap,cmap,N,nt,ny,nx,TR,threshcolor,0);
    return TR;
  }

  threshcolor=0.5; 
  threshtr = TR;

  imgsize = ny*nx;
  datasize = nt*imgsize;
  distnpt=(float **)fmatrix(TR+1,TR+1);
  distJ=(float **)fmatrix(TR+1,TR+1);
  distcolor=(float **)fmatrix(TR+1,TR+1);
  loc=0;
  for (it=0;it<nt;it++)
  {
    for (iy=0;iy<ny;iy++)
    {
      loc++;
      for (ix=1;ix<nx;ix++)
      {
        loc1 = loc-1;
        if (rmap[loc1]!=rmap[loc])
        {
          ir=rmap[loc1]; jr=rmap[loc];
          distnpt[ir][jr]+=1; distnpt[jr][ir]=distnpt[ir][jr];
        }
        loc++;
      }
    }
  }

  loc=0;
  for (it=0;it<nt;it++)
  {
    loc+=nx;
    for (iy=1;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        loc1 = loc-nx;
        if (rmap[loc1]!=rmap[loc])
        {
          ir=rmap[loc1]; jr=rmap[loc];
          distnpt[ir][jr]+=1; distnpt[jr][ir]=distnpt[ir][jr];
        }
        loc++;
      }
    }
  }

  rmap1 = (unsigned char *)calloc(datasize,sizeof(unsigned char));
  currentJ=(float *)calloc(TR+1,sizeof(float));
  mergeJ=(float *)calloc(2,sizeof(float));
  overallJ=gettotalJS(cmap,N,ny,nx,rmap,TR,currentJ,unused,0);
  oldoverallJ = overallJ;
if (debug) printf("%d %f\n",TR,overallJ);

  P=(float **)fmatrix(TR+1,N);
  npt = (int *)calloc(TR+1,sizeof(int));
  for (l=0;l<datasize;l++) 
  {
    P[rmap[l]][cmap[l]] += 1;
    npt[rmap[l]]++;
  }
  for (ir=1;ir<=TR;ir++)
    for (i=0;i<N;i++) P[ir][i] /= npt[ir];

  mindist=10000;
  for (ir=1;ir<TR;ir++)
  {
    for (jr=ir+1;jr<=TR;jr++)
    {
      if (distnpt[ir][jr]!=0.0)
      {
        for (l=0;l<datasize;l++) 
        {
          if (rmap[l]==ir || rmap[l]==jr) rmap1[l]=1;
          else rmap1[l]=0;
        }
        gettotalJS(cmap,N,ny,nx,rmap1,1,mergeJ,unused,0);
        distJ[ir][jr] = mergeJ[1]-(npt[ir]*currentJ[ir]+npt[jr]*currentJ[jr])
                            /(npt[ir]+npt[jr]);
        distJ[jr][ir] = distJ[ir][jr];

        distcolor[jr][ir] = distcolor[ir][jr] = distance(P[ir],P[jr],N);
        if (distcolor[ir][jr]<mindist)
        {
          mindist=distcolor[ir][jr]; mini=ir; minj=jr;
        }
if (debug>1) printf("%d %d %f \n",ir,jr,distJ[ir][jr]);
      }
    }
  }

  convert = (int *)calloc(TR+1,sizeof(int));
  for (i=1;i<=TR;i++) convert[i]=i;
  newtr=TR;
  while (mindist<threshcolor)
  {
if (debug>1) 
  printf("min %d %d %f %f %f\n",mini,minj,currentJ[mini],currentJ[minj],mindist);

    overallJ = overallJ-(npt[mini]*currentJ[mini]+npt[minj]*currentJ[minj])/datasize;
    npttotal = npt[mini] + npt[minj];
    for (i=0;i<N;i++)
    {
      P[mini][i] = (P[mini][i]*npt[mini]+P[minj][i]*npt[minj]) / npttotal;
    }
    currentJ[mini] = (npt[mini]*currentJ[mini]+npt[minj]*currentJ[minj]) / npttotal 
                    + distJ[mini][minj];
    npt[mini]=npttotal;
    overallJ = overallJ + npt[mini]*currentJ[mini]/datasize;

if (debug) printf("%d %f %f\n",newtr-1,mindist,overallJ);

    if (overallJ <= oldoverallJ) 
    {
      oldoverallJ=overallJ;
      threshtr=newtr-1;
    }

    for (i=1;i<=TR;i++) { if (convert[i]==minj) convert[i]=mini; }
    for (ir=1;ir<=newtr;ir++)
    {
      if (ir!=mini && ir!=minj)
      {
        if (distnpt[mini][ir]!=0.0 || distnpt[minj][ir]!=0.0)
        {
          for (l=0;l<datasize;l++)
          {
            if (convert[rmap[l]]==mini || convert[rmap[l]]==ir) rmap1[l]=1;
            else rmap1[l]=0;
          }
          gettotalJS(cmap,N,ny,nx,rmap1,1,mergeJ,unused,0);
          distJ[mini][ir] = mergeJ[1] - ( npt[mini]*currentJ[mini] 
              + npt[ir]*currentJ[ir]) / (npt[mini]+npt[ir]);
          distJ[ir][mini] = distJ[mini][ir];

          distcolor[mini][ir] = distance(P[mini],P[ir],N);
          distcolor[ir][mini] = distcolor[mini][ir];
          distnpt[mini][ir]=distnpt[mini][ir]+distnpt[minj][ir];
          distnpt[ir][mini]=distnpt[mini][ir];
if (debug>1) 
  printf("%d %d %f %f %f %f\n",mini,ir,distJ[mini][ir],currentJ[mini],currentJ[ir],mergeJ[1]);
        }
      }
    }

    for (i=1;i<=TR;i++) { if (convert[i]>minj) convert[i]--; }

    for (ir=minj+1;ir<=newtr;ir++) 
    {
      npt[ir-1]=npt[ir];
      currentJ[ir-1]=currentJ[ir];
      for (i=0;i<N;i++) P[ir-1][i]=P[ir][i];
    }
    for (ir=1;ir<=newtr;ir++)
    {
      for (jr=minj+1;jr<=newtr;jr++)
      {
        distnpt[ir][jr-1]=distnpt[ir][jr];
        distcolor[ir][jr-1]=distcolor[ir][jr];
        distJ[ir][jr-1]=distJ[ir][jr];
      }
    }
    for (ir=minj+1;ir<=newtr;ir++)
    {
      for (jr=1;jr<=newtr-1;jr++)
      {
        distnpt[ir-1][jr]=distnpt[ir][jr];
        distcolor[ir-1][jr]=distcolor[ir][jr];
        distJ[ir-1][jr]=distJ[ir][jr];
      }
    }

    newtr--; mindist=10000;

    for (ir=1;ir<newtr;ir++)
    {
      for (jr=ir+1;jr<=newtr;jr++)
      {
        if (distnpt[ir][jr]!=0)
        {
          if (distcolor[ir][jr]<mindist)
          {
            mindist=distcolor[ir][jr]; mini=ir; minj=jr;
          }
        }
      }
    }
  }
/*
  for (l=0;l<datasize;l++) rmap[l]=convert[rmap[l]];
*/

  free(rmap1);
  free(currentJ);
  free(mergeJ);
  free(npt);
  free_fmatrix(P,TR+1);
  free(convert);
  free_fmatrix(distnpt,TR+1);
  free_fmatrix(distJ,TR+1);
  free_fmatrix(distcolor,TR+1);

  TR=merge(rmap,cmap,N,nt,ny,nx,TR,threshcolor,threshtr);
  return TR;
}

int merge(unsigned char *rmap,unsigned char *cmap,int N,int nt,int ny,int nx,int TR,
    float threshcolor,int threshtr)
{
  int it,iy,ix,ir,*npt,npttotal,jr,i,mini,minj,newtr;
    float **P,mindist,**distnpt,**distcolor;
  int loc,loc1,l,datasize,imgsize,*convert;;

  imgsize = ny*nx;
  datasize = nt*imgsize;
  distnpt=(float **)fmatrix(TR+1,TR+1);
  distcolor=(float **)fmatrix(TR+1,TR+1);
  loc=0;
  for (it=0;it<nt;it++)
  {
    for (iy=0;iy<ny;iy++)
    {
      loc++;
      for (ix=1;ix<nx;ix++)
      {
        loc1 = loc-1;
        if (rmap[loc1]!=rmap[loc])
        {
          ir=rmap[loc1]; jr=rmap[loc];
          distnpt[ir][jr]+=1; distnpt[jr][ir]=distnpt[ir][jr];
        }
        loc++;
      }
    }
  }

  loc=0;
  for (it=0;it<nt;it++)
  {
    loc+=nx;
    for (iy=1;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        loc1 = loc-nx;
        if (rmap[loc1]!=rmap[loc])
        {
          ir=rmap[loc1]; jr=rmap[loc];
          distnpt[ir][jr]+=1; distnpt[jr][ir]=distnpt[ir][jr];
        }
        loc++;
      }
    }
  }

  P=(float **)fmatrix(TR+1,N);
  npt=(int *)calloc(TR+1,sizeof(int));
  for (l=0;l<datasize;l++)
  {
    ir=rmap[l];
    P[ir][cmap[l]] += 1;
    npt[ir]++;
  }
  for (ir=1;ir<=TR;ir++)
    for (i=0;i<N;i++) P[ir][i]/=npt[ir];

  mindist=10000;
  for (ir=1;ir<TR;ir++)
  {
    for (jr=ir+1;jr<=TR;jr++)
    {
      if (distnpt[ir][jr]!=0.0)
      {
        distcolor[jr][ir] = distcolor[ir][jr] = distance(P[ir],P[jr],N);
        if (distcolor[ir][jr]<mindist)
        {
          mindist=distcolor[ir][jr]; mini=ir; minj=jr;
        }
      }
    }
  }

  convert = (int *)calloc(TR+1,sizeof(int));
  for (i=1;i<=TR;i++) convert[i]=i;
  newtr=TR;
  while (mindist<threshcolor && newtr>threshtr)
  {
    for (i=1;i<=TR;i++)
    {
      if (convert[i]==minj) convert[i]=mini;
      else if (convert[i]>minj) convert[i]--;
    }

    npttotal = npt[mini] + npt[minj];
    for (i=0;i<N;i++)
    {
      P[mini][i] = (P[mini][i]*npt[mini]+P[minj][i]*npt[minj]) / npttotal;
    }

    npt[mini]=npttotal;
    for (ir=1;ir<=newtr;ir++)
    {
      if (ir!=mini && ir!=minj)
      {
        if (distnpt[mini][ir]!=0.0 || distnpt[minj][ir]!=0.0)
        {
          distcolor[mini][ir] = distance(P[mini],P[ir],N);
          distcolor[ir][mini] = distcolor[mini][ir];
          distnpt[mini][ir]=distnpt[mini][ir]+distnpt[minj][ir];
          distnpt[ir][mini]=distnpt[mini][ir];
        }
      }
    }

    for (ir=1;ir<=newtr;ir++)
    {
      for (jr=minj+1;jr<=newtr;jr++)
      {
        distnpt[ir][jr-1]=distnpt[ir][jr];
        distcolor[ir][jr-1]=distcolor[ir][jr];
      }
    }
    for (ir=minj+1;ir<=newtr;ir++)
    {
      for (jr=1;jr<=newtr-1;jr++)
      {
        distnpt[ir-1][jr]=distnpt[ir][jr];
        distcolor[ir-1][jr]=distcolor[ir][jr];
      }
      npt[ir-1]=npt[ir]; 
      for (i=0;i<N;i++) P[ir-1][i]=P[ir][i];
    }

    newtr--; mindist=10000;
    for (ir=1;ir<newtr;ir++)
    {
      for (jr=ir+1;jr<=newtr;jr++)
      {
        if (distnpt[ir][jr]!=0)
        {
          if (distcolor[ir][jr]<mindist)
          {
            mindist=distcolor[ir][jr]; mini=ir; minj=jr;
          }
        }
      }
    }
  }
  for (l=0;l<datasize;l++) rmap[l]=convert[rmap[l]];

  free(convert);
  free(npt); 
  free_fmatrix(P,TR+1);
  free_fmatrix(distnpt,TR+1);
  free_fmatrix(distcolor,TR+1);
  return newtr;
}

void tempofilt(unsigned char *rmap1,int nt,int ny,int nx,int N,unsigned char *cmap,
    int *offset,int *step)
{
  int l,imgsize,it,**done,**appear,iy,ix;
  unsigned char *rmap0,*rmap;
  short *rmap2,*rmap3;
  float *J;

  imgsize = ny*nx;
  rmap2=(short *)calloc(imgsize,sizeof(short));
  rmap3=(short *)calloc(imgsize,sizeof(short));
  rmap0=(unsigned char *)calloc(imgsize,sizeof(unsigned char));
  for (l=0;l<imgsize;l++) rmap0[l]=1;
  J = (float *)calloc(imgsize,sizeof(float));
  done=(int **)imatrix(1,2);

  appear = (int **)imatrix(nt,256);
  rmap = rmap1;
  for (it=0;it<nt;it++)
  {
    for (l=0;l<imgsize;l++) appear[it][rmap[l]]=1;
    rmap += imgsize;
  }

  rmap = rmap1;
  for (l=0;l<imgsize;l++) { if (rmap[l]==0) break; }
  if (l<imgsize)
  {
    for (l=0;l<imgsize;l++) rmap2[l]=rmap[l];
    getJ(cmap,N,ny,nx,J,offset[1],step[1],rmap2,rmap0,1);
    removehole(rmap2,1,ny,nx,rmap0);
    done[0][1]=0;
    flood(rmap2,J,1,ny,nx,rmap0,1,done);
    for (l=0;l<imgsize;l++) rmap[l]=(unsigned char) rmap2[l];
  }

  for (it=1;it<nt-1;it++)
  {
    if (it<nt-2)
    {
      rmap = rmap1+(it+1)*imgsize;
      for (l=0;l<imgsize;l++)
      {
        if (rmap[l]!=rmap[l+imgsize] && rmap[l]!=rmap[l-imgsize]) rmap3[l]=0;
        else rmap3[l]=rmap[l];
      }
    }

    rmap = rmap1+it*imgsize;
    for (l=0;l<imgsize;l++)
    {
      if (rmap[l-imgsize]==rmap3[l] && rmap[l-imgsize]>0)
      {
        if (appear[it-1][rmap[l]] && appear[it+1][rmap[l]]) 
          rmap[l]=rmap[l-imgsize];
      }
    }

    for (l=0;l<imgsize;l++)
    {
      if (rmap[l]>0)
      {
        if (rmap[l]!=rmap[l-imgsize] && appear[it-1][rmap[l]]) rmap[l]=0;
        else if (rmap[l]!=rmap[l+imgsize] && appear[it+1][rmap[l]]) rmap[l]=0;
      }
    }

    for (l=0;l<imgsize;l++) rmap2[l]=rmap[l];
    l=0;
    for (iy=0;iy<ny;iy++)
    {
      for (ix=0;ix<nx;ix++)
      {
        if (rmap[l]>0)
        {
          if (iy-1>=0) { if (rmap[l-nx]==0) rmap2[l]=0; }
          if (ix-1>=0) { if (rmap[l-1] ==0) rmap2[l]=0; }
          if (ix+1<nx) { if (rmap[l+1] ==0) rmap2[l]=0; }
          if (iy+1<ny) { if (rmap[l+nx]==0) rmap2[l]=0; }
        }
        l++;
      }
    }

    getJ(cmap+it*imgsize,N,ny,nx,J,offset[1],step[1],rmap2,rmap0,1);
    removehole(rmap2,1,ny,nx,rmap0);
    done[0][1]=0;
    flood(rmap2,J,1,ny,nx,rmap0,1,done);
    for (l=0;l<imgsize;l++) rmap[l]=(unsigned char) rmap2[l];
  }

  rmap = rmap1 + (nt-1)*imgsize;
  for (l=0;l<imgsize;l++) { if (rmap[l]==0) break; }
  if (l<imgsize)
  {
    for (l=0;l<imgsize;l++) rmap2[l]=rmap[l];
    getJ(cmap+it*imgsize,N,ny,nx,J,offset[1],step[1],rmap2,rmap0,1);
    removehole(rmap2,1,ny,nx,rmap0);
    done[0][1]=0;
    flood(rmap2,J,1,ny,nx,rmap0,1,done);
    for (l=0;l<imgsize;l++) rmap[l]=(unsigned char) rmap2[l];
  }

  free_imatrix(appear,nt);
  free(rmap0);
  free(rmap2);
  free(rmap3);
  free(J);
  free_imatrix(done,1);
}

