# NPR Avatar Shader System — Technical Meeting Document

**Project:** Avatar Shader Experimental (Unity URP 17.0.4)
**Date:** April 2026

---

## 1. System Overview

The rendering pipeline applies four distinct NPR (Non-Photorealistic Rendering) techniques in sequence:

```
Geometry pass:   XToon_2DRamp  →  HalftoneHatching
Post-process:    AnisotropicKuwahara  →  HierarchicalEdgeDetection / SobelEdgeDetection
```

XToon and HalftoneHatching are **per-material object shaders** — each avatar mesh uses one. Kuwahara and edge detection are **screen-space post-process passes** applied to the composited frame via URP Renderer Features.

---

## 2. XToon 2D Ramp Shader

**File:** `Assets/Shaders/Shaders after Project/XToon_2DRamp.shader`
**Reference:** Barla, Thollot & Markosian — *"X-Toon: An Extended Toon Shader"* (NPAR 2006)

### Core Concept

Classic toon shading maps a single NdotL value to a 1D colour ramp. XToon replaces this with a **2D texture lookup**:

- **U axis** = NdotL (lighting intensity, 0–1)
- **V axis** = "tone detail" or abstraction level (0 = full detail, 1 = abstract)

### Passes

| Pass | LightMode | Purpose |
|------|-----------|---------|
| 0 XToonForward | UniversalForward | Main toon shading |
| 1 Outline | SRPDefaultUnlit | Inverted hull outline |
| 2 ShadowCaster | ShadowCaster | Shadow map contribution |
| 3 DepthOnly | DepthOnly | Depth pre-pass |
| 4 DepthNormals | DepthNormals | Writes normals for edge detection |

### Key Implementation (Fragment Shader)

**NdotL → rampU (Section 3 of paper):**

```hlsl
float NdotL   = dot(normalWS, lightDir) * shadow;
float rampU   = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);
```

Maps NdotL [−1,1] to [0,1], then lerps toward 0.5 based on `_LightSensitivity`.

**Detail axis → rampV (Sections 4.1, 4.2, 4.3 of paper):**

```hlsl
#if defined(_DETAILMODE_DEPTH)
    float t = saturate((length(_WorldSpaceCameraPos - posWS) - _DepthNear) / (_DepthFar - _DepthNear));
    return saturate(t + _DetailBias);
#elif defined(_DETAILMODE_CURVATURE)
    float curvature = length(ddx(normalWS)) + length(ddy(normalWS));
    float t = 1.0 - saturate(curvature * 10.0);
    return t * (1.0 - _DetailBias) + _DetailBias;
#else
    return _ManualDetail;
#endif
```

**Abstraction effect — rampV compresses lighting contrast:**

```hlsl
float abstractU    = lerp(rampU, 0.5, rampV * 0.6);
float dynSmoothing = lerp(_RampSmoothing, _RampSmoothing + 0.35, rampV);
float shadowMask   = smoothstep(0.5 - dynSmoothing, 0.5 + dynSmoothing, abstractU);
```

High rampV = all pixels converge toward neutral mid-tone = abstract/flat rendering.

**Normal Field Abstraction (Section 5 of paper):**

```hlsl
float3 smoothN = normalize(normalWS + _NormalSmoothing * (normalize(positionWS) - normalWS));
normalWS = normalize(lerp(normalWS, smoothN, _NormalSmoothing * 0.5));
```

**Shadow + specular + rim (added, not in paper):**

```hlsl
float3 shadowedAlbedo = lerp(toonAlbedo * _ShadowColor.rgb, toonAlbedo, shadowMask);
float3 finalColor     = lerp(albedo, shadowedAlbedo, _ShadowStrength);
// Stylized specular: NdotH threshold
float specular = smoothstep(1.0 - _SpecularSize - _SpecularSmoothness,
                             1.0 - _SpecularSize + _SpecularSmoothness, NdotH) * shadow;
// Rim: 1 - NdotV
float rim = smoothstep(_RimThreshold - 0.01, _RimThreshold + 0.01,
    (1.0 - NdotV) * pow(saturate(NdotL + 0.5), 0.2));
finalColor = lerp(textureColor, finalColor, _LightingStrength);
```

### Variable Definitions

