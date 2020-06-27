#include "CommandContext.h"
#include "PostEffects.h"
#include "GameInput.h"
#include "Renderer.h"
#include "Scene.h"

ExpVar g_spotLightIntensity("Application/Light Intensity", 4000000.0f);

class ModelViewer : public GameCore::IGameApp
{
public:
	virtual void Startup() override;
	virtual void Cleanup() override;
	virtual void Update(const float deltaT) override;
	virtual void RenderScene() override;

private:
	Scene m_scene;
};

void ModelViewer::Startup()
{
	Renderer::Create();
	PostEffects::EnableAdaptation = false;
	Graphics::s_EnableVSync = false;

	TextureManager::Initialize(L"../Sponza/");
	ASSERT(m_scene.m_model.Load("../Sponza/sponza.h3d"), "Failed to load model");
	ASSERT(m_scene.m_model.m_Header.meshCount > 0, "Model contains no meshes");
	ASSERT(m_scene.m_modelCutout.Load("../Sponza/sponza_cutout.h3d"), "Failed to load model");
	ASSERT(m_scene.m_modelCutout.m_Header.meshCount > 0, "Model contains no meshes");

	constexpr float NEAR_Z_CLIP = 1.0f;
	constexpr float FAR_Z_CLIP = 10000.0f;

	const Vector3 cameraPos = { -500.0, 200.0, 400.0 };
	const Vector3 cameraDir = { 1.0, -0.2, 0.0 };
	const Vector3 cameraUp = { 0.0, 1.0, 0.0 };
	m_scene.m_camera.SetEyeAtUp(cameraPos, cameraPos + cameraDir, cameraUp);
	m_scene.m_camera.SetPerspectiveMatrix(XM_PIDIV4, 9.0f / 16.0f, NEAR_Z_CLIP, FAR_Z_CLIP);
	m_scene.m_cameraController.reset(new GameCore::CameraController(m_scene.m_camera, cameraUp));
	m_scene.m_cameraController->Update(0.0f);

	const Vector3 lightPos = { 300.0, 150.0, 400.0 };
	const Vector3 lightDir = { 1.0, -0.5, -1.0 };
	const Vector3 lightUp = { 0.0, 1.0, 0.0 };
	m_scene.m_spotLight.SetEyeAtUp(lightPos, lightPos + lightDir, lightUp);
	m_scene.m_spotLight.SetPerspectiveMatrix(XM_PIDIV4, 1.0f, NEAR_Z_CLIP, FAR_Z_CLIP);
	m_scene.m_spotLightController.reset(new GameCore::CameraController(m_scene.m_spotLight, lightUp));
	m_scene.m_spotLightController->Update(0.0f);
}

void ModelViewer::Cleanup()
{
	m_scene.Clear();
}

void ModelViewer::Update(const float deltaT)
{
	const ScopedTimer _prof(L"Update State");

	if (GameInput::IsPressed(GameInput::kMouse0))
	{
		m_scene.m_spotLightController->Update(deltaT);
	}
	else
	{
		m_scene.m_cameraController->Update(deltaT);
	}

	m_scene.m_spotLightIntensity = g_spotLightIntensity;
}

void ModelViewer::RenderScene()
{
	GraphicsContext& context = GraphicsContext::Begin(L"Rendering");
	Renderer::Render(context, m_scene);
	context.Finish();
}

int wmain()
{
	ModelViewer app;
	GameCore::RunApplication(app, L"ModelViewer");
	return 0;
}
