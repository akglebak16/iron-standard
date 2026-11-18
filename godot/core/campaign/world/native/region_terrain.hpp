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
inline float river_x(float y) {
  const float bend = y-std::clamp(y,690.f,750.f);
  return 1280+92*std::sin(bend/157)+24*std::sin(bend/55);
}

inline float river_width(float y) {
  float outlet = std::clamp((y-910)/150,0.f,1.f);
  return 5.5f+y*.012f+3*terrain_noise(91,y,116,552)+18*outlet*outlet;
}

// Stable regional layout, variable watershed slopes, woodland and saddle.
// Construct once per job. All consumers sample identical world coordinates.
struct RegionShape {
  unsigned seed;
  float scale, strength, cohesion, pass, shift, phase;
  float west_detour=0, east_detour=0;
  RegionShape(unsigned value=188,float macro_scale=1,float relief_strength=1,float forest_cohesion=1)
    : seed(value),scale(std::clamp(macro_scale,.7f,1.4f)),
      strength(std::clamp(relief_strength,.6f,1.4f)),cohesion(std::clamp(forest_cohesion,.7f,1.4f)),
      pass(1670+250*terrain_hash(5,7,value)),shift(140*(terrain_hash(3,11,value)-.5f)),
      phase(6.28f*terrain_hash(7,1,value)) {}

  float ridge_axis(float x) const {
    return 183+shift+.21f*(x-1240)+95*std::sin((x-1260)/(255*scale)+phase*.42f);
  }
  float massif(float x,float y) const {
    float axis=ridge_axis(x), d=(y-axis)/(152*scale);
    float spur=(y-axis-105-58*std::sin(x/173+phase))/(120*scale);
    float saddle=(x-pass)/100;
    return std::max(std::exp(-d*d),.57f*std::exp(-spur*spur))*
      std::clamp((x-1090)/385,0.f,1.f)*(1-.91f*std::exp(-saddle*saddle));
  }
  float relief(float x,float y) const {
    float along=x+.83f*y;
    float foot=(y-ridge_axis(x)-205)/210;
    float folds=.5f+.5f*std::cos(along/(81*scale)+phase+1.8f*terrain_noise(x,y,230,seed));
    float hills=(.10f+.22f*std::exp(-foot*foot))*folds*folds;
    float bank=std::min(1.f,std::abs(x-river_x(y))/165);
    float upland=.47f*massif(x,y)+hills+.13f*terrain_noise(x,y,210,seed^47);
    return .05f+.12f*std::clamp(1-y/1250,0.f,1.f)+strength*upland*bank*bank*(3-2*bank);
  }
  float woodland(float x,float y) const {
    float warp=122*terrain_noise(x,y,295,seed^911);
    // The regional woodland survives every variant. Its boundary and
    // clearings move within the same drainage basin.
    float along=(x-640-110*std::cos(phase))/(440*cohesion);
    float across=(y-358+.34f*(x-640)-shift*.62f)/(155*cohesion);
    float core=std::exp(-along*along-across*across);
    float apron=(y-ridge_axis(x)-83)/115;
    float treeline=std::exp(-apron*apron)*std::clamp((x-1410)/490,0.f,1.f);
    float growth=.68f*terrain_noise(x+warp,y-.24f*x,295*cohesion,seed^184)+
      .32f*terrain_noise(x,y,98,seed^273);
    return std::max(growth+.12f*massif(x,y),.35f+.37f*core+.20f*growth+.095f*treeline);
  }
};
} // namespace iron::overworld