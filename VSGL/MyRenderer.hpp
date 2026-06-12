#pragma once

#include "Scene.hpp"

#include "ColorBuffer.h"
#include "DepthBuffer.h"
#include "DescriptorHeap.h"
#include "GpuBuffer.h"
#include "PipelineState.h"
#include "RootSignature.h"

class GraphicsContext;
class ComputeContext;

namespace vsgl
{
class MyRenderer
{
  public:
	void Initialize();
	void Shutdown();
	void Render(GraphicsContext& context, const Scene& scene);

  private:
	void ReflectiveShadowMapPass(GraphicsContext& context, const Scene& scene);
	void ShadowMapPass(GraphicsContext& context, const Scene& scene);
	void DepthPass(GraphicsContext& context, const Scene& scene);
	void LightingPass(GraphicsContext& context, const Scene& scene);
	void VSGLGenerationPass(ComputeContext& context, const Math::Camera& spotLight, float lightIntensity);

	DepthBuffer m_shadowMap;
	DepthBuffer m_rsmDepthBuffer;
	ColorBuffer m_rsmNormalBuffer;
	ColorBuffer m_rsmDiffuseBuffer;
	ColorBuffer m_rsmSpecularBuffer;
	StructuredBuffer m_sgLightBuffer;
	DescriptorHandle m_lightingDescriptorTable;

	RootSignature m_depthRootSig;
	RootSignature m_rsmRootSig;
	RootSignature m_lightingRootSig;
	RootSignature m_vsglRootSig;
	GraphicsPSO m_depthPSO = {L"s_depthPSO"};
	GraphicsPSO m_depthCutoutPSO = {L"s_depthCutoutPSO"};
	GraphicsPSO m_shadowMapPSO = {L"s_shadowMapPSO"};
	GraphicsPSO m_shadowMapCutoutPSO = {L"s_shadowMapCutoutPSO"};
	GraphicsPSO m_reflectiveShadowMapPSO = {L"s_reflectiveShadowMapPSO"};
	GraphicsPSO m_reflectiveShadowMapCutoutPSO = {L"s_reflectiveShadowMapCutoutPSO"};
	GraphicsPSO m_lightingPSO = {L"s_lightingPSO"};
	GraphicsPSO m_lightingCutoutPSO = {L"s_lightingCutoutPSO"};
	GraphicsPSO m_previousLightingPSO = {L"s_previousLightingPSO"};
	GraphicsPSO m_previousLightingCutoutPSO = {L"s_previousLightingCutoutPSO"};
	ComputePSO m_vsglGenerationDiffusePSO = {L"s_vsglGenerationDiffusePSO"};
	ComputePSO m_vsglGenerationSpecularPSO = {L"s_vsglGenerationSpecularPSO"};
};
} // namespace vsgl
