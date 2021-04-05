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

#include "ParticleUtility.hlsli"

StructuredBuffer<ParticleVertex> g_VertexBuffer : register( t0 );
ByteAddressBuffer g_VertexCount : register(t1);
RWStructuredBuffer<uint> g_SortBuffer : register(u0);
RWByteAddressBuffer g_DrawIndirectArgs : register(u1);

groupshared uint gs_SortKeys[2048];

void FillSortKey( uint GroupStart, uint Offset, uint VertexCount )
{
    if (GroupStart + Offset >= VertexCount)
    {
        gs_SortKeys[Offset] = 0;		// Z = 0 will sort to the end of the list (back to front)
        return;
    }

    uint VertexIdx = GroupStart + Offset;
    ParticleVertex Sprite = g_VertexBuffer[VertexIdx];

    // Frustum cull before adding this particle to list of visible particles (for rendering)
    float4 HPos = mul( gViewProj, float4(Sprite.Position, 1) );
    float Height = Sprite.Size * gVertCotangent;
    float Width = Height * gAspectRatio;
    float3 Extent = abs(HPos.xyz) - float3(Width, Height, 0);

    // Frustum cull rather than sorting and rendering every particle
    if (max(max(0.0, Extent.x), max(Extent.y, Extent.z)) <= HPos.w)
    {
        // Encode depth as 14 bits because we only need [0, 1] at half precision.
        // This gives us 18-bit indices--up to 256k particles.
        float Depth = saturate(HPos.w * gRcpFarZ);
        gs_SortKeys[Offset] = f32tof16(Depth) << 18 | VertexIdx;

        // Increment the visible instance counter
        g_DrawIndirectArgs.InterlockedAdd(4, 1);
    }
    else
    {
        // Cull particle index by sorting it to the end and not incrementing the visible instance counter
        gs_SortKeys[Offset] = 0;
    }
}

[RootSignature(Particle_RootSig)]
[numthreads(1024, 1, 1)]
void main( uint3 DTid : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint GI : SV_GroupIndex )
{
    uint VisibleParticles = g_VertexCount.Load(0);

    uint GroupStart = Gid.x * 2048;

    if (GroupStart > VisibleParticles)
    {
        g_SortBuffer[GroupStart + GI] = 0;
        g_SortBuffer[GroupStart + GI + 1024] = 0;
        return;
    }

    FillSortKey(GroupStart, GI, VisibleParticles);
    FillSortKey(GroupStart, GI + 1024, VisibleParticles);

    GroupMemoryBarrierWithGroupSync();

    uint k;

    [unroll]
    for (k = 2; k <= 2048; k *= 2)
    {
        //[unroll]
        for (uint j = k / 2; j > 0; j /= 2)
        {
            uint Index1 = InsertZeroBit(GI, j);
            uint Index2 = Index1 ^ (k == j * 2 ? k - 1 : j);

            uint A = gs_SortKeys[Index1];
            uint B = gs_SortKeys[Index2];

            if (A < B)
            {
                gs_SortKeys[Index1] = B;
                gs_SortKeys[Index2] = A;
            }

            GroupMemoryBarrierWithGroupSync();
        }
    }

    g_SortBuffer[GroupStart + GI] = gs_SortKeys[GI];
    g_SortBuffer[GroupStart + GI + 1024] = gs_SortKeys[GI + 1024];
}
