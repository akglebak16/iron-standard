#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace iron::overworld {
inline float terrain_hash(int x, int y, unsigned seed) {
  uint32_t h = uint32_t(x)*0x9e3779b9u ^ uint32_t(y)*0x85ebca6bu ^ seed;
  h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu;
  return float((h ^ (h >> 16)) >> 8) / 16777216.f;
}
inline float terrain_noise(float x, float y, float scale, unsigned seed) {
  x/=scale; y/=scale;
  int i=int(std::floor(x)), j=int(std::floor(y));
  float u=x-i, v=y-j;
  u=u*u*(3-2*u); v=v*v*(3-2*v);
  auto row=[&](int k){return (1-u)*terrain_hash(i,k,seed)+u*terrain_hash(i+1,k,seed);};
  return (1-v)*row(j)+v*row(j+1);
}
inline float ridge_axis(float x) {
  return 235 + .19f*(x-1300) + 70*std::sin((x-1250)/210);
}
inline float massif(float x,float y) {
  float d=(y-ridge_axis(x))/195;
  float saddle=(x-1750)/70;
  return std::exp(-d*d)*std::clamp((x-1080)/440,0.f,1.f)*
         (1-.78f*std::exp(-saddle*saddle));
}
inline float relief(float x,float y) {
  return .55f*massif(x,y)+.30f*terrain_noise(x,y,300,47)
       + .18f*terrain_noise(x,y,138,91)+.08f*terrain_noise(x,y,63,17);
}
inline float woodland(float x,float y) {
  return .65f*terrain_noise(x,y,225,184)+.35f*terrain_noise(x,y,86,273)
       + .15f*massif(x,y);
}
} // namespace iron::overworld
