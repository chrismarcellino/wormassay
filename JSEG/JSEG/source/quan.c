#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "mathutil.h"
#include "imgutil.h"
#include "memutil.h"
#include "quan.h"
#include "ioutil.h"
#include "segment.h"

int quantize(float *B,float **cb,int nt,int ny,int nx,int dim,float thresh)
{
  int it,i,offset,N;
  float *A,*weight,avgweight;
  int ny2,nx2,ei;
  unsigned char *P;
int debug=0;

  ei = nt*ny*nx;
  printf ("color quantization\n");

  offset=2;
  ny2 = ny+2*offset; nx2 = nx+2*offset;
  weight=(float *)calloc(ei,sizeof(float));
  A=(float *)calloc(ny2*nx2*dim,sizeof(float));
  avgweight = 0;
  for (it=0;it<nt;it++)
  {
    extendboundfloat(B+it*ny*nx*dim,A,ny,nx,offset,dim);
    avgweight += pga(B+it*ny*nx*dim,A,ny,nx,offset,weight+it*ny*nx,dim);
  }
  avgweight /= nt;
  free(A);

  for (i=0;i<ei;i++) weight[i] = exp(-weight[i]);
  P=(unsigned char *)calloc(ei,sizeof(unsigned char));
  N=MAX(round(2*avgweight),round(17*sqrt(dim/3.0)));
  if (N>256) N=256;
  N=greedy(B,ei,dim,N,cb,0.05,P,weight);

/* These codes are for testing direct VQ */
/*
  weight=(float *)calloc(ei,sizeof(float));
  for (i=0;i<ei;i++) weight[i] = 1;
  P=(unsigned char *)calloc(ei,sizeof(unsigned char));
  N=20;
  greedy(B,ei,dim,N,cb,0.05,P,weight);
*/

  N=mergecb(B,cb,P,ei,N,thresh,dim);
  gla(B,ei,dim,N,cb,0.03,P,weight);

if (debug) printf("N=%d \n",N);

  free(weight); free(P);
  return N;
}

void getcmap(float *B,unsigned char *cmap,float **cb,int npt,int dim,int N)
{
  int i,j;
  float mindif,dif;

  for (i=0;i<npt;i++)
  {
    mindif = distance2(B,cb[0],dim);
    cmap[i]=0;
    for (j=1;j<N;j++)
    {
      dif = distance2(B,cb[j],dim);
      if (dif<mindif) { cmap[i]=j; mindif=dif; }
    }
    B += dim;
  }
}

int mergecb(float *B,float **cb,unsigned char *P,int npt,int N,float thresh,int dim)
{
  int i,j,newN,*count,l,ei,*count2;
  float **dist,**dist2,**cb2;

  if (N==1) return 1;

  count=(int *)calloc(N,sizeof(int));
  for (l=0;l<npt;l++) count[P[l]]++;

  dist=(float **)fmatrix(N,N);
  ei = N-1;
  for (i=0;i<ei;i++)
  {
    for (j=i+1;j<N;j++)
    {
      dist[i][j] = distance2(cb[i],cb[j],dim);
      dist[j][i] = dist[i][j];
    }
  }

  if (thresh<0)
  {
    cb2 = (float **)fmatrix(N,dim);
    for (i=0;i<N;i++) 
      for (j=0;j<dim;j++) cb2[i][j]=cb[i][j];
    count2=(int *)calloc(N,sizeof(int));
    for (i=0;i<N;i++) count2[i]=count[i];
    dist2=(float **)fmatrix(N,N);
    for (i=0;i<N;i++)
      for (j=0;j<N;j++) dist2[i][j]=dist[i][j];
    if (dim==3) thresh=400;
    else if (dim==1) thresh=800;
    mergecb1(dist2,B,cb2,P,npt,N,&thresh,dim,count2,1);
    free_fmatrix(cb2,N);
    free(count2);
    free_fmatrix(dist2,N);
  }
  printf("thresh %f ",thresh);
  newN=mergecb1(dist,B,cb,P,npt,N,&thresh,dim,count,0);

  free_fmatrix(dist,N);
  free(count);
  return newN;
}

