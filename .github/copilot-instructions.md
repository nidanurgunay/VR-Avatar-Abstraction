# AI Coding Agent Instructions - Unity Toon Shader XR Project

## Project Overview
This is a Unity 6 (6000.0.60f1) project for a thesis exploring **toon/cel-shaded rendering for VR/XR avatars**. The project combines custom shader development with XR Interaction Toolkit for Oculus/OpenXR platforms.

**Primary Focus**: Developing and testing stylized toon shaders with outline rendering for character avatars in VR environments.

## Architecture & Key Components

### Rendering Pipeline
- **Pipeline**: Universal Render Pipeline (URP) 17.0.4
- **Render Assets**: Dual quality configurations in `Assets/Settings/`:
  - `PC_RPAsset.asset` / `PC_Renderer.asset` - Desktop VR quality
  - `Mobile_RPAsset.asset` / `Mobile_Renderer.asset` - Mobile VR quality
- All shaders **must** target `"RenderPipeline"="UniversalPipeline"` and use URP shader libraries

### Shader Development Workflow

#### Shader Variants & Organization
The project uses **three parallel shader development approaches**:
1. **Shader Graph** (`.shadergraph` files) - Visual shader editor for rapid iteration
   - `ToonShaderGraph.shadergraph`, `ToonShaderGraph_1.shadergraph`, `ToonShaderGraph_2.shadergraph`
   - `OutlineShader.shadergraph` - Dedicated outline implementation
2. **Hand-coded HLSL** (`.shader` files) - Fine-grained control over rendering
   - `ToonShader.shader` - Base toon shader with outline pass
   - `Toon_outer.shader` / `Toon_outer_1.shader` - Advanced dual-outline system (outer geometry + inner edge detection)
   - `TonnShader_2.shader` - Alternative variant

#### Critical Shader Pattern: Dual-Pass Outline System
**Inspect** [Toon_outer.shader](Assets/Shaders/Toon_outer.shader) for the canonical implementation:

```hlsl
// Pass 1: Outer Outline (geometry expansion, Cull Front)
Pass {
    Name "OuterOutline"
    Cull Front
    ZWrite Off
    // Expand vertices along world-space normals
    float3 posWS = positionInputs.positionWS + normalInputs.normalWS * _OuterOutlineWidth;
}

// Pass 2: Main Toon Shading + Inner Lines (normal-based edge detection)
Pass {
    Name "ForwardLit"
    Tags { "LightMode"="UniversalForward" }
    // Sample neighboring normals to detect inner edges
    // Apply stepped lighting with configurable ToonSteps
}
```

**Key Properties**:
- `_OuterOutlineWidth` - World-space outline thickness (0-0.5)
- `_ToonSteps` - Quantization levels for cel shading (1-10)
- `_InnerLineThreshold` - Sensitivity for internal edge detection
- `_TextureIntensity` - Blend between flat color and texture detail

### Material-Shader Linkage
Materials in `Assets/Materials/` are organized by shader variant:
- `ToonShaderGraphs/` - Materials using Shader Graph versions
- `ToonShader_1/` - Materials using HLSL variants
- `JadeToonMaterial.mat` - Applied to the Jade character model

**Always update materials** when changing shader properties to see changes in editor.

### Character Integration
- Character model: `Assets/Characters/Jade.fbx`
- This is a single test character for shader validation
- Materials are assigned to mesh renderers via Unity's Material slots

### XR Configuration
- **Packages**: XR Interaction Toolkit 3.0.9, XR Management 4.5.3, Oculus SDK 4.5.2, OpenXR 1.15.1
- **Input**: New Input System (1.14.2) with custom action map at `Assets/InputSystem_Actions.inputactions`
  - Defines Player actions: Move, Look, Attack
- **XR Samples**: Located in `Assets/Samples/XR Interaction Toolkit/` (auto-imported from package)
- **Settings**: XR configurations in `Assets/XRI/Settings/`

## Development Workflows

### Testing Shader Changes
1. Edit shader in VS Code or Unity Shader Graph editor
2. Unity auto-compiles on save (watch console for errors)
3. Select material in Hierarchy/Project to see Inspector updates
4. Test in Play mode or build to VR headset for true lighting evaluation

**Common Issue**: Shader not updating → Check Console for compilation errors; ensure material references correct shader

### Adding New Shader Properties
```hlsl
Properties {
    _NewProperty ("Display Name", Range(min, max)) = defaultValue
}

CBUFFER_START(UnityPerMaterial)
    float _NewProperty;  // Must match property name
CBUFFER_END
```

### VR Build & Testing
- **Platform**: Switch platform to Android (Quest) or Windows (PCVR) in Build Settings
- **Test Scene**: `Assets/Scenes/SampleScene.unity` or `Assets/ToonShadrTest.unity`
- XR Device Simulator available for in-editor testing without headset

## Unity-Specific Conventions

### File Organization
- **NEVER** manually edit files in `Library/` - Unity manages this cache
- `.meta` files are critical - commit them to version control for GUID consistency
- Shader compilation outputs cached in `Library/ShaderCache/`

### URP Shader Requirements
Always include these namespaces in HLSL shaders:
```hlsl
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
```

Use URP functions (NOT built-in pipeline):
- `TransformObjectToHClip()` instead of `UnityObjectToClipPos()`
- `GetVertexPositionInputs()`, `GetVertexNormalInputs()` for vertex transformations
- `GetMainLight()` for primary light access

### Project Structure Logic
- `Assets/` - All user-editable content (scenes, scripts, shaders, models)
- `Packages/` - Package dependencies (read-only, managed by Unity)
- `ProjectSettings/` - Project configuration (quality, input, XR settings)
- `Library/` - Build cache (excluded from version control)

## Research Context
This is a **thesis project exploring toon shader aesthetics in VR**. Shader variants exist to:
- Compare Shader Graph vs. hand-coded HLSL workflows
- Test different outline techniques (geometry expansion vs. edge detection)
- Evaluate performance trade-offs on VR hardware

When suggesting shader modifications, consider:
- VR performance constraints (target 72-90 fps per eye)
- Stereoscopic rendering implications (outline width in screen vs. world space)
- Real-time lighting requirements (must work with dynamic lights)

## Common Gotchas
- **Shader Graph changes** don't appear → Reimport the `.shadergraph` file
- **Outlines disappear at distance** → Use world-space outline width, not screen-space
- **Toon shading too dark** → Increase `_AmbientColor` or reduce `_ShadowStrength`
- **Material not found errors** → Materials reference shaders by path; don't move/rename shaders without updating materials

## Questions for Clarification
- Are there specific shader effects or research goals you're investigating?
- Do you need help with XR interaction setup or primarily shader development?
- Should I prioritize Shader Graph or HLSL development for new features?