| Variable | Range | Effect |
|----------|-------|--------|
| `_ToonRamp` | Texture2D | 2D ramp: U=light, V=detail. Defaults to white when unassigned. |
| `_RampSmoothing` | 0–0.1 | Width of AA band between toon zones |
| `_LightSensitivity` | 0–1 | How much lighting angle affects shading (0=flat) |
| `_DetailMode` | Depth/Curvature/Manual | Controls how V axis is computed |
| `_DetailBias` | 0–1 | Shifts the V range up or down |
| `_DepthNear/_DepthFar` | Metres | Distance range for depth abstraction |
| `_ManualDetail` | 0–1 | Direct V override in Manual mode |
| `_NormalSmoothing` | 0–1 | Blends to simplified normals (shape abstraction) |
| `_ShadowColor` | Color | Tint for shadowed areas (typically cool blue) |
| `_ShadowStrength` | 0–1 | Opacity of shadow tinting |
| `_LightingStrength` | 0–1 | Blend: 0=texture only, 1=full specular+rim |
| `_SpecularSize` | 0–1 | NdotH threshold for highlight (smaller=tighter) |
| `_SpecularSmoothness` | 0.001–0.5 | Softness of specular edge |
| `_RimPower` | 0.5–10 | Sharpness of rim falloff (1-NdotV)^power |
| `_RimThreshold` | 0–1 | Minimum NdotL required for rim to appear |
| `_OutlineWidth` | 0–0.05 | World-space hull expansion for inverted outline |
| `_AlphaBlend` | Toggle | Switches material to transparent queue (eyelashes) |

---

## 3. Halftone & Hatching Shader

**File:** `Assets/Shaders/Shaders after Project/HalftoneHatching.shader`
**Reference:** Praun, Hoppe, Webb & Finkelstein — *"Real-Time Hatching"* (SIGGRAPH 2001)

### Core Concept

Replaces smooth colour gradients with ink-on-paper mark patterns. Lighting computes a single `tone` value [0=black, 1=white]; pattern functions decide which marks to draw at that tone level. Implements the **Tonal Art Map (TAM)** concept procedurally.

### Pattern Generation

**Tone from lighting:**

```hlsl
float NdotL = saturate(dot(normalWS, mainLight.direction));
float tone  = NdotL * shadow + _ToneBias;
```

**Halftone dot (circular grid):**

```hlsl
float2 rotCoords = Rotate2D(coords, _HalftoneAngle);
float2 gridPos   = frac(rotCoords * _HalftoneScale) - 0.5;  // [-0.5, 0.5] per cell
float  dist      = length(gridPos);
float  radius    = sqrt(1.0 - tone) * 0.5;  // area ∝ darkness (real halftone physics)
float  pattern   = 1.0 - smoothstep(radius - 0.5/_HalftoneSharpness,
                                     radius + 0.5/_HalftoneSharpness, dist);
```

`sqrt(1-tone)` ensures dot **area** is proportional to ink coverage, matching physical print.

**Hatch line:**

```hlsl
float2 rotCoords = Rotate2D(coords, angleDeg);
float  linePos   = frac(rotCoords.x * _HatchScale);
float  lineMask  = smoothstep(thickness, thickness + 0.02, abs(linePos - 0.5));
return 1.0 - lineMask;
```

**TAM layering (Praun et al. core idea):**

```hlsl
// Layer 1 – primary stripes   (light shadow  t > 0.15)
// Layer 2 – cross hatch       (deeper shadow t > 0.35)
// Layer 3 – dense diagonal    (darker        t > 0.55)
// Layer 4 – solid fill        (near-black    t > 0.80)
pattern = max(pattern, HatchLine(...) * smoothstep(threshold_in, threshold_out, t));
```

`max()` stacking prevents double-darkening where layers overlap.

**Final colour:**

```hlsl
float3 paperCol   = lerp(_PaperColor.rgb, baseAlbedo, _TextureInfluence);
float3 inkCol     = lerp(_InkColor.rgb, baseAlbedo * _InkColor.rgb, _TextureInfluence);
float3 finalColor = lerp(paperCol, inkCol, pattern);
```

### Normal Map Support

The shader accepts a `_BumpMap` (tangent-space normal map). When assigned, the `_NORMALMAP` keyword enables TBN transform in both the forward pass and the `DepthNormals` pass — so edge detection sees surface detail normals on this material.

### Variable Definitions

