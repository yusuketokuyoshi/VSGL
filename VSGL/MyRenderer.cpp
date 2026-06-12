#include "MyRenderer.hpp"
#include "Scene.hpp"
#include "Shaders/VSGLGenerationSetting.h"

#include "BufferManager.h"
#include "CommandContext.h"
#include "Renderer.h"

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <limits>

// Compiled shaders
#include "CompiledShaders/DepthCutoutPS.h"
#include "CompiledShaders/DepthCutoutVS.h"
#include "CompiledShaders/DepthVS.h"
#include "CompiledShaders/LightingCutoutPS.h"
#include "CompiledShaders/LightingPS.h"
#include "CompiledShaders/LightingVS.h"
#include "CompiledShaders/PreviousLightingCutoutPS.h"
#include "CompiledShaders/PreviousLightingPS.h"
#include "CompiledShaders/ReflectiveShadowMapCutoutPS.h"
#include "CompiledShaders/ReflectiveShadowMapPS.h"
#include "CompiledShaders/ReflectiveShadowMapVS.h"
#include "CompiledShaders/VSGLGenerationDiffuseCS.h"
#include "CompiledShaders/VSGLGenerationSpecularCS.h"

namespace vsgl
{
namespace
{
BoolVar m_previousSGLighting{"SG lighting/Previous method", false};

enum GFX_ROOT_INDEX
{
	ROOT_INDEX_VS_CBV,
	ROOT_INDEX_PS_SRV0,
	ROOT_INDEX_PS_SRV1,
	ROOT_INDEX_PS_CBV0,
	ROOT_INDEX_PS_CBV1,
};
enum VSGL_ROOT_INDEX
{
	VSGL_ROOT_INDEX_CBV,
	VSGL_ROOT_INDEX_CONSTANTS,
	VSGL_ROOT_INDEX_SRV,
	VSGL_ROOT_INDEX_UAV,
};

void DrawDepth(GraphicsContext& context, const ModelH3D& model)
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

		context.DrawIndexed(indexCount, startIndex, static_cast<INT>(baseVertex));
	}
}

void Draw(GraphicsContext& context, const ModelH3D& model)
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

		context.DrawIndexed(indexCount, startIndex, static_cast<INT>(baseVertex));
	}
}
} // namespace

