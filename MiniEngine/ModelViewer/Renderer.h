#pragma once

class GraphicsContext;
class Scene;

namespace Renderer
{
	extern void Create();
	extern void Render(GraphicsContext& context, const Scene& scene);
};
