#pragma once

#include "ModelH3D.h"
#include "Camera.h"
#include "CameraController.h"

class Scene
{
public:
	void Clear()
	{
		m_model.Clear();
		m_modelCutout.Clear();
		m_cameraController.release();
		m_spotlightController.release();
	}

	static constexpr uint32_t         MODEL_SRV_COUNT = 4;
	static constexpr uint32_t         CUTOUT_SRV_COUNT = 1; // Alpha cutout for the depth pass.
	ModelH3D                          m_model;
	ModelH3D                          m_modelCutout;
	Math::Camera                      m_camera;
	std::unique_ptr<CameraController> m_cameraController;
	Math::Camera                      m_spotlight;
	std::unique_ptr<CameraController> m_spotlightController;
	float                             m_spotlightIntensity = 0.0f;
};
