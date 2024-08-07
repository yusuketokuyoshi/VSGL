#include "GraphicsCore.h"
#include "BufferManager.h"
#include "CommandContext.h"
#include "Renderer.h"
#include "MyRenderer.h"
#include "Scene.h"
#include "Shaders/VSGLGenerationSetting.h"

// Compiled shaders
#include "CompiledShaders/DepthVS.h"
#include "CompiledShaders/DepthCutoutVS.h"
#include "CompiledShaders/DepthCutoutPS.h"
#include "CompiledShaders/ReflectiveShadowMapVS.h"
#include "CompiledShaders/ReflectiveShadowMapPS.h"
#include "CompiledShaders/ReflectiveShadowMapCutoutPS.h"
#include "CompiledShaders/VSGLGenerationDiffuseCS.h"
#include "CompiledShaders/VSGLGenerationSpecularCS.h"
#include "CompiledShaders/LightingVS.h"
#include "CompiledShaders/LightingPS.h"
#include "CompiledShaders/LightingCutoutPS.h"

namespace MyRenderer
{
    enum GFX_ROOT_INDEX {
        ROOT_INDEX_VS_CBV,
        ROOT_INDEX_PS_SRV0,
        ROOT_INDEX_PS_SRV1,
        ROOT_INDEX_PS_CBV0,
        ROOT_INDEX_PS_CBV1,
    };
    enum VSGL_ROOT_INDEX {
        VSGL_ROOT_INDEX_CBV,
        VSGL_ROOT_INDEX_CONSTANTS,
        VSGL_ROOT_INDEX_SRV,
        VSGL_ROOT_INDEX_UAV,
    };

    static DepthBuffer s_shadowMap;
    static DepthBuffer s_rsmDepthBuffer;
    static ColorBuffer s_rsmNormalBuffer;
    static ColorBuffer s_rsmDiffuseBuffer;
    static ColorBuffer s_rsmSpecularBuffer;
    static StructuredBuffer s_sgLightBuffer;
    static DescriptorHandle s_lightingDescriptorTable;

    static RootSignature s_depthRootSig;
    static RootSignature s_rsmRootSig;
    static RootSignature s_lightingRootSig;
    static RootSignature s_vsglRootSig;
    static GraphicsPSO s_depthPSO = { L"s_depthPSO" };
    static GraphicsPSO s_depthCutoutPSO = { L"s_depthCutoutPSO" };
    static GraphicsPSO s_shadowMapPSO = { L"s_shadowMapPSO" };
    static GraphicsPSO s_shadowMapCutoutPSO = { L"s_shadowMapCutoutPSO" };
    static GraphicsPSO s_reflectiveShadowMapPSO = { L"s_reflectiveShadowMapPSO" };
    static GraphicsPSO s_reflectiveShadowMapCutoutPSO = { L"s_reflectiveShadowMapCutoutPSO" };
    static GraphicsPSO s_lightingPSO = { L"s_lightingPSO" };
    static GraphicsPSO s_lightingCutoutPSO = { L"s_lightingCutoutPSO" };
    static ComputePSO s_vsglGenerationDiffusePSO = { L"s_vsglGenerationDiffusePSO" };
    static ComputePSO s_vsglGenerationSpecularPSO = { L"s_vsglGenerationSpecularPSO" };

    static void ReflectiveShadowMapPass(GraphicsContext& context, const Scene& scene);
    static void ShadowMapPass(GraphicsContext& context, const Scene& scene);
    static void VSGLGenerationPass(ComputeContext& context, const Math::Camera& spotLight, const float lightIntensity);
    static void DepthPass(GraphicsContext& context, const Scene& scene);
    static void LightingPass(GraphicsContext& context, const Scene& scene);
    static void Draw(GraphicsContext& context, const ModelH3D& model);
    static void DrawDepth(GraphicsContext& context, const ModelH3D& model);
}