int mergecb1(float **dist,float *B,float **cb,unsigned char *P,int npt,int newN,
    float *thresh,int dim,int *count,int status)
{  
  int i,j,l,mini=0,minj,total,k,ei,endloop;
  float mindist,avgJC,oldJC,maxJ,olddist,thresh2,*cent,ST,*A;
int debug=0;

  ei = newN-1;
  mindist=100000;
  for (i=0;i<ei;i++)
  {
    for (j=i+1;j<newN;j++)
    {
      if (dist[i][j]<mindist)
      {
        mindist=dist[i][j];
        mini=i;
        minj=j;
      }
    }
  }

  if (status==1)
  {
    cent = (float *)calloc(dim,sizeof(float));
    i=0;
    for (l=0;l<npt;l++)
      for (j=0;j<dim;j++) cent[j] += B[i++];
    for (j=0;j<dim;j++) cent[j] /= npt;
    ST=0;
    A=B;
    for (l=0;l<npt;l++) 
    { 
      ST += distance2(A,cent,dim); 
      A += dim; 
    }
    free(cent);

    avgJC = gettotalJC(B,P,newN,cb,dim,npt,ST);
if (debug) 
  printf("N=%d avgJC=%f dist=%f\n",newN-1,avgJC,mindist);         
    oldJC = avgJC;
    maxJ=0;
    olddist=0;
    if (dim==3) thresh2=260;
    else thresh2=500;
  }

  endloop=0;
  while (endloop==0 && newN>1)
  {
    if (mindist>=*thresh) 
    { 
      if (status==1) endloop=1; 
      else break;
    }
    total=count[mini]+count[minj];
    for (k=0;k<dim;k++)
      cb[mini][k] = (count[mini]*cb[mini][k]+count[minj]*cb[minj][k])/total;
    count[mini]=total;
    ei = newN-1;
    for (i=minj;i<ei;i++)
    {
      count[i]=count[i+1];
      for (k=0;k<dim;k++) cb[i][k]=cb[i+1][k]; 
    }
    for (i=minj;i<ei;i++)
    {
      for (j=0;j<minj;j++) dist[i][j]=dist[i+1][j];
    }
    for (j=minj;j<ei;j++)
    {
      for (i=0;i<minj;i++) dist[i][j]=dist[i][j+1];
    }
    for (i=minj;i<ei;i++)
    {
      for (j=minj;j<ei;j++) dist[i][j]=dist[i+1][j+1];
    }

    newN--;

    if (status==1)
    {
      avgJC = gettotalJC(B,P,newN,cb,dim,npt,ST);

      if (oldJC-avgJC>maxJ && mindist>thresh2) 
      {
        maxJ=oldJC-avgJC;
        if (olddist<mindist) thresh2 = (olddist+mindist)/2;
        else thresh2 = olddist-0.01;
      }
if (debug) 
  printf("N=%d avgJC=%f dif=%f dist=%f thresh=%f maxJ=%f \n",newN,avgJC,oldJC-avgJC,
      mindist,thresh2,maxJ);
      oldJC = avgJC;
      olddist = mindist;
    }

    for (j=0;j<newN;j++)
    {
      dist[mini][j] = distance2(cb[mini],cb[j],dim);
      dist[j][mini] = dist[mini][j];
    }
    mindist=100000;
    ei = newN-1;
    for (i=0;i<ei;i++)
    {
      for (j=i+1;j<newN;j++)
      {
        if (dist[i][j]<mindist)
        {
          mindist=dist[i][j];
          mini=i;
          minj=j;
        }
      }
    }
  }
  if (status ==1 ) *thresh = thresh2;
  return newN;
}

int greedy(float *A,int nvec,int ndim,int N,float **codebook,float t,unsigned char *P,
    float *weight)
{
  int iv,in,jn,imax,nsplit,*index2,k,i,retgla,kn;
  float *totalw,*d,**buf, *variance;

  buf=fmatrix(N,ndim);
  d=(float *)calloc(ndim,sizeof(float));
  variance=(float *)calloc(N,sizeof(float));
  totalw=(float *)calloc(N,sizeof(float));
  index2=(int *)calloc(N,sizeof(int));

/* Calculate the initial centroid */
  for (k=0;k<ndim;k++) codebook[0][k]=0.0;
  totalw[0]=0; i=0;
  for (iv=0;iv<nvec;iv++)
  {
    P[iv]= 0;
    totalw[0]+=weight[iv];
    for (k=0;k<ndim;k++) codebook[0][k] += weight[iv]*A[i++];
  }
  for (k=0;k<ndim;k++) codebook[0][k]/=totalw[0];

  in=1;
  while (in<N)
  {
/*  find the maximum variance */
    for (jn=0;jn<in;jn++) 
    { 
      variance[jn]=0; 
      totalw[jn]=0;
      for (k=0;k<ndim;k++) buf[jn][k]=0.0;
    }
    i = 0;
    for (iv=0;iv<nvec;iv++)
    {
      for (k=0;k<ndim;k++) d[k] = codebook[P[iv]][k] - A[i++];
      for (k=0;k<ndim;k++) 
      {
        buf[P[iv]][k] += weight[iv]*sqr(d[k]);
        variance[P[iv]]+= buf[P[iv]][k];
      }
      totalw[P[iv]] += weight[iv];
    }
    for (jn=0;jn<in;jn++) 
    {
      for (k=0;k<ndim;k++) buf[jn][k] = sqrt(buf[jn][k]/totalw[jn]);
    }
    piksrt(in,variance,index2);

/*  split */
    nsplit=in/2+1;
    if ((nsplit+in)>N) nsplit=N-in;
    for (jn=0;jn<nsplit;jn++)
    {
      imax=index2[jn];
      for (k=0;k<ndim;k++) codebook[in+jn][k] = codebook[imax][k] - buf[imax][k]; 
      for (k=0;k<ndim;k++) codebook[imax] [k] = codebook[imax][k] + buf[imax][k];
    }

/*  run gla on the codebook */
    in=in+nsplit;
    retgla=gla(A,nvec,ndim,in,codebook,t,P,weight);

/*  find the code vectors same, remove them and stop */
    if (retgla)
    {
      for (jn=0;jn<in-1;jn++)
      {
        for (kn=jn+1;kn<in;kn++)
        {
          if (distance2(codebook[jn],codebook[kn],ndim)==0)
          {
            for (i=kn;i<in-1;i++) 
              for (k=0;k<ndim;k++) codebook[i][k]=codebook[i+1][k];
            in--;
          }
        }
      }
      break;
    }
  }
  free_fmatrix(buf,N);
  free (d);
  free (index2);
  free(variance);
  free(totalw);
  return in;
}