void MyRenderer::Initialize()
{
	m_shadowMap.Create(L"m_shadowMap", 2048, 2048, DXGI_FORMAT_D32_FLOAT);
	m_rsmDepthBuffer.Create(L"m_rsmDepthBuffer", RSM_WIDTH, RSM_WIDTH, DXGI_FORMAT_D32_FLOAT);
	m_rsmNormalBuffer.Create(L"m_rsmNormalBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R16G16_SNORM);
	m_rsmDiffuseBuffer.Create(L"m_rsmDiffuseBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R10G10B10A2_UNORM);
	m_rsmSpecularBuffer.Create(L"m_rsmSpecularBuffer", RSM_WIDTH, RSM_WIDTH, 1, DXGI_FORMAT_R8G8B8A8_UNORM);
	m_sgLightBuffer.Create(L"m_sgLightBuffer", 2, sizeof(uint32_t) * 12);

	// Allocate a descriptor table for forward rendering
	constexpr uint32_t LIGHTING_DESCRIPTOR_TABLE_SIZE = 1;
	m_lightingDescriptorTable = Renderer::s_TextureHeap.Alloc(LIGHTING_DESCRIPTOR_TABLE_SIZE);
	Graphics::g_Device->CopyDescriptorsSimple(1, m_lightingDescriptorTable, m_shadowMap.GetDepthSRV(), D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

	SamplerDesc shadowSamplerDesc;
	shadowSamplerDesc.Filter = D3D12_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT;
	shadowSamplerDesc.ComparisonFunc = D3D12_COMPARISON_FUNC_GREATER;
	shadowSamplerDesc.SetTextureAddressMode(D3D12_TEXTURE_ADDRESS_MODE_BORDER);

	SamplerDesc samplerAnisotropicWrapDesc = Graphics::SamplerAnisoWrapDesc;
	samplerAnisotropicWrapDesc.MaxAnisotropy = 16;

	m_depthRootSig.Reset(2, 1);
	m_depthRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
	m_depthRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::CUTOUT_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
	m_depthRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
	m_depthRootSig.Finalize(L"m_depthRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

	m_rsmRootSig.Reset(2, 1);
	m_rsmRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
	m_rsmRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::MODEL_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
	m_rsmRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
	m_rsmRootSig.Finalize(L"m_rsmRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

	m_lightingRootSig.Reset(5, 2);
	m_lightingRootSig[ROOT_INDEX_VS_CBV].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_VERTEX);
	m_lightingRootSig[ROOT_INDEX_PS_SRV0].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, Scene::MODEL_SRV_COUNT, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig[ROOT_INDEX_PS_SRV1].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, Scene::MODEL_SRV_COUNT, LIGHTING_DESCRIPTOR_TABLE_SIZE, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig[ROOT_INDEX_PS_CBV0].InitAsConstantBuffer(0, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig[ROOT_INDEX_PS_CBV1].InitAsConstantBuffer(1, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig.InitStaticSampler(0, samplerAnisotropicWrapDesc, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig.InitStaticSampler(1, shadowSamplerDesc, D3D12_SHADER_VISIBILITY_PIXEL);
	m_lightingRootSig.Finalize(L"m_lightingRootSig", D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT);

	m_vsglRootSig.Reset(4);
	m_vsglRootSig[VSGL_ROOT_INDEX_CBV].InitAsConstantBuffer(0);
	m_vsglRootSig[VSGL_ROOT_INDEX_CONSTANTS].InitAsConstants(1, 1);
	m_vsglRootSig[VSGL_ROOT_INDEX_SRV].InitAsDescriptorRange(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 0, 3);
	m_vsglRootSig[VSGL_ROOT_INDEX_UAV].InitAsBufferUAV(0);
	m_vsglRootSig.Finalize(L"m_vsglRootSig");

	m_vsglGenerationDiffusePSO.SetRootSignature(m_vsglRootSig);
	m_vsglGenerationDiffusePSO.SetComputeShader(g_pVSGLGenerationDiffuseCS, sizeof(g_pVSGLGenerationDiffuseCS));
	m_vsglGenerationDiffusePSO.Finalize();
	m_vsglGenerationSpecularPSO.SetRootSignature(m_vsglRootSig);
	m_vsglGenerationSpecularPSO.SetComputeShader(g_pVSGLGenerationSpecularCS, sizeof(g_pVSGLGenerationSpecularCS));
	m_vsglGenerationSpecularPSO.Finalize();

	{
		constexpr std::array DEPTH_ELEMENT_DESCS = {
			D3D12_INPUT_ELEMENT_DESC{"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
		};
		constexpr std::array CUTOUT_ELEMENT_DESCS = {
			D3D12_INPUT_ELEMENT_DESC{"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
			D3D12_INPUT_ELEMENT_DESC{"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
		};

		m_depthPSO.SetRootSignature(m_depthRootSig);
		m_depthPSO.SetRasterizerState(Graphics::RasterizerDefault);
		m_depthPSO.SetBlendState(Graphics::BlendNoColorWrite);
		m_depthPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_depthPSO.SetInputLayout(static_cast<UINT>(DEPTH_ELEMENT_DESCS.size()), DEPTH_ELEMENT_DESCS.data());
		m_depthPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_depthPSO.SetRenderTargetFormats(0, nullptr, Graphics::g_SceneDepthBuffer.GetFormat());
		m_depthPSO.SetVertexShader(g_pDepthVS, sizeof(g_pDepthVS));
		m_depthPSO.Finalize();

		m_depthCutoutPSO.SetRootSignature(m_depthRootSig);
		m_depthCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
		m_depthCutoutPSO.SetBlendState(Graphics::BlendNoColorWrite);
		m_depthCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_depthCutoutPSO.SetInputLayout(static_cast<UINT>(CUTOUT_ELEMENT_DESCS.size()), CUTOUT_ELEMENT_DESCS.data());
		m_depthCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_depthCutoutPSO.SetRenderTargetFormats(0, nullptr, Graphics::g_SceneDepthBuffer.GetFormat());
		m_depthCutoutPSO.SetVertexShader(g_pDepthCutoutVS, sizeof(g_pDepthCutoutVS));
		m_depthCutoutPSO.SetPixelShader(g_pDepthCutoutPS, sizeof(g_pDepthCutoutPS));
		m_depthCutoutPSO.Finalize();

		m_shadowMapPSO.SetRootSignature(m_depthRootSig);
		m_shadowMapPSO.SetRasterizerState(Graphics::RasterizerShadow);
		m_shadowMapPSO.SetBlendState(Graphics::BlendNoColorWrite);
		m_shadowMapPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_shadowMapPSO.SetInputLayout(static_cast<UINT>(DEPTH_ELEMENT_DESCS.size()), DEPTH_ELEMENT_DESCS.data());
		m_shadowMapPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_shadowMapPSO.SetRenderTargetFormats(0, nullptr, m_shadowMap.GetFormat());
		m_shadowMapPSO.SetVertexShader(g_pDepthVS, sizeof(g_pDepthVS));
		m_shadowMapPSO.Finalize();

		m_shadowMapCutoutPSO.SetRootSignature(m_depthRootSig);
		m_shadowMapCutoutPSO.SetRasterizerState(Graphics::RasterizerShadowTwoSided);
		m_shadowMapCutoutPSO.SetBlendState(Graphics::BlendNoColorWrite);
		m_shadowMapCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_shadowMapCutoutPSO.SetInputLayout(static_cast<UINT>(CUTOUT_ELEMENT_DESCS.size()), CUTOUT_ELEMENT_DESCS.data());
		m_shadowMapCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_shadowMapCutoutPSO.SetRenderTargetFormats(0, nullptr, m_shadowMap.GetFormat());
		m_shadowMapCutoutPSO.SetVertexShader(g_pDepthCutoutVS, sizeof(g_pDepthCutoutVS));
		m_shadowMapCutoutPSO.SetPixelShader(g_pDepthCutoutPS, sizeof(g_pDepthCutoutPS));
		m_shadowMapCutoutPSO.Finalize();
	}
	{
		constexpr std::array ELEMENT_DESCS = {
			D3D12_INPUT_ELEMENT_DESC{"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
			D3D12_INPUT_ELEMENT_DESC{"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
			D3D12_INPUT_ELEMENT_DESC{"NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
			D3D12_INPUT_ELEMENT_DESC{"TANGENT", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
			D3D12_INPUT_ELEMENT_DESC{"BITANGENT", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D12_APPEND_ALIGNED_ELEMENT, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
		};
		const std::array rsmFormats = {m_rsmNormalBuffer.GetFormat(), m_rsmDiffuseBuffer.GetFormat(), m_rsmSpecularBuffer.GetFormat()};

		m_reflectiveShadowMapPSO.SetRootSignature(m_rsmRootSig);
		m_reflectiveShadowMapPSO.SetRasterizerState(Graphics::RasterizerDefault);
		m_reflectiveShadowMapPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_reflectiveShadowMapPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_reflectiveShadowMapPSO.SetBlendState(Graphics::BlendDisable);
		m_reflectiveShadowMapPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_reflectiveShadowMapPSO.SetRenderTargetFormats(static_cast<UINT>(rsmFormats.size()), rsmFormats.data(), m_rsmDepthBuffer.GetFormat());
		m_reflectiveShadowMapPSO.SetVertexShader(g_pReflectiveShadowMapVS, sizeof(g_pReflectiveShadowMapVS));
		m_reflectiveShadowMapPSO.SetPixelShader(g_pReflectiveShadowMapPS, sizeof(g_pReflectiveShadowMapPS));
		m_reflectiveShadowMapPSO.Finalize();

		m_reflectiveShadowMapCutoutPSO.SetRootSignature(m_rsmRootSig);
		m_reflectiveShadowMapCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
		m_reflectiveShadowMapCutoutPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_reflectiveShadowMapCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_reflectiveShadowMapCutoutPSO.SetBlendState(Graphics::BlendDisable);
		m_reflectiveShadowMapCutoutPSO.SetDepthStencilState(Graphics::DepthStateReadWrite);
		m_reflectiveShadowMapCutoutPSO.SetRenderTargetFormats(static_cast<UINT>(rsmFormats.size()), rsmFormats.data(), m_rsmDepthBuffer.GetFormat());
		m_reflectiveShadowMapCutoutPSO.SetVertexShader(g_pReflectiveShadowMapVS, sizeof(g_pReflectiveShadowMapVS));
		m_reflectiveShadowMapCutoutPSO.SetPixelShader(g_pReflectiveShadowMapCutoutPS, sizeof(g_pReflectiveShadowMapCutoutPS));
		m_reflectiveShadowMapCutoutPSO.Finalize();

		m_lightingPSO.SetRootSignature(m_lightingRootSig);
		m_lightingPSO.SetRasterizerState(Graphics::RasterizerDefault);
		m_lightingPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_lightingPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_lightingPSO.SetBlendState(Graphics::BlendDisable);
		m_lightingPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
		m_lightingPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
		m_lightingPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
		m_lightingPSO.SetPixelShader(g_pLightingPS, sizeof(g_pLightingPS));
		m_lightingPSO.Finalize();

		m_lightingCutoutPSO.SetRootSignature(m_lightingRootSig);
		m_lightingCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
		m_lightingCutoutPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_lightingCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_lightingCutoutPSO.SetBlendState(Graphics::BlendDisable);
		m_lightingCutoutPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
		m_lightingCutoutPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
		m_lightingCutoutPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
		m_lightingCutoutPSO.SetPixelShader(g_pLightingCutoutPS, sizeof(g_pLightingCutoutPS));
		m_lightingCutoutPSO.Finalize();

		m_previousLightingPSO.SetRootSignature(m_lightingRootSig);
		m_previousLightingPSO.SetRasterizerState(Graphics::RasterizerDefault);
		m_previousLightingPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_previousLightingPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_previousLightingPSO.SetBlendState(Graphics::BlendDisable);
		m_previousLightingPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
		m_previousLightingPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
		m_previousLightingPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
		m_previousLightingPSO.SetPixelShader(g_pPreviousLightingPS, sizeof(g_pPreviousLightingPS));
		m_previousLightingPSO.Finalize();

		m_previousLightingCutoutPSO.SetRootSignature(m_lightingRootSig);
		m_previousLightingCutoutPSO.SetRasterizerState(Graphics::RasterizerTwoSided);
		m_previousLightingCutoutPSO.SetInputLayout(static_cast<UINT>(ELEMENT_DESCS.size()), ELEMENT_DESCS.data());
		m_previousLightingCutoutPSO.SetPrimitiveTopologyType(D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
		m_previousLightingCutoutPSO.SetBlendState(Graphics::BlendDisable);
		m_previousLightingCutoutPSO.SetDepthStencilState(Graphics::DepthStateTestEqual);
		m_previousLightingCutoutPSO.SetRenderTargetFormat(Graphics::g_SceneColorBuffer.GetFormat(), Graphics::g_SceneDepthBuffer.GetFormat());
		m_previousLightingCutoutPSO.SetVertexShader(g_pLightingVS, sizeof(g_pLightingVS));
		m_previousLightingCutoutPSO.SetPixelShader(g_pPreviousLightingCutoutPS, sizeof(g_pPreviousLightingCutoutPS));
		m_previousLightingCutoutPSO.Finalize();
	}
}

void MyRenderer::Shutdown()
{
	m_shadowMap.Destroy();
	m_rsmDepthBuffer.Destroy();
	m_rsmNormalBuffer.Destroy();
	m_rsmDiffuseBuffer.Destroy();
	m_rsmSpecularBuffer.Destroy();
	m_sgLightBuffer.Destroy();
}

void MyRenderer::Render(GraphicsContext& context, const Scene& scene)
{
	// Initialize rendering buffers.
	context.TransitionResource(m_rsmDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_WRITE);
	context.TransitionResource(m_rsmNormalBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
	context.TransitionResource(m_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
	context.TransitionResource(m_rsmSpecularBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
	context.TransitionResource(m_shadowMap, D3D12_RESOURCE_STATE_DEPTH_WRITE);
	context.TransitionResource(m_sgLightBuffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
	context.TransitionResource(Graphics::g_SceneDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_WRITE);
	context.TransitionResource(Graphics::g_SceneColorBuffer, D3D12_RESOURCE_STATE_RENDER_TARGET);
	context.ClearDepth(m_rsmDepthBuffer);
	context.ClearColor(m_rsmDiffuseBuffer);
	context.ClearColor(m_rsmSpecularBuffer);
	context.ClearDepth(m_shadowMap);
	context.ClearDepth(Graphics::g_SceneDepthBuffer);
	context.ClearColor(Graphics::g_SceneColorBuffer);

	ReflectiveShadowMapPass(context, scene);
	ShadowMapPass(context, scene);
	DepthPass(context, scene);
	VSGLGenerationPass(context.GetComputeContext(), scene.m_spotlight, scene.m_spotlightIntensity);
	LightingPass(context, scene);
}

void MyRenderer::ReflectiveShadowMapPass(GraphicsContext& context, const Scene& scene)
{
	const ScopedTimer profile(L"Reflective Shadow Map", context);

	const XMMATRIX& viewProj = scene.m_spotlight.GetViewProjMatrix();
	const std::array rtvs = {m_rsmNormalBuffer.GetRTV(), m_rsmDiffuseBuffer.GetRTV(), m_rsmSpecularBuffer.GetRTV()};

	context.SetRootSignature(m_rsmRootSig);
	context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
	context.SetViewportAndScissor(0, 0, m_rsmDepthBuffer.GetWidth(), m_rsmDepthBuffer.GetHeight());
	context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
	context.SetRenderTargets(static_cast<UINT>(rtvs.size()), rtvs.data(), m_rsmDepthBuffer.GetDSV());
	context.SetPipelineState(m_reflectiveShadowMapPSO);
	Draw(context, scene.m_model);

	if (scene.m_modelCutout.m_Header.meshCount > 0)
	{
		context.SetPipelineState(m_reflectiveShadowMapCutoutPSO);
		Draw(context, scene.m_modelCutout);
	}

	context.BeginResourceTransition(m_rsmDepthBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.BeginResourceTransition(m_rsmNormalBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.BeginResourceTransition(m_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.BeginResourceTransition(m_rsmSpecularBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
}

void MyRenderer::ShadowMapPass(GraphicsContext& context, const Scene& scene)
{
	const ScopedTimer profile(L"Shadow Map", context);

	const XMMATRIX& viewProj = scene.m_spotlight.GetViewProjMatrix();

	context.SetRootSignature(m_depthRootSig);
	context.SetViewportAndScissor(0, 0, m_shadowMap.GetWidth(), m_shadowMap.GetHeight());
	context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
	context.SetDepthStencilTarget(m_shadowMap.GetDSV());
	context.SetPipelineState(m_shadowMapPSO);
	DrawDepth(context, scene.m_model);

	if (scene.m_modelCutout.m_Header.meshCount > 0)
	{
		context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
		context.SetPipelineState(m_shadowMapCutoutPSO);
		Draw(context, scene.m_modelCutout);
	}

	context.BeginResourceTransition(m_shadowMap, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
}

void MyRenderer::DepthPass(GraphicsContext& context, const Scene& scene)
{
	const ScopedTimer profile(L"Depth", context);

	const XMMATRIX& viewProj = scene.m_camera.GetViewProjMatrix();

	context.SetRootSignature(m_depthRootSig);
	context.SetViewportAndScissor(0, 0, Graphics::g_SceneDepthBuffer.GetWidth(), Graphics::g_SceneDepthBuffer.GetHeight());
	context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
	context.SetDepthStencilTarget(Graphics::g_SceneDepthBuffer.GetDSV());
	context.SetPipelineState(m_depthPSO);
	DrawDepth(context, scene.m_model);

	if (scene.m_modelCutout.m_Header.meshCount > 0)
	{
		context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
		context.SetPipelineState(m_depthCutoutPSO);
		Draw(context, scene.m_modelCutout);
	}

	context.BeginResourceTransition(Graphics::g_SceneDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_READ);
}

void MyRenderer::LightingPass(GraphicsContext& context, const Scene& scene)
{
	const ScopedTimer profile(L"Lighting", context);

	context.TransitionResource(Graphics::g_SceneDepthBuffer, D3D12_RESOURCE_STATE_DEPTH_READ);
	context.TransitionResource(m_shadowMap, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(m_sgLightBuffer, D3D12_RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER);

	const XMMATRIX& viewProj = scene.m_camera.GetViewProjMatrix();

	alignas(16) struct
	{
		XMMATRIX lightViewProj;
		XMVECTOR cameraPosition;
		XMFLOAT3 lightPosition;
		float lightIntensity;
	} constants{};

	constants.lightViewProj = scene.m_spotlight.GetViewProjMatrix();
	constants.cameraPosition = scene.m_camera.GetPosition();
	XMStoreFloat3(&constants.lightPosition, scene.m_spotlight.GetPosition());
	constants.lightIntensity = scene.m_spotlightIntensity;

	context.SetRootSignature(m_lightingRootSig);
	context.SetDescriptorHeap(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, Renderer::s_TextureHeap.GetHeapPointer());
	context.SetViewportAndScissor(0, 0, Graphics::g_SceneDepthBuffer.GetWidth(), Graphics::g_SceneDepthBuffer.GetHeight());
	context.SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
	context.SetDynamicConstantBufferView(ROOT_INDEX_VS_CBV, sizeof(viewProj), &viewProj);
	context.SetDynamicConstantBufferView(ROOT_INDEX_PS_CBV0, sizeof(constants), &constants);
	context.SetConstantBuffer(ROOT_INDEX_PS_CBV1, m_sgLightBuffer.RootConstantBufferView());
	context.SetDescriptorTable(ROOT_INDEX_PS_SRV1, m_lightingDescriptorTable);
	context.SetRenderTarget(Graphics::g_SceneColorBuffer.GetRTV(), Graphics::g_SceneDepthBuffer.GetDSV_DepthReadOnly());
	context.SetPipelineState(m_previousSGLighting ? m_previousLightingPSO : m_lightingPSO);
	Draw(context, scene.m_model);

	if (scene.m_modelCutout.m_Header.meshCount > 0)
	{
		context.SetPipelineState(m_previousSGLighting ? m_previousLightingCutoutPSO : m_lightingCutoutPSO);
		Draw(context, scene.m_modelCutout);
	}
}

// Generate a diffuse VSGL and specular VSGL from an RSM.
void MyRenderer::VSGLGenerationPass(ComputeContext& context, const Math::Camera& spotLight, const float lightIntensity)
{
	static_assert(RSM_WIDTH % THREAD_GROUP_WIDTH == 0);
	assert(m_rsmDepthBuffer.GetWidth() == RSM_WIDTH);
	assert(m_rsmDepthBuffer.GetHeight() == RSM_WIDTH);
	assert(m_rsmNormalBuffer.GetWidth() == RSM_WIDTH);
	assert(m_rsmNormalBuffer.GetHeight() == RSM_WIDTH);
	assert(m_rsmDiffuseBuffer.GetWidth() == RSM_WIDTH);
	assert(m_rsmDiffuseBuffer.GetHeight() == RSM_WIDTH);
	assert(m_rsmSpecularBuffer.GetWidth() == RSM_WIDTH);
	assert(m_rsmSpecularBuffer.GetHeight() == RSM_WIDTH);

	const ScopedTimer profile(L"VSGL Generation", context);

	context.TransitionResource(m_rsmDepthBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(m_rsmNormalBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(m_rsmDiffuseBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.TransitionResource(m_rsmSpecularBuffer, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
	context.SetRootSignature(m_vsglRootSig);

	const float planeWidth = 2.0f * std::tan(spotLight.GetFOV() / 2.0f);
	const float photonPower = lightIntensity * (planeWidth * planeWidth) / (RSM_WIDTH * RSM_WIDTH); // Photon power before multiplying the Jacobian.

	alignas(16) struct
	{
		XMMATRIX lightViewProjInv;
		XMVECTOR lightPosition;
		XMFLOAT3 lightAxis;
		float photonPower;
	} constants{};

	constants.lightViewProjInv = XMMatrixInverse(nullptr, spotLight.GetViewProjMatrix());
	constants.lightPosition = spotLight.GetPosition();
	XMStoreFloat3(&constants.lightAxis, XMVector3Cross(spotLight.GetUpVec(), spotLight.GetRightVec()));
	constants.photonPower = photonPower;

	context.SetDynamicConstantBufferView(VSGL_ROOT_INDEX_CBV, sizeof(constants), &constants);
	context.SetBufferUAV(VSGL_ROOT_INDEX_UAV, m_sgLightBuffer);

	const std::array srvs = {m_rsmDepthBuffer.GetDepthSRV(), m_rsmNormalBuffer.GetSRV(), m_rsmDiffuseBuffer.GetSRV()};

	// Generate Diffuse VSGLs.
	context.SetDynamicDescriptors(VSGL_ROOT_INDEX_SRV, 0, static_cast<UINT>(srvs.size()), srvs.data());
	context.SetConstants(VSGL_ROOT_INDEX_CONSTANTS, 0);
	context.SetPipelineState(m_vsglGenerationDiffusePSO);
	context.Dispatch(1, 1, 1);

	// Generate Specular VSGLs.
	context.SetDynamicDescriptor(VSGL_ROOT_INDEX_SRV, 2, m_rsmSpecularBuffer.GetSRV());
	context.SetConstants(VSGL_ROOT_INDEX_CONSTANTS, 1);
	context.SetPipelineState(m_vsglGenerationSpecularPSO);
	context.Dispatch(1, 1, 1);
}
} // namespace vsgl