void MyRenderer::Initialize()
{
    s_shadowMap.Create(L"s_shadowMap", 2048, 2048, DXGI_FORMAT_D32_FLOAT);
    s_rsmDepthBuffer.Create(L"s_rsmDepthBuffer", RSM_WIDTH, RSM_WIDTH, DXGI_FORMAT_D32_FLOAT);
    s_rsmNormalBuffer.Create(L"s_rsmNormalBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R16G16_SNORM);
    s_rsmDiffuseBuffer.Create(L"s_rsmDiffuseBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R10G10B10A2_UNORM);
    s_rsmSpecularBuffer.Create(L"s_rsmSpecularBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R8G8B8A8_UNORM);
    s_sgLightBuffer.Create(L"s_sgLightBuffer", 2, sizeof(uint32_t) * 12);

    // Allocate a descriptor table for forward rendering
    constexpr uint_fast8_t LIGHTING_DESCRIPTOR_TABLE_SIZE = 1;
    s_lightingDescriptorTable = Renderer::s_TextureHeap.Alloc(LIGHTING_DESCRIPTOR_TABLE_SIZE);
    Graphics::g_Device->CopyDescriptorsSimple(1, s_lightingDescriptorTable, s_shadowMap.GetDepthSRV(), D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

    SamplerDesc shadowSamplerDesc;
    shadowSamplerDesc.Filter = D3D12_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT;
    shadowSamplerDesc.ComparisonFunc = D3D12_COMPARISON_FUNC_GREATER;
    shadowSamplerDesc.SetTextureAddressMode(D3D12_TEXTURE_ADDRESS_MODE_BORDER);

    SamplerDesc samplerAnisotropicWrapDesc = Graphics::SamplerAnisoWrapDesc;
    samplerAnisotropicWrapDesc.MaxAnisotropy = 16;

    s_depthRootSig.Reset(2, 1);
    s_depthRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
    s_depthRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::CUTOUT_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
    s_depthRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
    s_depthRootSig.Finalize(L"s_depthRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

    s_rsmRootSig.Reset(2, 1);
    s_rsmRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
    s_rsmRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::MODEL_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
    s_rsmRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
    s_rsmRootSig.Finalize(L"s_rsmRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

    s_lightingRootSig.Reset(5, 2);
    s_lightingRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
    s_lightingRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::MODEL_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig[ROOT_INDEX_PS_SRV1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, Scene::MODEL_SRV_COUNT, LIGHTING_DESCRIPTOR_TABLE_SIZE, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig[ROOT_INDEX_PS_CBV0].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig[ROOT_INDEX_PS_CBV1].InitAsConstantBuffer(1, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig.InitStaticSampler(1, shadowSamplerDesc, D3D12_SHADER_VISIBILITY_PIXEL);
    s_lightingRootSig.Finalize(L"s_lightingRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

    s_vsglRootSig.Reset(4);
    s_vsglRootSig[VSGL_ROOT_INDEX_CBV].InitAsConstantBuffer(0);
    s_vsglRootSig[VSGL_ROOT_INDEX_CONSTANTS].InitAsConstants(1, 1);
    s_vsglRootSig[VSGL_ROOT_INDEX_SRV].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 3);
    s_vsglRootSig[VSGL_ROOT_INDEX_UAV].InitAsBufferUAV(0);
    s_vsglRootSig.Finalize(L"s_vsglRootSig");

    s_vsglGenerationDiffusePSO.SetRootSignature(s_vsglRootSig);
    s_vsglGenerationDiffusePSO.SetComputeShader(g_pVSGLGenerationDiffuseCS, sizeof(g_pVSGLGenerationDiffuseCS));
    s_vsglGenerationDiffusePSO.Finalize();
    s_vsglGenerationSpecularPSO.SetRootSignature(s_vsglRootSig);
    s_vsglGenerationSpecularPSO.SetComputeShader(g_pVSGLGenerationSpecularCS, sizeof(g_pVSGLGenerationSpecularCS));
    s_vsglGenerationSpecularPSO.Finalize();

    {
        constexpr D3D12_INPUT_ELEMENT_DESC DEPTH_ELEMENT_DESCS[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
        };
        constexpr D3D12_INPUT_ELEMENT_DESC CUTOUT_ELEMENT_DESCS[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
        };

        s_depthPSO.SetRootSignature(s_depthRootSig);
        s_depthPSO.SetRasterizerState(Graphics::RasterizerDefault);
        s_depthPSO.SetBlendState(Graphics::BlendNoColorWrite);
        s_depthPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_depthPSO.SetInputLayout(_countof(DEPTH_ELEMENT_DESCS), DEPTH_ELEMENT_DESCS);
        s_depthPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_depthPSO.SetRenderTargetFormats(0, nullptr, Graphics::g_SceneDepthBuffer.GetFormat());
        s_depthPSO.SetVertexShader(g_pDepthVS, sizeof(g_pDepthVS));
        s_depthPSO.Finalize();

        s_depthCutoutPSO.SetRootSignature(s_depthRootSig);
        s_depthCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
        s_depthCutoutPSO.SetBlendState(Graphics::BlendNoColorWrite);
        s_depthCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_depthCutoutPSO.SetInputLayout(_countof(CUTOUT_ELEMENT_DESCS), CUTOUT_ELEMENT_DESCS);
        s_depthCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_depthCutoutPSO.SetRenderTargetFormats(0, nullptr, Graphics::g_SceneDepthBuffer.GetFormat());
        s_depthCutoutPSO.SetVertexShader(g_pDepthCutoutVS, sizeof(g_pDepthCutoutVS));
        s_depthCutoutPSO.SetPixelShader(g_pDepthCutoutPS, sizeof(g_pDepthCutoutPS));
        s_depthCutoutPSO.Finalize();

        s_shadowMapPSO.SetRootSignature(s_depthRootSig);
        s_shadowMapPSO.SetRasterizerState(Graphics::RasterizerShadow);
        s_shadowMapPSO.SetBlendState(Graphics::BlendNoColorWrite);
        s_shadowMapPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_shadowMapPSO.SetInputLayout(_countof(DEPTH_ELEMENT_DESCS), DEPTH_ELEMENT_DESCS);
        s_shadowMapPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_shadowMapPSO.SetRenderTargetFormats(0, nullptr, s_shadowMap.GetFormat());
        s_shadowMapPSO.SetVertexShader(g_pDepthVS, sizeof(g_pDepthVS));
        s_shadowMapPSO.Finalize();

        s_shadowMapCutoutPSO.SetRootSignature(s_depthRootSig);
        s_shadowMapCutoutPSO.SetRasterizerState(Graphics::RasterizerShadowTwoSided);
        s_shadowMapCutoutPSO.SetBlendState(Graphics::BlendNoColorWrite);
        s_shadowMapCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_shadowMapCutoutPSO.SetInputLayout(_countof(CUTOUT_ELEMENT_DESCS), CUTOUT_ELEMENT_DESCS);
        s_shadowMapCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_shadowMapCutoutPSO.SetRenderTargetFormats(0, nullptr, s_shadowMap.GetFormat());
        s_shadowMapCutoutPSO.SetVertexShader(g_pDepthCutoutVS, sizeof(g_pDepthCutoutVS));
        s_shadowMapCutoutPSO.SetPixelShader(g_pDepthCutoutPS, sizeof(g_pDepthCutoutPS));
        s_shadowMapCutoutPSO.Finalize();
    }
    {
        constexpr D3D12_INPUT_ELEMENT_DESC ELEMENT_DESCS[] = {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            { "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            { "TANGENT", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 },
            { "BITANGENT", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0 }
        };
        const DXGI_FORMAT rsmFormats[] = { s_rsmNormalBuffer.GetFormat(), s_rsmDiffuseBuffer.GetFormat(), s_rsmSpecularBuffer.GetFormat() };

        s_reflectiveShadowMapPSO.SetRootSignature(s_rsmRootSig);
        s_reflectiveShadowMapPSO.SetRasterizerState(Graphics::RasterizerDefault);
        s_reflectiveShadowMapPSO.SetInputLayout(_countof(ELEMENT_DESCS), ELEMENT_DESCS);
        s_reflectiveShadowMapPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_reflectiveShadowMapPSO.SetBlendState(Graphics::BlendDisable);
        s_reflectiveShadowMapPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_reflectiveShadowMapPSO.SetRenderTargetFormats(_countof(rsmFormats), rsmFormats, s_rsmDepthBuffer.GetFormat());
        s_reflectiveShadowMapPSO.SetVertexShader(g_pReflectiveShadowMapVS, sizeof(g_pReflectiveShadowMapVS));
        s_reflectiveShadowMapPSO.SetPixelShader(g_pReflectiveShadowMapPS, sizeof(g_pReflectiveShadowMapPS));
        s_reflectiveShadowMapPSO.Finalize();

        s_reflectiveShadowMapCutoutPSO.SetRootSignature(s_rsmRootSig);
        s_reflectiveShadowMapCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
        s_reflectiveShadowMapCutoutPSO.SetInputLayout(_countof(ELEMENT_DESCS), ELEMENT_DESCS);
        s_reflectiveShadowMapCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_reflectiveShadowMapCutoutPSO.SetBlendState(Graphics::BlendDisable);
        s_reflectiveShadowMapCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
        s_reflectiveShadowMapCutoutPSO.SetRenderTargetFormats(_countof(rsmFormats), rsmFormats, s_rsmDepthBuffer.GetFormat());
        s_reflectiveShadowMapCutoutPSO.SetVertexShader(g_pReflectiveShadowMapVS, sizeof(g_pReflectiveShadowMapVS));
        s_reflectiveShadowMapCutoutPSO.SetPixelShader(g_pReflectiveShadowMapCutoutPS, sizeof(g_pReflectiveShadowMapCutoutPS));
        s_reflectiveShadowMapCutoutPSO.Finalize();

        s_lightingPSO.SetRootSignature(s_lightingRootSig);
        s_lightingPSO.SetRasterizerState(Graphics::RasterizerDefault);
        s_lightingPSO.SetInputLayout(_countof(ELEMENT_DESCS), ELEMENT_DESCS);
        s_lightingPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_lightingPSO.SetBlendState(Graphics::BlendDisable);
        s_lightingPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
        s_lightingPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
        s_lightingPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
        s_lightingPSO.SetPixelShader(g_pLightingPS, sizeof(g_pLightingPS));
        s_lightingPSO.Finalize();

        s_lightingCutoutPSO.SetRootSignature(s_lightingRootSig);
        s_lightingCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
        s_lightingCutoutPSO.SetInputLayout(_countof(ELEMENT_DESCS), ELEMENT_DESCS);
        s_lightingCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
        s_lightingCutoutPSO.SetBlendState(Graphics::BlendDisable);
        s_lightingCutoutPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
        s_lightingCutoutPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
        s_lightingCutoutPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
        s_lightingCutoutPSO.SetPixelShader(g_pLightingCutoutPS, sizeof(g_pLightingCutoutPS));
        s_lightingCutoutPSO.Finalize();
    }
}

void MyRenderer::Shutdown()
{
    s_shadowMap.Destroy();
    s_rsmDepthBuffer.Destroy();
    s_rsmNormalBuffer.Destroy();
    s_rsmDiffuseBuffer.Destroy();
    s_rsmSpecularBuffer.Destroy();
    s_sgLightBuffer.Destroy();
}

void MyRenderer::Render(GraphicsContext& context, const Scene& scene)
{
    // Initialize rendering buffers.
    context.TransitionResource(s_rsmDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_WRITE);
    context.TransitionResource(s_rsmNormalBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
    context.TransitionResource(s_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
    context.TransitionResource(s_rsmSpecularBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
    context.TransitionResource(s_shadowMap, D3D12_RESOURCE_STATE_DEPTH_WRITE);
    context.TransitionResource(s_sgLightBuffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    context.TransitionResource(Graphics::g_SceneDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_WRITE);
    context.TransitionResource(Graphics::g_SceneColorBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
    context.ClearDepth(s_rsmDepthBuffer);
    context.ClearColor(s_rsmDiffuseBuffer);
    context.ClearColor(s_rsmSpecularBuffer);
    context.ClearDepth(s_shadowMap);
    context.ClearDepth(Graphics::g_SceneDepthBuffer);
    context.ClearColor(Graphics::g_SceneColorBuffer);

    ReflectiveShadowMapPass(context, scene);
    ShadowMapPass(context, scene);
    VSGLGenerationPass(context.GetComputeContext(), scene.m_spotlight, scene.m_spotlightIntensity);
    DepthPass(context, scene);
    LightingPass(context, scene);
}

void MyRenderer::ReflectiveShadowMapPass(GraphicsContext& context, const Scene& scene)
{
    const ScopedTimer profile(L"Reflective Shadow Map", context);

    const XMMATRIX& viewProj = scene.m_spotlight.GetViewProjMatrix();
    const D3D12_CPU_DESCRIPTOR_HANDLE rtvs[] = {
        s_rsmNormalBuffer.GetRTV(),
        s_rsmDiffuseBuffer.GetRTV(),
        s_rsmSpecularBuffer.GetRTV()
    };

    context.SetRootSignature(s_rsmRootSig);
    context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
    context.SetViewportAndScissor(0, 0, s_rsmDepthBuffer.GetWidth(), s_rsmDepthBuffer.GetHeight());
    context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
    context.SetRenderTargets(_countof(rtvs), rtvs, s_rsmDepthBuffer.GetDSV());
    context.SetPipelineState(s_reflectiveShadowMapPSO);
    Draw(context, scene.m_model);

    if (scene.m_modelCutout.m_Header.meshCount > 0)
    {
        context.SetPipelineState(s_reflectiveShadowMapCutoutPSO);
        Draw(context, scene.m_modelCutout);
    }

    context.BeginResourceTransition(s_rsmDepthBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.BeginResourceTransition(s_rsmNormalBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.BeginResourceTransition(s_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.BeginResourceTransition(s_rsmSpecularBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
}

void MyRenderer::ShadowMapPass(GraphicsContext& context, const Scene& scene)
{
    const ScopedTimer profile(L"Shadow Map", context);

    const XMMATRIX& viewProj = scene.m_spotlight.GetViewProjMatrix();

    context.SetRootSignature(s_depthRootSig);
    context.SetViewportAndScissor(0, 0, s_shadowMap.GetWidth(), s_shadowMap.GetHeight());
    context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
    context.SetDepthStencilTarget(s_shadowMap.GetDSV());
    context.SetPipelineState(s_shadowMapPSO);
    DrawDepth(context, scene.m_model);

    if (scene.m_modelCutout.m_Header.meshCount > 0)
    {
        context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
        context.SetPipelineState(s_shadowMapCutoutPSO);
        Draw(context, scene.m_modelCutout);
    }

    context.BeginResourceTransition(s_shadowMap, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
}

void MyRenderer::DepthPass(GraphicsContext& context, const Scene& scene)
{
    const ScopedTimer profile(L"Depth", context);

    const XMMATRIX& viewProj = scene.m_camera.GetViewProjMatrix();

    context.SetRootSignature(s_depthRootSig);
    context.SetViewportAndScissor(0, 0, Graphics::g_SceneDepthBuffer.GetWidth(), Graphics::g_SceneDepthBuffer.GetHeight());
    context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
    context.SetDepthStencilTarget(Graphics::g_SceneDepthBuffer.GetDSV());
    context.SetPipelineState(s_depthPSO);
    DrawDepth(context, scene.m_model);

    if (scene.m_modelCutout.m_Header.meshCount > 0)
    {
        context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
        context.SetPipelineState(s_depthCutoutPSO);
        Draw(context, scene.m_modelCutout);
    }
}

void MyRenderer::LightingPass(GraphicsContext& context, const Scene& scene)
{
    const ScopedTimer profile(L"Lighting", context);

    context.TransitionResource(Graphics::g_SceneDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_READ);
    context.TransitionResource(s_shadowMap, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
    context.TransitionResource(s_sgLightBuffer, D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);

    const XMMATRIX& viewProj = scene.m_camera.GetViewProjMatrix();

    __declspec(align(16)) struct {
        XMMATRIX lightViewProj;
        XMVECTOR cameraPosition;
        XMFLOAT3 lightPosition;
        float    lightIntensity;
    } constants;

    constants.lightViewProj = scene.m_spotlight.GetViewProjMatrix();
    constants.cameraPosition = scene.m_camera.GetPosition();
    XMStoreFloat3(&constants.lightPosition, scene.m_spotlight.GetPosition());
    constants.lightIntensity = scene.m_spotlightIntensity;

    context.SetRootSignature(s_lightingRootSig);
    context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
    context.SetViewportAndScissor(0, 0, Graphics::g_SceneDepthBuffer.GetWidth(), Graphics::g_SceneDepthBuffer.GetHeight());
    context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
    context.SetDynamicConstantBufferView(ROOT_INDEX_PS_CBV0, sizeof(constants), &constants);
    context.SetConstantBuffer(ROOT_INDEX_PS_CBV1, s_sgLightBuffer.RootConstantBufferView());
    context.SetDescriptorTable(ROOT_INDEX_PS_SRV1, s_lightingDescriptorTable);
    context.SetRenderTarget(Graphics::g_SceneColorBuffer.GetRTV(), Graphics::g_SceneDepthBuffer.GetDSV_DepthReadOnly());
    context.SetPipelineState(s_lightingPSO);
    Draw(context, scene.m_model);

    if (scene.m_modelCutout.m_Header.meshCount > 0)
    {
        context.SetPipelineState(s_lightingCutoutPSO);
        Draw(context, scene.m_modelCutout);
    }
}

// Generate a diffuse VSGL and specular VSGL from an RSM.
void MyRenderer::VSGLGenerationPass(ComputeContext& context, const Math::Camera& spotLight, const float lightIntensity)
{
    static_assert(RSM_WIDTH % THREAD_GROUP_WIDTH == 0);
    assert(s_rsmDepthBuffer.GetWidth() == RSM_WIDTH);
    assert(s_rsmDepthBuffer.GetHeight() == RSM_WIDTH);
    assert(s_rsmNormalBuffer.GetWidth() == RSM_WIDTH);
    assert(s_rsmNormalBuffer.GetHeight() == RSM_WIDTH);
    assert(s_rsmDiffuseBuffer.GetWidth() == RSM_WIDTH);
    assert(s_rsmDiffuseBuffer.GetHeight() == RSM_WIDTH);
    assert(s_rsmSpecularBuffer.GetWidth() == RSM_WIDTH);
    assert(s_rsmSpecularBuffer.GetHeight() == RSM_WIDTH);

    const ScopedTimer profile(L"VSGL Generation", context);

    context.TransitionResource(s_rsmDepthBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.TransitionResource(s_rsmNormalBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.TransitionResource(s_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.TransitionResource(s_rsmSpecularBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    context.SetRootSignature(s_vsglRootSig);

    const float planeWidth = 2.0f * tan(spotLight.GetFOV() / 2.0f);
    const float photonPower = lightIntensity * (planeWidth * planeWidth) / (RSM_WIDTH * RSM_WIDTH); // Photon power before multiplying the Jacobian.

    __declspec(align(16)) struct {
        XMMATRIX lightViewProjInv;
        XMVECTOR lightPosition;
        XMFLOAT3 lightAxis;
        float    photonPower;
    } constants;

    constants.lightViewProjInv = XMMatrixInverse(nullptr, spotLight.GetViewProjMatrix());
    constants.lightPosition = spotLight.GetPosition();
    XMStoreFloat3(&constants.lightAxis, XMVector3Cross(spotLight.GetUpVec(), spotLight.GetRightVec()));
    constants.photonPower = photonPower;

    context.SetDynamicConstantBufferView(VSGL_ROOT_INDEX_CBV, sizeof(constants), &constants);
    context.SetBufferUAV(VSGL_ROOT_INDEX_UAV, s_sgLightBuffer);

    const D3D12_CPU_DESCRIPTOR_HANDLE srvs[] = {
        s_rsmDepthBuffer.GetDepthSRV(),
        s_rsmNormalBuffer.GetSRV(),
        s_rsmDiffuseBuffer.GetSRV(),
    };

    // Generate Diffuse VSGLs.
    context.SetDynamicDescriptors(VSGL_ROOT_INDEX_SRV, 0, _countof(srvs), srvs);
    context.SetConstants(VSGL_ROOT_INDEX_CONSTANTS, 0);
    context.SetPipelineState(s_vsglGenerationDiffusePSO);
    context.Dispatch(1, 1, 1);

    // Generate Specular VSGLs.
    context.SetDynamicDescriptor(VSGL_ROOT_INDEX_SRV, 2, s_rsmSpecularBuffer.GetSRV());
    context.SetConstants(VSGL_ROOT_INDEX_CONSTANTS, 1);
    context.SetPipelineState(s_vsglGenerationSpecularPSO);
    context.Dispatch(1, 1, 1);
}

void MyRenderer::DrawDepth(GraphicsContext& context, const ModelH3D& model)
{
    context.SetIndexBuffer(model.GetIndexBuffer());
    context.SetVertexBuffer(0, model.GetVertexBuffer());
    const uint32_t vertexStride = model.GetVertexStride();

    for (uint32_t meshIndex = 0; meshIndex < model.GetMeshCount(); ++meshIndex)
    {
        const ModelH3D::Mesh& mesh = model.GetMesh(meshIndex);

        assert(mesh.indexCount % 3 == 0);
        assert(mesh.indexDataByteOffset % (sizeof(uint16_t) * 3) == 0);
        assert(mesh.vertexDataByteOffset % vertexStride == 0);

        const uint32_t indexCount = mesh.indexCount;
        const uint32_t startIndex = mesh.indexDataByteOffset / sizeof(uint16_t);
        const uint32_t baseVertex = mesh.vertexDataByteOffset / vertexStride;

        context.DrawIndexed(indexCount, startIndex, baseVertex);
    }
}

void MyRenderer::Draw(GraphicsContext& context, const ModelH3D& model)
{
    context.SetIndexBuffer(model.GetIndexBuffer());
    context.SetVertexBuffer(0, model.GetVertexBuffer());
    const uint32_t vertexStride = model.GetVertexStride();
    uint32_t materialIndex = std::numeric_limits<uint32_t>::max();

    for (uint32_t meshIndex = 0; meshIndex < model.GetMeshCount(); ++meshIndex)
    {
        const ModelH3D::Mesh& mesh = model.GetMesh(meshIndex);

        assert(mesh.indexCount % 3 == 0);
        assert(mesh.indexDataByteOffset % (sizeof(uint16_t) * 3) == 0);
        assert(mesh.vertexDataByteOffset % vertexStride == 0);

        const uint32_t indexCount = mesh.indexCount;
        const uint32_t startIndex = mesh.indexDataByteOffset / sizeof(uint16_t);
        const uint32_t baseVertex = mesh.vertexDataByteOffset / vertexStride;

        if (mesh.materialIndex != materialIndex)
        {
            materialIndex = mesh.materialIndex;
            context.SetDescriptorTable(ROOT_INDEX_PS_SRV0, model.GetSRVs(materialIndex));
        }

        context.DrawIndexed(indexCount, startIndex, baseVertex);
    }
}