int gla(float *A,int nvec,int ndim,int N,float **codebook,float t,unsigned char *P,
    float *weight)
{
  int iv,in,i,j,jn,codeword_exist=0,k,l;
  float *totalw,d1,d2,rate,lastmse,mse,*d;

  totalw=(float *)calloc(N,sizeof(float));
  d=(float *)calloc(ndim,sizeof(float));

  for (i=0;i<5;i++)
  {
/*  get the new partition and total distortion using NN */
    mse=0.0; j=0;
    for (iv=0;iv<nvec;iv++)
    {
      for (k=0;k<ndim;k++) d[k] = A[j++]-codebook[0][k];
      d1=0;
      for (k=0;k<ndim;k++) d1 += sqr(d[k]);
      P[iv]=0; 
      for (in=1;in<N;in++)
      {
        d2=0; l=j-ndim;
        for (k=0;k<ndim;k++) 
        {
          d2+=sqr(A[l]-codebook[in][k]); l++;
          if (d2>=d1) break;
        }
        if (d2<d1)  { d1=d2; P[iv]= (unsigned char) in; }
      }
      mse+=d1;
    }

/*  get the new codebook using centroid */
    for (in=0;in<N;in++) 
    {
      totalw[in]=0.0;
      for (k=0;k<ndim;k++) codebook[in][k]=0;
    }
    j = 0;
    for (iv=0;iv<nvec;iv++)
    {
      for (k=0;k<ndim;k++) codebook[P[iv]][k] += weight[iv]*A[j++];
      totalw[P[iv]]+=weight[iv];
    }
    for (in=0;in<N;in++)
    {
      if (totalw[in]>0.0)
      {
        for (k=0;k<ndim;k++) codebook[in][k] /= totalw[in]; 
      }
      else
      {
/*      assign a training vector not in the codebook as code vector */
        codeword_exist=1;
        iv= round ( ((float) rand()) *(nvec-1)/RAND_MAX);
        while (codeword_exist<=2 && codeword_exist>0)
        {
          j = iv*ndim;
          for (k=0;k<ndim;k++) codebook[in][k] = A[j++];
          for (jn=0;jn<N;jn++)
          {
            if (jn!=in)
            {
              for (k=0;k<ndim;k++) d[k]=codebook[jn][k]-codebook[in][k];
              d1=0;
              for (k=0;k<ndim;k++) d1 += sqr(d[k]);
              if (d1==0) break;
            }
          }
          if (jn==N) codeword_exist=0;
          else 
          { 
            iv = round( ((float) rand()) *(nvec-1)/RAND_MAX);
            codeword_exist++;
          }
        }
      }
    }
    if (i>0)
    {
      rate=(lastmse-mse)/lastmse;
      if (rate<t) break;
    }
    lastmse=mse;
  }

  for (in=0;in<N;in++)
  {
    totalw[in]=0.0;
    for (k=0;k<ndim;k++) codebook[in][k]=0;
  }
  j = 0;
  for (iv=0;iv<nvec;iv++)
  {
    for (k=0;k<ndim;k++) codebook[P[iv]][k] += A[j++];
    totalw[P[iv]]+=1.0;
  }
  for (in=0;in<N;in++)
  {
    if (totalw[in]>0)
    {
      for (k=0;k<ndim;k++) codebook[in][k] /= totalw[in];
    }
  }

  free(d);
  free(totalw);
  return codeword_exist; 
}

