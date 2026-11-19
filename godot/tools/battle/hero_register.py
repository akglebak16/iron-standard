# Face registration of hero heads, hair and beards to the bare head (#232): for each part the scale and
# offset that lay its face over the bare head's face. Usage: python3 hero_register.py <parts dir> <out json>
# (parts: torso/head/hair PNGs named h-<helm>.png, x-<hair>.png, as cut by render_heraldic_hero.cjs).
import json,colorsys
import numpy as np
from PIL import Image
import sys
P=sys.argv[1].rstrip('/')+'/'
def load(n): return np.array(Image.open(P+n+'.png').convert('RGBA')).astype(float)
def skin(px):
  r,g,b,a=[px[...,i]/255 for i in range(4)]
  mx=np.maximum(np.maximum(r,g),b); mn=np.minimum(np.minimum(r,g),b); s=np.where(mx>0,(mx-mn)/np.maximum(mx,1e-6),0)
  h=np.where(mx==r,((g-b)/np.maximum(mx-mn,1e-6))%6,np.where(mx==g,(b-r)/np.maximum(mx-mn,1e-6)+2,(r-g)/np.maximum(mx-mn,1e-6)+4))/6%1
  return (a>.5)&(h>.04)&(h<.11)&(s>.18)&(s<.56)&(mx>.62)
ref=load('h-none'); R=skin(ref); H,W=R.shape
from scipy.ndimage import binary_dilation,binary_erosion
LR=ref[...,:3].mean(2)*(ref[...,3]>128)
def score(mask,s,dx,dy,L=None):
  ys,xs=np.nonzero(mask)
  X=np.round(xs*s+dx).astype(int);Y=np.round(ys*s+dy).astype(int)
  ok=(X>=0)&(Y>=0)&(X<W)&(Y<H)
  d=np.full(len(xs),255.);d[ok]=np.abs(LR[Y[ok],X[ok]]-L[ys[ok],xs[ok]])
  return -d.mean()
def register(n):
  px=load(n); m0=skin(px); m=binary_dilation(m0,iterations=3)&binary_erosion(binary_dilation(m0,iterations=12),iterations=12) if False else None
  from scipy.ndimage import binary_fill_holes
  m=binary_erosion(binary_fill_holes(binary_dilation(m0,iterations=3)),iterations=2); L=px[...,:3].mean(2)
  sub=np.zeros_like(m);sub[::3,::3]=True
  if m0.sum()<500: return None
  ys,xs=np.nonzero(m0); ry,rx=np.nonzero(R)
  best=(-1e9,)
  for s in np.arange(.9,1.11,.02):
    cx=0; cy=0
    for dx in range(-80,81,3):
      for dy in range(-170,60,3):
        sc=score(m&sub,s,cx+dx,cy+dy,L)
        if sc>best[0]: best=(sc,s,cx+dx,cy+dy)
  sc,s,dx,dy=best; b=best
  for s2 in np.arange(s-.02,s+.021,.005):
    for ddx in np.arange(-3,3.1,1):
      for ddy in np.arange(-3,3.1,1):
        sc=score(m,s2,dx+ddx,dy+ddy,L)
        if sc>b[0]: b=(sc,s2,dx+ddx,dy+ddy)
  return [round(float(v),3) for v in b[1:]]+[round(float(b[0]),3)]
out={'h-none':[1,0,0,1]}
import sys
names=['h-nasal','h-spectacle','h-cap','h-hood','h-crest','h-kettle','h-furcap','h-pointed','h-coif','h-turban','h-turbanm','x-hair','x-beard1','x-beard2','x-stache','h-great','h-flat','h-mask']
for n in names:
  out[n]=register(n); print(n,out[n],flush=True)
json.dump(out,open(sys.argv[2],'w'))
