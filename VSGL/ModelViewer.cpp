#include "CommandContext.h"
#include "PostEffects.h"
#include "GameInput.h"
#include "Renderer.h"
#include "MyRenderer.hpp"
#include "Scene.hpp"
#include <memory>

namespace
{
ExpVar g_spotLightIntensity{"Application/Light Intensity", 4000000.0f};

class ModelViewer : public GameCore::IGameApp
{
  private:
	Scene m_scene;

  public:
	void Startup() override;
	void Cleanup() override;
	void Update(const float deltaT) override;
	void RenderScene() override;
};

void ModelViewer::Startup()
{
	Renderer::Initialize();
	MyRenderer::Initialize();
	PostEffects::EnableAdaptation = false;

	ASSERT(m_scene.m_model.Load(L"../Sponza/sponza.h3d"), "Failed to load model");
	ASSERT(m_scene.m_model.GetMeshCount() > 0, "Model contains no meshes");
	ASSERT(m_scene.m_modelCutout.Load(L"../Sponza/sponza_cutout.h3d"), "Failed to load model");
	ASSERT(m_scene.m_modelCutout.GetMeshCount() > 0, "Model contains no meshes");

	constexpr float NEAR_Z_CLIP = 1.0f;
	constexpr float FAR_Z_CLIP = 10000.0f;

	const Vector3 CAMERA_POS = {-500.0, 200.0, 400.0};
	const Vector3 CAMERA_DIR = {1.0, -0.2, 0.0};
	m_scene.m_camera.SetEyeAtUp(CAMERA_POS, CAMERA_POS + CAMERA_DIR, Vector3(kYUnitVector));
	m_scene.m_camera.SetZRange(NEAR_Z_CLIP, FAR_Z_CLIP);
	m_scene.m_cameraController = std::make_unique<FlyingFPSCamera>(m_scene.m_camera, Vector3(kYUnitVector));
	m_scene.m_cameraController->Update(0.0f);

	const Vector3 LIGHT_POS = {300.0, 150.0, 400.0};
	const Vector3 LIGHT_DIR = {1.0, -0.5, -1.0};
	m_scene.m_spotlight.SetEyeAtUp(LIGHT_POS, LIGHT_POS + LIGHT_DIR, Vector3(kYUnitVector));
	m_scene.m_spotlight.SetZRange(NEAR_Z_CLIP, FAR_Z_CLIP);
	m_scene.m_spotlight.SetAspectRatio(1.0f);
	m_scene.m_spotlightController = std::make_unique<FlyingFPSCamera>(m_scene.m_spotlight, Vector3(kYUnitVector));
	m_scene.m_spotlightController->Update(0.0f);
}

void ModelViewer::Cleanup()
{
	m_scene.Clear();
	MyRenderer::Shutdown();
	Renderer::Shutdown();
}

void ModelViewer::Update(const float deltaT)
{
	const ScopedTimer _prof(L"Update State");

	if (GameInput::IsPressed(GameInput::kMouse0))
	{
		m_scene.m_spotlightController->Update(deltaT);
	}
	else
	{
		m_scene.m_cameraController->Update(deltaT);
	}

	m_scene.m_spotlightIntensity = g_spotLightIntensity;
}

void ModelViewer::RenderScene()
{
	GraphicsContext& context = GraphicsContext::Begin(L"Rendering");
	MyRenderer::Render(context, m_scene);
	context.Finish();
}
} // namespace

int WINAPI wWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE /*hPrevInstance*/, _In_ LPWSTR /*lpCmdLine*/, _In_ int nShowCmd)
{
	ModelViewer modelViewer;
	return GameCore::RunApplication(modelViewer, L"ModelViewer", hInstance, nShowCmd);
}
