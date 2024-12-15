#pragma once

class GraphicsContext;
class Scene;

namespace MyRenderer
{
extern void Initialize();
extern void Shutdown();
extern void Render(GraphicsContext& context, const Scene& scene);
} // namespace MyRenderer