| Variable | Effect |
|----------|--------|
| `_PatternMode` | Halftone / Hatching / Stipple / Combined |
| `_HalftoneScale` | Dot grid density (higher = smaller dots) |
| `_HalftoneSharpness` | Dot edge crispness |
| `_HalftoneAngle` | Dot grid rotation (45° = classic print) |
| `_HalftoneSpace` | ScreenSpace / ObjectSpace / WorldSpace |
| `_HatchScale` | Line density |
| `_HatchAngle / _CrossHatchAngle` | Direction of hatch layers |
| `_HatchThickness` | Line width relative to cell size |
| `_ToneBias` | Shifts tone curve (positive=lighter overall) |
| `_TextureInfluence` | 0=flat ink/paper colours, 1=texture tints both |
| `_BumpMap / _BumpScale` | Normal map for lighting detail response |

---

## 4. Anisotropic Kuwahara Filter

**File:** `Assets/Shaders/Shaders after Project/AnisotropicKuwahara.shader`
**C# Feature:** `KuwaharaFilterFeature` in `NPRRendererFeatures.cs`
**Reference:** Kyprianidis, Kang & Döllner — *"Image and Video Abstraction by Anisotropic Kuwahara Filtering"* (Pacific Graphics 2009)

### Implementation: 4-Pass Pipeline

**Pass 0 — Structure Tensor** (Section 3 of paper)

Runs Sobel on luminance to compute the local gradient structure:

```hlsl
float gx = -tl - 2*l - bl + tr + 2*r + br;
float gy = -tl - 2*t - tr + bl + 2*b + br;
return float4(gx*gx, gx*gy, gy*gy, 1.0);  // packs J11, J12, J22
```

**Pass 1 — Gaussian Blur on Tensor** (Section 3.1)

Two-pass separable Gaussian (5-tap) smooths the tensor to get stable orientation across regions.

**Pass 2 — Anisotropic Kuwahara Sampling** (Section 4)

Eigendecomposes the blurred tensor to find dominant gradient direction and anisotropy:

```hlsl
float lambda1 = 0.5*(J.x + J.z + sqrt((J.x-J.z)*(J.x-J.z) + 4*J.y*J.y));
float lambda2 = 0.5*(J.x + J.z - sqrt(...));
float2 eigVec = float2(lambda1 - J.x, -J.y);  // major eigenvector
```

Divides neighbourhood into `_SectorCount` sectors aligned to eigenvector. For each sector computes mean and variance, weights final colour by `1/variance^_Sharpness` — sectors matching local structure win.

**Pass 3 — Masked Composite** (project addition, not in paper)

Blends the Kuwahara result over the original using an avatar silhouette mask. Restricts painterly effect to the avatar layer only.

### What was NOT implemented from the paper

The paper's Section 5 describes a **Gaussian image pyramid** multi-scale extension: build downsampled copies, filter at each scale, blend. This was not implemented — single-scale is sufficient for avatar-scale geometry in VR and avoids 3–4 extra blit passes per frame.

### Variable Definitions (Renderer Feature Inspector)

| Variable | Range | Effect |
|----------|-------|--------|
| `Kernel Size` | 2–16 | Filter radius. Larger = bigger brushstrokes, slower. |
| `Sector Count` | 4–8 | Angular resolution of anisotropic sectors. 8 = paper recommendation. |
| `Sharpness` | 1–18 | How strongly the winning sector dominates. High = crisp strokes. |
| `Hardness` | 1–18 | Gaussian weight falloff rate within sector. |
| `Zero Crossing` | 0.3–0.8 | Phase of sector weighting function. 0.58 = paper default. |
| `Avatar Layer` | LayerMask | Restricts effect to this layer. Nothing = full screen. |

---

## 5. Hierarchical Edge Detection vs Sobel Edge Detection

**Files:** `HierarchicalEdgeDetection.shader`, `SobelEdgeDetection.shader`
**C# Feature:** `EdgeDetectionFeature` in `NPRRendererFeatures.cs`
**Reference:** Inspired by AHEAD: Adaptive Hierarchical Edge Detection and classic NPR multi-layer techniques.

### Three-Layer Architecture (shared by both)

Both shaders fuse three independent detection layers:

