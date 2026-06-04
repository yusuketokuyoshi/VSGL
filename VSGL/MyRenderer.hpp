#pragma once

class GraphicsContext;

namespace vsgl
{
class Scene;

namespace MyRenderer
{
extern void Initialize();
extern void Shutdown();
extern void Render(GraphicsContext& context, const Scene& scene);
} // namespace MyRenderer
} // namespace vsgl
