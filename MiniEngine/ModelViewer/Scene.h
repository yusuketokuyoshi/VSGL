#pragma once

#include "Model.h"
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
		m_spotLightController.release();
	}

	static constexpr uint32_t                   MODEL_SRV_COUNT = 4;
	static constexpr uint32_t                   CUTOUT_SRV_COUNT = 1; // Alpha cutout for the depth pass.
	Model                                       m_model;
	Model                                       m_modelCutout;
	Math::Camera                                m_camera;
	std::unique_ptr<GameCore::CameraController> m_cameraController;
	Math::Camera                                m_spotLight;
	std::unique_ptr<GameCore::CameraController> m_spotLightController;
	float                                       m_spotLightIntensity = 0.0f;
};