float pga(float *B,float *A,int ny,int nx,int offset,float *weight,int dim)
{
  int iy,ix,jy,jx,window,j,k,winarea,*index,*index2;
  float *peer,*dif,avg=0.0,*D,D1,D2,**A1,mean1,mean2;
  int J1,J2,nnoise,J;
  float *difdif,difdift;
  int ej,ej2,ey,ex,nx2;

  peer = (float *)calloc(dim,sizeof(float));

  window=2*offset+1;
  winarea=sqr(window);
  nnoise=offset+1;
  A1=(float **) malloc(winarea*sizeof(float *));
  dif=(float *)calloc(winarea,sizeof(float));
  index=(int *)calloc(winarea,sizeof(int));
  D=(float *)calloc(winarea,sizeof(float));
  index2=(int *)calloc(winarea,sizeof(int));
  difdif=(float *)calloc(winarea-1,sizeof(int));

  nx2 = nx+2*offset;
  ej = winarea-1;

  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      j=0;
      ey = iy+window; ex = ix+window;
      for (jy=iy;jy<ey;jy++)
      {
        for (jx=ix;jx<ex;jx++)
        {
          A1[j]=A+LOC(jy,jx,0,nx2,dim);
          dif[j]=distance(B,A1[j],dim);
          j++;
        }
      }
      piksrtS2B(winarea,dif,index);

      for (j=0;j<ej;j++) difdif[j]=dif[j+1]-dif[j];

      difdift = 12.0 *sqrt(dim/3.0);
      J1=0; 
      for (j=nnoise-1;j>=0;j--)
      {
        if (difdif[j]>difdift) { J1=j+1; break; }
      }
      J2=winarea-1;
      for (j=winarea-1-nnoise;j<ej;j++)      
      {
        if (difdif[j]>difdift) { J2=j; break; }
      }
      J=J2-2;

      if (distance2(A1[index[J1]],A1[index[J2]],dim)==0.0)
      {
        for (k=0;k<dim;k++) B[k] = A1[index[J1]][k];
      }
      else 
      {
        for (j=J1;j<=J;j++)
        {
          D1=0; D2=0;
          mean1=0; mean2=0;

          for (k=J1;k<=j;k++) mean1+=dif[k];
          mean1 /= (j-J1+1);
          for (k=J1;k<=j;k++) D1+=sqr(dif[k]-mean1);
 
          for (k=j+1;k<=J2;k++) mean2+=dif[k];
          mean2 /= (J2-j);
          for (k=j+1;k<=J2;k++) D2+=sqr(dif[k]-mean2);

          D[j-J1] = (D1+D2) / sqr(mean2-mean1);        
        }

        piksrtS2B(J-J1+1,D,index2);
        *weight = dif[index2[0]+J1]-dif[J1];
        avg += (*weight);

        for (k=0;k<dim;k++) peer[k]=0;
        ej2 = index2[0]+J1;
        for (j=J1;j<=ej2;j++)
        {
          for (k=0;k<dim;k++) peer[k] += A1[index[j]][k];
        }
        for (k=0;k<dim;k++) B[k] = peer[k]/(index2[0]+1);
      }
      B += dim;
      weight ++;
    }
  }
  avg = avg/(ny*nx);
  free(dif);
  free(index);
  free(index2);
  free(difdif);
  free(D);
  free(A1);
  free(peer);

  return avg;
}

void pgamap(unsigned char *cmap,int ny,int nx,int offset,int N)
{
  int iy,ix,ny2,nx2,imgsize2,jy,jx,nnoise,i,l,l1,ey,ex;
  int window,count,*count1,*index;
  unsigned char *cmap0;

  ny2 = ny+2*offset; nx2 = nx+2*offset;
  imgsize2 = ny2*nx2;
  cmap0 = (unsigned char *) calloc (imgsize2,sizeof(unsigned char));
  extendbounduc(cmap,cmap0,ny,nx,offset,1);
  nnoise = 2;
  window = 2*offset+1;
  count1 = (int *)calloc(N,sizeof(int));
  index = (int *)calloc(N,sizeof(int));
  l=0;
  for (iy=0;iy<ny;iy++)
  {
    for (ix=0;ix<nx;ix++)
    {
      ey = iy+window; ex = ix+window;
      count=0;
      for (jy=iy;jy<ey;jy++)
      {
        for (jx=ix;jx<ex;jx++)
        {
          l1=LOC2(jy,jx,nx2);
          if (cmap0[l1]==cmap[l]) count++;
        }
      }
      if (count<=nnoise)
      {
        for (i=0;i<N;i++) count1[i]=0;
        for (jy=iy;jy<ey;jy++)
        {
          for (jx=ix;jx<ex;jx++)
          {
            l1=LOC2(jy,jx,nx2);
            count1[cmap0[l1]] ++;
          }
        }
        piksrtint(N,count1,index);
        cmap[l]=index[0];
      }
      l++;
    }
  }
  free(index);
  free(count1);
  free(cmap0);
}

