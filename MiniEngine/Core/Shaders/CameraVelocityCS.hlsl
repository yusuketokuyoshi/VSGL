//
// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
// Developed by Minigraph
//
// Author:  James Stanard 
//

#include "CommonRS.hlsli"
#include "PixelPacking_Velocity.hlsli"

// We can use the original depth buffer or a linearized one.  In this case, we use linear Z because
// we have discarded the 32-bit depth buffer but still retain a 16-bit linear buffer (previously
// used by SSAO.)  Note that hyperbolic Z is reversed by default (TBD) for increased precision, so
// its Z=0 maps to the far plane.  With linear Z, Z=0 maps to the eye position.  Both extend to Z=1.
#define USE_LINEAR_Z

Texture2D<float> DepthBuffer : register(t0);
RWTexture2D<packed_velocity_t> VelocityBuffer : register(u0);

cbuffer CBuffer : register(b1)
{
    matrix CurToPrevXForm;
}

[RootSignature(Common_RootSig)]
[numthreads( 8, 8, 1 )]
void main( uint3 DTid : SV_DispatchThreadID )
{
    uint2 st = DTid.xy;
    float2 CurPixel = st + 0.5;
    float Depth = DepthBuffer[st];
#ifdef USE_LINEAR_Z
    float4 HPos = float4( CurPixel * Depth, 1.0, Depth );
#else
    float4 HPos = float4( CurPixel, Depth, 1.0 );
#endif
    float4 PrevHPos = mul( CurToPrevXForm, HPos );

    PrevHPos.xyz /= PrevHPos.w;

#ifdef USE_LINEAR_Z
    PrevHPos.z = PrevHPos.w;
#endif

    VelocityBuffer[st] = PackVelocity(PrevHPos.xyz - float3(CurPixel, Depth));
}