| Layer | Signal | Detects |
|-------|--------|---------|
| 1 Depth | `SampleSceneDepth` → `LinearEyeDepth` | Silhouettes between objects |
| 2 Normal | `SampleSceneNormals` | Creases and hard edges on surfaces |
| 3 Colour | `_BlitTexture` luminance + chroma | Texture boundaries, fine detail |

**Fusion via weighted max-pooling:**

```hlsl
float edge = max(depthLine  * _DepthWeight,
             max(normalLine * _NormalWeight,
                 colorLine  * _ColorWeight));
```

Max avoids double-counting where layers overlap; per-layer weights allow independent tuning.

**Projection-aware kernel (both shaders):**

```hlsl
float2 projScale = float2(unity_CameraProjection[0][0], unity_CameraProjection[1][1]);
float2 offset    = _BlitTexture_TexelSize.xy * _EdgeWidth * projScale / max(centerDepth, 0.1);
```

Dividing by depth keeps physical sampling radius constant regardless of camera zoom or distance.

### Kernel Difference

**HierarchicalEdgeDetection — Roberts Cross (2×2, 4 samples per layer):**

```hlsl
return abs(tl - br) + abs(tr - bl);
```

Fast (12 total samples), slight directional bias toward 45° edges.

**SobelEdgeDetection — Sobel 3×3 (8 samples per layer):**

```hlsl
float gx = -tl - 2*l - bl + tr + 2*r + br;
float gy = -tl - 2*t - tr + bl + 2*b + br;
return sqrt(gx*gx + gy*gy);
```

Isotropic (equal sensitivity in all directions), smoother lines, ~2× GPU cost (24 total samples).

### Adaptive Sensitivity

```hlsl
float adaptiveFactor = lerp(1.0, saturate(brightness * 2.0), _AdaptiveStrength);
```

Suppresses false edges in shadow areas where depth/normal buffers are noisy.

### Avatar Masking (DepthNormals dependency)

Both shaders call `SampleSceneNormals(uv)` which reads URP's `_CameraNormalsTexture`. For avatar materials (XToon, HalftoneHatching) to contribute to this buffer, both shaders include a custom `DepthNormals` pass (LightMode = "DepthNormals") that writes `NormalizeNormalPerPixel(normalWS)` — the exact URP 17 encoding. Without this pass the normal crease layer sees zeros for avatar pixels.

### Variable Definitions (Renderer Feature Inspector)

| Variable | Range | Effect |
|----------|-------|--------|
| `Depth Threshold` | 0.01–5 m | Minimum world-space depth jump for silhouette |
| `Normal Threshold` | 0.05–2 | Minimum normal difference for crease |
| `Color Threshold` | 0.01–1 | Minimum luminance change for texture edge |
| `Depth/Normal/Color Weight` | 0–1 | Per-layer blend contribution before max-pool |
| `Edge Width` | 0.5–4 | Kernel scale multiplier (world-space consistent) |
| `Adaptive Strength` | 0–1 | How much dark areas reduce sensitivity |
| `Fade With Depth` | Toggle | Edges fade between Fade Start and Fade End distances |
| `Avatar Layer` | LayerMask | Restricts edges to this layer only |

---

## 6. Project-Specific Additions (not in source papers)

| Feature | Where | What it adds |
|---------|-------|-------------|
| Alpha blend toggle | XToon | Per-material transparency for eyelashes/hair |
| `_LightingStrength` | XToon | Blend between texture-only and fully lit |
| Inverted hull outline | XToon, HalftoneHatching | Geometry-based outline, no post-process needed |
| Avatar layer masking | Kuwahara, EdgeDetection | Restricts effects to avatar, not background |
| `_NORMALMAP` keyword | HalftoneHatching | Normal map drives pattern tone response |
| `DepthNormals` pass | XToon, HalftoneHatching | Feeds avatar normals into edge detection |
| Abstract V-axis fallback | XToon | rampV compresses lighting contrast when no ramp texture assigned |

---

## 7. Rendering Order Summary

```
1. DepthNormals prepass   → XToon + HalftoneHatching write normals buffer
2. DepthOnly prepass      → both write depth buffer
3. UniversalForward       → XToon toon-shaded avatar pixels
                          → HalftoneHatching pattern-shaded pixels
4. AfterRenderingTransparents:
   a. KuwaharaFilterFeature  → painterly abstraction on avatar layer
   b. EdgeDetectionFeature   → outline on avatar layer using depth + normals + colour
```
