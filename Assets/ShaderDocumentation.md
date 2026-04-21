# Shader Documentation
## XToon 2D Ramp Shader, Anisotropic Kuwahara Filter, Halftone & Hatching Shader, and Hierarchical Edge Detection

---

# Part 1 — XToon: Extended Toon Shader

## What is a shader?

A 3D avatar is just geometry — triangles with positions in space. A **shader** is the GPU program that answers two questions:

1. **Where does each triangle's corner land on screen?** → vertex shader
2. **What colour is each pixel inside that triangle?** → fragment shader

Without a shader, Unity does not know whether an avatar should look like skin, metal, plastic, or a cartoon. The shader is the complete description of visual logic.

---

## What is XToon?

XToon is a non-photorealistic rendering technique introduced in:

> Barla, Thollot & Markosian — *"X-Toon: An Extended Toon Shader"* (NPAR 2006)

A **classic toon shader** takes a single lighting value (NdotL, explained below) and maps it to a 1D colour gradient — the result is flat colour bands (lit/shadow) but no ability to express distance, detail level, or abstraction.

**XToon's contribution:** replace the 1D gradient with a **2D texture**, adding a second axis called "tone detail" that lets the shader express how abstract or detailed the rendering should be based on depth, curvature, or artist intent.

---

## Shader Structure

This shader is located at:
`Assets/Shaders/Shaders after Project/XToon_2DRamp.shader`

It has four GPU passes:

| Pass | Name | Purpose |
|------|------|---------|
| 0 | XToonForward | Main toon shading — what you see |
| 1 | Outline | Draws black outline using inverted hull |
| 2 | ShadowCaster | Tells Unity where this object casts shadows |
| 3 | DepthOnly | Writes depth for SSAO, DOF, and other effects |

The paper's contribution lives entirely in **Pass 0**. The other three are standard Unity infrastructure.

---

## The Properties Block

```hlsl
Properties { ... }
```

A list of artist-controllable inputs that appear as sliders, colour pickers, and texture slots in the Unity Inspector. They do no computation — they are named values the shader code reads. Examples:

- `_BaseMap` — the skin/clothing diffuse texture
- `_ToonRamp` — the 2D ramp texture (core of XToon)
- `_ShadowColor` — colour to tint shadowed areas
- `_SpecularSize` — how large the stylised highlight disc is

---

## SubShader Tags

```hlsl
"RenderType" = "Opaque"
"Queue"      = "Geometry"
```

These tell URP **when** to draw this object. `Queue = Geometry` means draw during the opaque pass, before transparent objects. `RenderType = Opaque` tells screen-space effects (SSAO, outlines, shadows) how to treat this mesh. Changing these to `Transparent` was one of the bugs we investigated — it caused post-processing to skip the body, making it appear dark.

---

## Pass 0 — Main XToon Shading

### Step 1: Normal Abstraction (Paper Section 5)

```hlsl
float3 smoothN = normalize(
    normalWS + _NormalSmoothing * (normalize(input.positionWS) - normalWS));
normalWS = normalize(lerp(normalWS, smoothN, _NormalSmoothing * 0.5));
```

Every triangle has a **surface normal** — an arrow pointing straight out, used to compute how much light hits it. Normal abstraction interpolates between the real surface normal and a simpler approximation (pointing from the world origin to the surface — equivalent to treating the avatar as a smooth sphere). 

- `_NormalSmoothing = 0` → use real normals → full surface detail in lighting
- `_NormalSmoothing = 1` → use sphere-like normals → flat, cartoon-rounded lighting

If an `_AbstractNormalMap` is assigned, that texture provides the simplified normals instead, giving the artist direct control over the abstracted shape.

**Paper reference:** Section 5 *"Normal Field Abstraction"* — the authors show that shape-level abstraction requires modifying the normal field, not just the colour mapping.

---

### Step 2: Computing NdotL — the U axis of the ramp (Paper Section 3)

```hlsl
float NdotL = dot(normalWS, lightDir);
NdotL = NdotL * shadow;
float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);
```

**N dot L** (normal dot light direction) is the cosine of the angle between the surface normal and the light direction:

- `NdotL = 1.0` → surface faces the light directly → fully lit
- `NdotL = 0.0` → surface is perpendicular to light → shadow boundary
- `NdotL < 0.0` → surface faces away → deep shadow

Multiplying by `shadow` (from Unity's shadow map) means occluded surfaces are pushed toward 0 regardless of angle.

The result is remapped from [-1, 1] to [0, 1] for texture sampling, then compressed by `_LightSensitivity` toward 0.5 (the ramp centre) — at zero sensitivity all pixels sample the middle of the ramp regardless of lighting.

This value becomes the **horizontal (U) coordinate** when sampling the 2D ramp texture.

---

### Step 3: Computing the Detail Axis — the V axis of the ramp (Paper Section 4)

```hlsl
float rampV = saturate(ComputeDetailAxis(input.positionWS, normalWS, viewDir));
```

This is **the core XToon contribution** — a second axis that drives how abstract the look is. Three modes:

#### Mode A — Depth (Paper Section 4.1)

```hlsl
float depth = length(_WorldSpaceCameraPos - posWS);
float t = saturate((depth - _DepthNear) / (_DepthFar - _DepthNear));
return lerp(0.0, 1.0, t) + _DetailBias;
```

Measures straight-line distance from the camera to the current pixel. As the avatar moves away:
- Distance < `_DepthNear` → `t = 0` → V = 0 → bottom of ramp → full detail
- Distance > `_DepthFar` → `t = 1` → V = 1 → top of ramp → maximum abstraction

An artist paints the ramp so distant rows look simpler or more stylised than close rows.

**Paper reference:** Section 4.1 *"Depth-based tone detail"* — objects become more abstract as they recede.

#### Mode B — Curvature (Paper Section 4.2)

```hlsl
float3 dNdx = ddx(normalWS);
float3 dNdy = ddy(normalWS);
float curvature = length(dNdx) + length(dNdy);
float t = 1.0 - saturate(curvature * 10.0);
```

`ddx` and `ddy` are GPU instructions that measure how much a value changes between adjacent screen pixels. Applied to the surface normal, they detect **curvature**:

- Highly curved areas (nose bridge, chin) → normals change rapidly → large `curvature` → `t` near 0 → V near 0 → detailed
- Flat areas (forehead, cheek) → normals barely change → small `curvature` → `t` near 1 → V near 1 → abstract

**Paper reference:** Section 4.2 *"Curvature-based tone detail"* — areas of high curvature retain detail; flat areas simplify.

#### Mode C — Manual (Paper Section 4.3)

```hlsl
return _ManualDetail;
```

A single slider sets the V value for the entire mesh. Useful for art-directing the look without procedural logic — the artist just chooses exactly which row of the ramp to use.

**Paper reference:** Section 4.3 *"User-controlled tone detail"*.

---

### Step 4: Sampling the 2D Ramp (Paper Figure 2)

```hlsl
float3 rampColor = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp, float2(rampU, rampV)).rgb;
```

This single line is the implementation of the paper's core idea. Instead of a 1D lookup `ramp(NdotL)`, it is a 2D lookup `ramp(NdotL, detailLevel)`. The artist paints this texture to define how every combination of lighting and abstraction level should look.

---

### Step 5: Shadow Colour Tinting

```hlsl
float shadowMask = rampColor.r;
float3 shadowedAlbedo = lerp(albedo * _ShadowColor.rgb, albedo, shadowMask);
float3 finalColor = lerp(albedo, shadowedAlbedo, _ShadowStrength);
```

The red channel of the ramp sample acts as a 0–1 shadow mask:

- `shadowMask = 1` → lit → show the full albedo (diffuse texture colour)
- `shadowMask = 0` → shadowed → blend albedo toward `_ShadowColor` (default: cool blue-grey)

`_ShadowStrength` scales how much the tint applies. This gives stylised shadows with a custom colour rather than simply darkening.

---

### Step 6: Stylised Specular

```hlsl
float3 halfDir = normalize(lightDir + viewDir);
float NdotH = dot(normalWS, halfDir);
float specular = smoothstep(1.0 - _SpecularSize - _SpecularSmoothness,
                            1.0 - _SpecularSize + _SpecularSmoothness,
                            NdotH) * shadow;
finalColor = lerp(finalColor, _SpecularColor.rgb, specular * _SpecularStrength);
```

The **half-vector** (`halfDir`) is the direction exactly halfway between the light and the camera. When the surface normal aligns with it, the pixel is at the mirror-reflection point — the specular highlight. `NdotH` measures this alignment.

`smoothstep` converts the smooth gradient into a sharp disc. `_SpecularSize` sets disc size; `_SpecularSmoothness` sets edge hardness. At low smoothness this produces the hard anime-style white dot. This is a non-physically-based stylised specular — the paper mentions specular as an extension but leaves the specific method to the implementer.

---

### Step 7: Rim Light

```hlsl
float NdotV = dot(normalWS, viewDir);
float rim = 1.0 - saturate(NdotV);
rim = smoothstep(_RimThreshold - 0.01, _RimThreshold + 0.01,
    rim * pow(saturate(NdotL + 0.5), 0.2));
finalColor = lerp(finalColor, _RimColor.rgb, rim * _RimStrength);
```

`NdotV` measures how much the surface faces the camera. Near-zero values mean the surface is nearly edge-on — the silhouette boundary. `1 - NdotV` is therefore brightest at edges. The `pow(NdotL + 0.5, 0.2)` term suppresses rim light on shadow-side edges, keeping the glow physically plausible. This produces the stylised edge glow common in anime and NPR characters.

---

### Step 8: Lighting Strength Slider (Added in this project)

```hlsl
float3 textureColor = finalColor;        // save before specular + rim
// ... apply specular + rim ...
finalColor = lerp(textureColor, finalColor, _LightingStrength);
```

Saves the toon-shaded colour before specular and rim are applied, then lerps between "texture only" and "fully lit" at the end. At `_LightingStrength = 0` all highlights disappear but the base toon colour remains intact; at `1.0` full specular and rim are applied. This was added to compensate for scenes with two lights causing excessive reflection.

---

## Pass 1 — Outline (Inverted Hull)

```hlsl
Cull Front
posWS += normalWS * _OutlineWidth;
```

The mesh is rendered a second time with front-face culling flipped. Normally `Cull Back` hides inside faces. With `Cull Front`, only the back faces of a **slightly expanded** mesh are visible — they appear as a uniform black border behind the main render. No edge detection math needed; pure geometry.

Limitation: flat surfaces produce thin or missing outlines because back-faces are nearly coplanar with front-faces when expanded.

---

## Pass 2 — Shadow Caster

A stripped-down pass that only outputs depth, letting Unity compute where this mesh casts shadows onto other objects. When `_ALPHA_BLEND` is enabled (eyelashes), it also samples the texture alpha and calls `clip()` to punch holes in the shadow matching the transparent regions.

---

## Pass 3 — Depth Only

Same logic as the shadow caster but used by screen-space effects (SSAO, depth of field, outlines) that need to know how far each pixel is from the camera.

---

## Alpha Blend (Added in this project)

```hlsl
[AlphaBlendToggle] _AlphaBlend ("Alpha Blend (Eyelashes)", Float) = 0
```

A checkbox that switches the material between opaque and transparent mode. When enabled:
- `Blend SrcAlpha OneMinusSrcAlpha` — standard alpha blending
- `ZWrite Off` — transparent objects do not write to the depth buffer
- `Queue = Transparent` — rendered after all opaque geometry
- Shadow/depth passes clip pixels whose alpha falls below `_AlphaCutoff`

A custom `MaterialPropertyDrawer` (`AlphaBlendToggleDrawer.cs`) handles setting these states automatically when the checkbox is toggled in the Inspector.

---

## Summary: Paper vs Implementation

| Feature | Source |
|---|---|
| 2D ramp (U = NdotL, V = detail) | Paper Section 3 — core contribution |
| Depth-driven V axis | Paper Section 4.1 |
| Curvature-driven V axis | Paper Section 4.2 |
| Manual V axis slider | Paper Section 4.3 |
| Normal Field Abstraction | Paper Section 5 |
| Shadow colour tinting | Standard toon technique |
| Stylised specular disc | Standard toon technique |
| Rim light | Standard toon technique |
| Inverted hull outline | Classic game technique |
| Alpha blend for eyelashes | Added for this project |
| Lighting strength slider | Added for this project |

---
---

# Part 2 — Anisotropic Kuwahara Filter

## What is it?

The Kuwahara filter is an **image abstraction / painterly effect** applied as a full-screen post-processing pass after the scene is rendered. It makes the image look like an oil painting — edges stay sharp, flat regions become smooth and uniform in colour.

This implementation is based on:

> Kyprianidis, Collomosse, Wang & Isenberg — *"Image and Video Abstraction by Anisotropic Kuwahara Filtering"* (Pacific Graphics 2009)

The key word is **anisotropic** — the filter adapts its shape and orientation to local image structure, rather than using a fixed circular kernel. This produces cleaner, more natural-looking painterly strokes that follow the shapes in the image.

---

## How it fits into the rendering pipeline

This is **not a per-material shader**. It is a **URP Renderer Feature** — a custom post-processing step that runs after the entire scene has been rendered to a texture. It takes that texture, applies the painterly effect, and writes the result back.

The pipeline in code (`AnisotropicKuwaharaFeature.cs` + `AnisotropicKuwahara.shader`):

```
Scene renders → camera colour texture
    │
    ▼ Pass 0: Structure Tensor
    │   Compute image gradient information (where are the edges and in what direction)
    │
    ▼ Pass 1: Gaussian Blur (run twice: horizontal then vertical)
    │   Smooth the gradient information to get stable orientation fields
    │
    ▼ Pass 2: Anisotropic Kuwahara Filter
    │   For each pixel: sample a directional ellipse of neighbours,
    │   divide them into sectors, pick the sector with lowest variance
    │
    ▼ Output: painterly image written back to camera texture
```

---

## Pass 0 — Structure Tensor (Paper Section 3)

```hlsl
float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
return float4(gx*gx, gx*gy, gy*gy, 1.0);
```

### What is a structure tensor?

Before the filter can be anisotropic, it needs to know the **local image structure** at every pixel — specifically:
- Is there an edge nearby?
- If so, in what direction does it run?
- How strong is it?

This is computed using **Sobel operators** — a classic edge-detection technique that convolves (slides a small pattern over) the image to measure horizontal and vertical brightness changes.

For each pixel, 8 neighbours are sampled (tl=top-left, l=left, bl=bottom-left, etc.). The pattern `[-1, -2, -1, 0, 0, 0, +1, +2, +1]` computes `gx` (horizontal gradient) and `gy` (vertical gradient).

The result is stored as a **2×2 structure tensor matrix** packed into RGB:
- Red = gx² (horizontal strength)
- Green = gx·gy (orientation coupling)
- Blue = gy² (vertical strength)

This tensor encodes both the strength and direction of the local gradient at each pixel.

**Paper reference:** Section 3 *"Structure Tensor"* — the authors derive their anisotropic filter from this tensor field.

---

## Pass 1 — Gaussian Blur on the Tensor (Paper Section 3.1)

```hlsl
float4 result  = sample(uv - 2*offset) * 0.0625
               + sample(uv -   offset) * 0.25
               + sample(uv           ) * 0.375
               + sample(uv +   offset) * 0.25
               + sample(uv + 2*offset) * 0.0625;
```

The structure tensor is noisy — a single sharp edge pixel surrounded by flat pixels can produce unstable orientation estimates. **Gaussian blur** smooths the tensor field across neighbouring pixels so that orientation information represents a wider local neighbourhood rather than individual pixel noise.

The weights `[0.0625, 0.25, 0.375, 0.25, 0.0625]` are a 5-tap approximation of a Gaussian bell curve. The blur is run **twice** — first horizontally then vertically — which is equivalent to a 2D Gaussian blur but costs only O(2n) samples instead of O(n²). This is called a **separable filter**.

**Paper reference:** Section 3.1 — smoothing the tensor field before using it for orientation estimation.

---

## Pass 2 — Anisotropic Kuwahara Filter (Paper Section 4)

This is the main algorithm. Three conceptual stages:

### Stage A — Eigenvalue decomposition (Paper Equation 1)

```hlsl
float disc    = sqrt((E-G)*(E-G) + 4.0*F*F);
float lambda1 = 0.5*(E+G+disc);
float lambda2 = 0.5*(E+G-disc);
float angle   = 0.5 * atan2(2.0*F, E-G);
float anisotropy = (lambda1-lambda2)/(lambda1+lambda2);
```

The structure tensor is a 2×2 matrix. **Eigenvalue decomposition** extracts two key quantities:

- **`angle`** — the dominant orientation of local image structure (the direction the edge runs)
- **`anisotropy`** — how strongly directional the structure is (0 = no clear direction = flat area, 1 = very strong edge)

These drive the shape of the filter kernel at each pixel.

**Paper reference:** Equation 1 — the tensor eigenanalysis that makes the filter orientation-aware.

### Stage B — Ellipse kernel shaped by anisotropy (Paper Section 4.1)

```hlsl
float a = radius * clamp((1.0 + anisotropy) * 0.5, 0.5, 2.0);
float b = radius * clamp((1.0 - anisotropy) * 0.5, 0.25, 1.0);
```

Instead of sampling a fixed circle around each pixel, the filter samples an **ellipse**:
- `a` = long axis (stretched in the direction of the edge)
- `b` = short axis (compressed perpendicular to the edge)

On a flat featureless area: `anisotropy ≈ 0` → circle → uniform blur
On a sharp edge: `anisotropy ≈ 1` → elongated ellipse aligned with the edge → blur runs along the edge, not across it → the edge stays sharp

The ellipse is also **rotated** to align with `angle` using cos/sin transforms.

**Paper reference:** Section 4.1 — the anisotropic ellipse formulation.

### Stage C — Sector-based sampling and variance weighting (Paper Equation αi)

```hlsl
// Divide the ellipse into N sectors, accumulate colour and variance per sector
float w = 1.0 / (1.0 + pow(variance * 1000.0, 0.5 * _Sharpness));
result += mean * w;
```

The ellipse is divided into N equal angular sectors (default 8). For each sample inside the ellipse:
1. Determine which sector it belongs to by its angle
2. Accumulate its colour (weighted by a Gaussian that reduces weight at the ellipse boundary)
3. Accumulate its colour variance (how much colours differ within that sector)

At the end, each sector has a **mean colour** and a **variance**. The final pixel colour is a weighted blend of all sector means, where the weight is `1 / (1 + variance)`:

- Low variance sector → colours are uniform → high weight → this sector looks like a flat paint region → **keep it**
- High variance sector → colours are mixed → low weight → this sector crosses an edge → **suppress it**

`_Sharpness` (paper parameter `q = 8`) controls how aggressively low-variance sectors dominate. Higher sharpness = crisper boundary between painted regions.

This is the mechanism that produces the oil-paint look: homogeneous colour regions become flat and saturated, edges between them stay sharp because sectors that would cross edges are downweighted.

**Paper reference:** Equation αi — the inverse-variance weighting that is the paper's core contribution over earlier Kuwahara variants.

---

## Pass 3 — Masked Composite (added in this project)

```hlsl
float mask = SAMPLE_TEXTURE2D(_AvatarMask, sampler_LinearClamp, uv).r;
return lerp(original, kuwahara, mask);
```

Optional. If an `avatarLayer` is specified in the Renderer Feature settings, a silhouette of the avatar is rendered to a mask texture first. The composite pass then blends the original scene (unfiltered) with the Kuwahara result using that mask — so only the avatar receives the painterly effect and the background is unchanged.

---

## Parameter Guide

| Parameter | Paper name | Effect |
|---|---|---|
| `kernelSize` | radius r | How many pixels around each point are sampled. Larger = more painterly, slower. |
| `sectorCount` | N | Number of angular wedges. 8 is the paper's recommendation. |
| `sharpness` | q | How sharply the lowest-variance sector wins. Paper uses q=8. Higher = harder edges between paint regions. |
| `hardness` | — | Gaussian weight falloff inside the kernel. Higher = samples near the ellipse edge matter less. |

---

## Summary: What the filter does visually

1. **Flat regions** (cheek, forehead) → one sector dominates completely → single uniform colour → smooth, saturated paint-like area
2. **Edges** (hairline, jaw, eye contour) → sectors on either side of the edge stay within their region → the edge is preserved sharply
3. **Orientation** → the ellipse aligns with the edge direction → strokes appear to follow the shape of the subject, like brush strokes painted along the contours of a face

The result is a rendering that looks hand-painted while preserving the recognisable structure of the avatar.

---

## How it connects to XToon

Both techniques are **NPR (Non-Photorealistic Rendering)** approaches:

- **XToon** operates per-object, per-pixel during the geometry rendering pass — it controls *how each material is shaded*
- **Kuwahara** operates on the final composited image as a post-process — it controls *how the entire rendered frame looks*

---

---

# Part 3 — Halftone & Hatching Shader

## What is it?

The Halftone & Hatching shader is a **per-object NPR material shader** (not a post-process) that replaces smooth colour gradients with ink-on-paper patterns borrowed from traditional printmaking and comics. Instead of blending between "lit" and "shadow" colours continuously, the shader asks: *what physical mark-making technique would a human artist use here?*

It is inspired by:

> Praun, Hoppe, Webb & Finkelstein — *"Real-Time Hatching"* (SIGGRAPH 2001)

That paper introduced the **Tonal Art Map (TAM)**: a set of pre-drawn texture layers, each with a different density of marks, that activate progressively as surfaces become darker. This shader implements the same layered-activation concept procedurally (no pre-drawn textures needed).

---

## Four Pattern Modes

You choose one mode in the Inspector via the **Pattern Mode** dropdown. Each mode is compiled into a separate shader variant using `shader_feature_local` keywords — unused variants are stripped from the build.

### Mode 1 — Halftone

Classic **printing-press halftone**: the image is broken into a regular grid of dots. Each dot's radius is proportional to how dark that area is.

```
light area  →  tiny dots spaced far apart
dark area   →  large dots, almost overlapping
black area  →  filled solid
```

**How the code does it:**

1. The pattern coordinates (UV, world-space, or screen-space) are rotated by `_HalftoneAngle` using a 2D rotation matrix.
2. `frac(rotCoords * _HalftoneScale)` maps the surface into a repeating [0,1]² grid of cells.
3. Subtracting 0.5 puts the origin at the cell centre, and `length(gridPos)` gives the distance from that centre.
4. The dot radius is `sqrt(1 - tone) * 0.5` — square root makes the dot *area* proportional to darkness, which is how real halftone printing works (equal ink per unit area).
5. `smoothstep` at the dot boundary gives a soft AA edge.

**Coordinate space options:**

| Space | Effect |
|-------|--------|
| ScreenSpace | Dots fixed on screen — stable at any angle, slight shimmer on moving objects |
| ObjectSpace | Dots follow UV layout — stay on the mesh, can stretch with UV distortion |
| WorldSpace | Dots anchored in world XYZ — triplanar projection, no UV dependency, best for stylised environments |

For the WorldSpace mode the code uses triplanar blending:
```hlsl
patternCoords = wsXZ * absN.y + wsXY * absN.z + wsYZ * absN.x;
```
Each axis pair is weighted by how much the surface normal points in that direction — a floor uses XZ, a wall uses XY or YZ, a sloped surface blends all three.

---

### Mode 2 — Hatching (Lines)

**Hatching** is the cross-hatch drawing technique: shadow areas are described by parallel lines, with more layers added the darker the area. This is the direct implementation of the Praun et al. TAM concept.

The shader uses four progressive layers, each controlled by a `smoothstep` envelope so layers fade in and out without hard jumps:

| Layer | Darkness threshold | What activates |
|-------|-------------------|----------------|
| 1 | t > 0.15 | Single direction lines (`_HatchAngle`) |
| 2 | t > 0.35 | Cross hatch lines (`_CrossHatchAngle`) |
| 3 | t > 0.55 | Dense diagonal (average of both angles, thicker) |
| 4 | t > 0.80 | Solid fill — near-black areas go fully opaque |

`t = 1 - tone` converts brightness to darkness (0 = fully lit, 1 = black shadow).

Each individual line is drawn with:
```hlsl
float linePos = frac(rotCoords.x * _HatchScale);
float lineMask = smoothstep(thickness, thickness + 0.02, abs(linePos - 0.5));
return 1.0 - lineMask;
```
`abs(linePos - 0.5)` creates a symmetric peak at each grid centre. `smoothstep` around `thickness` turns that into a stripe. Final `1 - lineMask` makes lines opaque and gaps transparent.

The layers are combined with `max()` — if any layer says "draw ink here", ink is drawn. This correctly stacks without double-darkening.

---

### Mode 3 — Stipple

**Stippling** is the technique of using scattered dots (like a fine pen) to represent tone — dark areas have denser dots, light areas have fewer.

```hlsl
float2 gridCoords = floor(coords * _StippleScale);
float noise = Hash21(gridCoords);
float stipple = (noise > tone * _StippleDensity) ? 1.0 : 0.0;
```

- `floor()` snaps to a grid cell — each cell gets one noise value
- `Hash21` is a deterministic pseudo-random hash: same input always gives the same output (no temporal shimmer)
- The threshold compares that random value to the surface tone: in bright areas (high `tone`) very few cells pass the test; in dark areas (low `tone`) most pass

The result is a stable, gridded dot pattern that responds to lighting without any texture look-up.

---

### Mode 4 — Combined

Blends halftone and hatching in a single pass:
- **Mid-tones** (between 0 and 0.5 tone): halftone dots dominate
- **Dark shadows** (tone approaching 0): hatching lines dominate

```hlsl
float halftonePart = HalftonePattern(...) * smoothstep(0.0, 0.5, tone) * smoothstep(1.0, 0.5, tone);
float hatchPart    = HatchingPattern(...)  * (1.0 - smoothstep(0.0, 0.4, tone));
pattern = max(halftonePart, hatchPart);
```

The double `smoothstep` on `halftonePart` creates a bell curve peaking at mid-tone. The inverted `smoothstep` on `hatchPart` ramps up only in dark areas.

---

## How Lighting Drives the Patterns

The shader computes a single float `tone` (0 = black shadow, 1 = fully lit):

```hlsl
float NdotL  = saturate(dot(normalWS, mainLight.direction));
float shadow = mainLight.shadowAttenuation;
float tone   = NdotL * shadow + _ToneBias;
```

- `NdotL` is the same diffuse dot product used in every toon/PBR shader
- `mainLight.shadowAttenuation` fades `tone` to near-zero where the object is in another object's shadow
- `_ToneBias` shifts the whole curve (positive = lighter overall, negative = darker)

Every pattern function receives this single `tone` value and decides how dense to make the marks. The surface texture and ink/paper colours then wrap around the pattern:

```hlsl
float3 paperCol = lerp(_PaperColor.rgb, baseAlbedo, _TextureInfluence);
float3 inkCol   = lerp(_InkColor.rgb,   baseAlbedo * _InkColor.rgb, _TextureInfluence);
float3 finalColor = lerp(paperCol, inkCol, pattern);
```

At `_TextureInfluence = 0` you get flat comic-book colours. At `_TextureInfluence = 1` the base texture acts as both the paper and tints the ink.

---

## Passes

| Pass | Purpose |
|------|---------|
| 0 — HalftoneHatchingForward | Main forward shading with pattern |
| 1 — Outline | Inverted hull outline (same technique as XToon) |
| 2 — ShadowCaster | Standard URP shadow casting |
| 3 — DepthOnly | Standard URP depth pre-pass |

The outline pass (Pass 1) is identical in principle to XToon's outline: render back faces with normals expanded outward by `_OutlineWidth`, write the `_OutlineColor`. No special edge detection needed.

---

## Key Parameters

| Parameter | What it does |
|-----------|-------------|
| `_PatternMode` | Switch between Halftone / Hatching / Stipple / Combined |
| `_HalftoneScale` | How many dots fit across the surface (higher = smaller dots) |
| `_HalftoneAngle` | Rotate the dot grid — 45° is the classic print angle |
| `_HalftoneSharpness` | How sharp the dot edge is — low = soft blobs, high = crisp circles |
| `_HalftoneSpace` | Coordinate space the dots are computed in |
| `_HatchScale` | Line density — higher = more lines per unit |
| `_HatchAngle` / `_CrossHatchAngle` | Direction of the two hatch layers |
| `_HatchThickness` | How thick each hatch line is |
| `_ToneLevels` | Reserved for future tone quantisation (currently drives no branching) |
| `_ToneBias` | Shift the whole tone curve lighter or darker |
| `_TextureInfluence` | 0 = flat cartoon, 1 = base texture drives the colours |
| `_InkColor` / `_PaperColor` | The two colours of the "print" — ink for marks, paper for gaps |

---

## Connection to the Tonal Art Map (TAM) Paper

Praun et al.'s key insight was that a single piece of paper needs multiple pre-drawn "TAM" images — one for each darkness level — so the renderer can cross-fade between them without aliasing. This shader achieves the same effect **procedurally**: each layer is a mathematical function that activates exactly when needed, with a `smoothstep` cross-fade built in. No texture atlas is required, and the result scales to any resolution without mip-map artefacts.

---

---

# Part 4 — Hierarchical Edge Detection vs Sobel Edge Detection

## What problem do both shaders solve?

Both are **post-process edge detection shaders** applied after all objects are rendered. They run on the already-composited frame and draw dark outlines where the image has discontinuities — silhouette edges between objects, creases in a surface, and colour/texture boundaries.

Neither shader touches the mesh geometry. They analyse four buffers that URP builds automatically:
- **Colour buffer** (_BlitTexture) — the rendered frame
- **Depth buffer** — how far each pixel is from the camera (in metres)
- **Screen-space normals buffer** — the surface normal at each pixel, in view space

---

## How edge detection works in general

An edge is a place where something changes rapidly. To find edges on a 2D image, you compute the **spatial gradient**: how much does a value change as you move from one pixel to its neighbour? Where the gradient is large, there is an edge.

Both shaders detect edges on three separate signals, then combine them:

1. **Depth edges** — finds silhouettes where one object ends and another begins, or the background
2. **Normal edges** — finds creases and hard edges on the same object (e.g., the jaw line of a face)
3. **Colour/luminance edges** — finds texture boundaries and fine surface detail

---

## The kernel: what is Roberts Cross vs Sobel?

This is the **core technical difference** between the two shaders.

### Roberts Cross (used by HierarchicalEdgeDetection)

Roberts Cross uses only **4 samples** arranged in a 2×2 diagonal pattern:

```
TL   TR
BL   BR
```

The gradient magnitude is:
```
|TL - BR| + |TR - BL|
```

This compares two diagonal pairs. It is:
- Very **fast**: 4 texture samples per layer (12 total for 3 layers)
- **Sensitive**: small kernel catches fine edges well
- **Directionally biased**: best at 45° edges, slightly weaker at pure horizontal/vertical

### Sobel (used by SobelEdgeDetection)

Sobel uses **8 samples** arranged in a 3×3 grid (all neighbours, excluding centre):

```
TL  T  TR
L       R
BL  B  BR
```

Two kernels are applied: Gx (horizontal gradient) and Gy (vertical gradient):

```
Gx:  -1  0  +1        Gy:  +1  +2  +1
     -2  0  +2              0   0   0
     -1  0  +1             -1  -2  -1
```

The centre row/column neighbours are double-weighted (`±2`) to smooth noise. The gradient magnitude is:

```
sqrt(Gx² + Gy²)
```

This is:
- **Slower**: 8 texture samples per layer (24 total for 3 layers — double the cost)
- **More isotropic**: equal sensitivity in all directions (no directional bias)
- **Smoother**: the weighted averaging reduces noise-induced false edges
- **Thicker lines**: the 3×3 neighbourhood integrates more signal, so edges tend to be slightly wider

---

## Side-by-side comparison

| Property | HierarchicalEdgeDetection (Roberts Cross) | SobelEdgeDetection (Sobel) |
|----------|------------------------------------------|---------------------------|
| Kernel size | 2×2 (4 samples per layer) | 3×3 (8 samples per layer) |
| Total texture samples | ~12 | ~24 |
| GPU cost | Lower | ~2× higher |
| Directional uniformity | Slight 45° bias | Fully isotropic |
| Noise sensitivity | More (small kernel) | Less (weighted smoothing) |
| Edge line style | Finer, crisper | Slightly thicker, smoother |
| Best for | Real-time, many avatars, performance-critical scenes | Offline render, single hero character, max quality |

---

## What both shaders share: the three-layer fusion

Despite using different kernels, both shaders follow the same **three-layer hierarchical architecture**:

### Layer 1 — Depth (Silhouettes)

Reads linear eye depth (in metres) for the four/eight neighbours and applies the kernel. A large depth jump means one object ends and another begins — a silhouette edge.

```
threshold unit = metres → e.g. 0.5 m depth jump = draw edge
```

This is the most important layer for character outlines. It cleanly separates the avatar body from the background and from other objects.

### Layer 2 — Normal (Creases)

Reads the per-pixel world normal for the neighbours. A large normal change means the surface bends sharply — a crease, hard edge, or silhouette from the *same* object.

For Roberts Cross, each normal component is differenced and the results are averaged:
```hlsl
float edge = dot(diff1 + diff2, float3(1,1,1)) / 3.0;
```

For Sobel, the Gx/Gy kernel is applied per-component as a `float3`, then the magnitude of the resulting gradient vectors is used:
```hlsl
return sqrt(dot(gx, gx) + dot(gy, gy));
```

This layer catches facial creases, collar bones, fabric folds — anything the depth layer misses because it is on the same continuous surface.

### Layer 3 — Colour/Luminance (Detail edges)

Reads the colour buffer. Uses luminance `(0.2126 R + 0.7152 G + 0.0722 B)` as the primary signal, plus a chromatic term to catch edges where hue changes but brightness does not.

This layer picks up texture patterns, skin markings, tattoos, clothing prints — detail that is invisible to depth and normals.

---

## Fusion: weighted max-pooling

After computing and thresholding each layer independently, the three edge values are combined with **max-pooling**:

```hlsl
float edge = max(depthLine  * _DepthWeight,
             max(normalLine * _NormalWeight,
                 colorLine  * _ColorWeight));
```

Max-pooling is used rather than addition or average because:
- Any single layer detecting a strong edge is enough to draw it
- Adding would double-count where two layers overlap, making those edges unnaturally thick
- Per-layer weights let you dial back colour edges (noisy on textured avatars) without affecting silhouettes

---

## Adaptive sensitivity

Both shaders modulate threshold sensitivity by local brightness:

```hlsl
float adaptiveFactor = lerp(1.0, saturate(brightness * 2.0), _AdaptiveStrength);
```

In dark areas, `brightness` is near 0, so `adaptiveFactor` drops toward 0 — the edge detector becomes less sensitive. This suppresses the large number of false edges that appear inside shadows because depth and normal buffers are noisy at low light. Normal edges receive half the adaptation (`lerp(1.0, adaptiveFactor, 0.5)`) because surface creases are equally real in shadow.

---

## Projection-aware kernel scaling

Both shaders use the same trick to keep edges at a consistent *world-space* width regardless of camera zoom or distance:

```hlsl
float2 projScale = float2(unity_CameraProjection[0][0],
                          unity_CameraProjection[1][1]);
float2 offset = _BlitTexture_TexelSize.xy * _EdgeWidth
                * projScale / max(centerDepth, 0.1);
```

- `_BlitTexture_TexelSize.xy` = one pixel in UV space
- `projScale` = cotangent of half-FOV — encodes zoom level
- Dividing by `centerDepth` shrinks the kernel for far-away objects

Without this, a wide-angle lens would produce thin edges and a telephoto lens would produce thick ones, and distant objects would have thicker outlines than close ones.

---

## Depth fading

Both shaders support optional depth-based fading:

```hlsl
float fade = 1.0 - saturate((depth - _DepthFadeStart) / (_DepthFadeEnd - _DepthFadeStart));
edge *= fade;
```

Edges smoothly disappear beyond `_DepthFadeEnd`. This prevents the background from being cluttered with outlines on distant geometry and gives a sense of atmospheric depth.

---

## Avatar masking

Both shaders share the masking system with the Kuwahara renderer feature: the C# `EdgeDetectionFeature` renders a silhouette of objects on `avatarLayer` into a separate render target, and the shader reads that as `_AvatarMask`. Only pixels where the mask is white get edges drawn — this restricts the post-process to the avatar without affecting the background or other objects.

---

## Summary: when to use which edge shader

- **HierarchicalEdgeDetection** (Roberts Cross): use as the default. Lower cost, crisper fine detail, slight softness in the shader is usually desirable for NPR aesthetics.
- **SobelEdgeDetection**: use when you notice slightly dotted or directionally-biased artefacts on edges that run at 0° or 90°, or when you have a powerful GPU and want maximum smoothness for a cinematic render.

Both plug into the same `EdgeDetectionFeature` C# renderer feature — you just swap which shader asset is assigned in the Inspector.

---

## How all four parts connect in the rendering pipeline

```
1. Geometry pass:
   XToon_2DRamp.shader  →  toon-shaded avatar pixels in the colour buffer
   HalftoneHatching.shader → mark-making patterns on separate material objects

2. Post-process (after all geometry):
   AnisotropicKuwahara.shader  →  painterly smoothing on the full frame
   HierarchicalEdgeDetection / SobelEdgeDetection  →  post-process outlines drawn on top
```

XToon and HalftoneHatching express **per-material artistic intent** — they decide what each surface looks like. Kuwahara and edge detection express **global stylistic coherence** — they modify how the whole image reads as a piece of art.

Together they form a complete NPR pipeline: toon shading → painterly abstraction → crisp outlines.

In this project they are layered: XToon first gives the avatar its toon-shaded look, then Kuwahara adds the painterly abstraction on top as a screen-space filter.

---

---

# Part 5 — Inspector Variable Reference

Quick-lookup tables for every exposed control in every shader and renderer feature. Each row answers: *what does this slider/checkbox/dropdown actually change in the rendering?*

---

## 5.1 XToon_2DRamp — Material Inspector

### Base

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Base Color` | Color (RGBA) | Tint multiplied on top of the base texture. White = no tint. Use for per-material colour variations without swapping textures. |
| `Base Map` | Texture2D | The albedo/diffuse texture. Applied before any lighting. If none assigned, treated as solid white. |

### Toon Ramp

| Variable | Type | What it controls |
|----------|------|-----------------|
| `2D Toon Ramp` | Texture2D | The core XToon lookup texture. **U axis (horizontal)** = NdotL (0 = shadow, 1 = fully lit). **V axis (vertical)** = detail/abstraction level. The colour sampled from this texture replaces normal diffuse shading. |
| `Ramp Edge Smoothing` | 0 – 0.1 | Width of the antialiasing band at ramp colour transitions. 0 = sharp cartoon bands. Higher = softer gradient between zones. |
| `Light Sensitivity` | 0 – 1 | Scales the NdotL value before it is used as the ramp U coordinate. 0 = everything reads as fully lit (ramp U = 1 everywhere). 1 = full sensitivity to lighting angle. |

### Abstraction Control (V axis of the ramp)

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Detail Axis Mode` | Dropdown | **Depth**: V is driven by camera distance (far = abstract). **Curvature**: V driven by surface curvature (flat = abstract, curved = detailed). **Manual**: V set by `Manual Detail Level` slider only. |
| `Detail Bias` | 0 – 1 | Offsets the computed V value. Pushes all surfaces toward more-abstract or more-detailed ramp rows regardless of depth or curvature. |
| `Depth Near` | Float (metres) | Distance at which V = 0 (maximum detail). Objects closer than this always show full detail. |
| `Depth Far` | Float (metres) | Distance at which V = 1 (maximum abstraction). Objects farther than this show the most abstract ramp row. |
| `Manual Detail Level` | 0 – 1 | Direct artist override of V when mode is **Manual**. 0 = full detail row, 1 = most abstract row. |

### Normal Abstraction

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Normal Smoothing` | 0 – 1 | Blends between the mesh's real normals (0) and a simplified version via `ddx`/`ddy` derivatives (1). At 1, fine normal-map wrinkles disappear and the shading responds to large-scale shape only — making the avatar look more like an illustration. |
| `Abstract Normal Map` | Texture2D | Optional second normal map with fewer details. If assigned and `Use Abstract Normal Map` is on, used as the smoothed target instead of the derivative-based fallback. |
| `Use Abstract Normal Map` | Toggle | Switches between the derivative-computed smooth normal (off) and the `Abstract Normal Map` texture (on). |

### Shadow

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Shadow Color` | Color | Tint applied to areas in shadow. Defaults to a slightly blue-grey to mimic ambient sky bounce light (a common cartoon/anime convention). |
| `Shadow Strength` | 0 – 1 | How strongly the shadow tint replaces the lit colour. 0 = no shadow tinting. 1 = shadow areas become fully the shadow colour. |

### Texture vs Lighting

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Lighting Effects Strength` | 0 – 1 | Master blend between "texture only" and "texture + all lighting". At 0, specular and rim light contributions are removed and you see only the raw texture colour through the ramp. At 1, full specular, rim, and shadow are active. Useful to dial back lighting on secondary materials that should read as flat. |

### Specular

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Specular Color` | Color | Tint of the specular highlight. White = neutral glint. Coloured = stylised sheen (e.g. warm gold for hair). |
| `Specular Size` | 0 – 1 | Threshold for the NdotH value that triggers the highlight. Smaller = tighter, smaller highlight. Larger = wide soft gloss. |
| `Specular Smoothness` | 0.001 – 0.5 | Width of the smoothstep edge at the specular boundary. Near 0 = hard-edged anime glint. Higher = blurry softbox look. |
| `Specular Strength` | 0 – 1 | Overall opacity of the specular contribution. 0 = no specular. 1 = full blend toward specular colour. |

### Rim Light

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Rim Color` | Color | Colour of the edge glow — typically a warm or cool light to suggest a back-light source. |
| `Rim Power` | 0.5 – 10 | Sharpness of the rim falloff. High = thin crisp rim on silhouette edge only. Low = wide glow that bleeds further inward. Computed as `pow(1 - NdotV, _RimPower)`. |
| `Rim Threshold` | 0 – 1 | Minimum NdotL required for rim to appear. Prevents rim light from appearing on shadowed sides (which would look wrong — rim is a back-light, not a fill). |
| `Rim Strength` | 0 – 1 | Opacity of the rim contribution. 0 = invisible. 1 = full colour overlay. |

### Outline

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Outline Color` | Color | Colour of the inverted-hull outline stroke. |
| `Outline Width` | 0 – 0.05 | How far (in world-space units) the back-face hull is expanded along normals. Larger = thicker stroke. Note: this is world-space so the outline does not grow thinner as the camera zooms in — it stays consistent. |

### Alpha

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Alpha Blend (Eyelashes)` | Checkbox | When **on**: material switches to transparent (SrcAlpha / OneMinusSrcAlpha blend, ZWrite off, Transparent queue). For eyelashes or hair with soft alpha edges. When **off**: fully opaque (ZWrite on, Geometry queue). Toggling this also sets `_SrcBlend`, `_DstBlend`, and `_ZWrite` automatically via the `AlphaBlendToggleDrawer`. |
| `Alpha Cutoff (Shadow)` | 0 – 1 | Minimum alpha value below which the shadow caster clips the pixel. Prevents semi-transparent areas from casting solid shadows. |
| `__src / __dst / __zw` | Hidden | Internal blend state values written by the AlphaBlendToggle checkbox. Do not edit manually. |

### Debug

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Debug Mode` | Dropdown | **Off**: normal rendering. **NdotL**: shows raw lighting value as greyscale. **RampUV**: shows U,V ramp coordinates as red/green. **Albedo**: shows only the base texture, no lighting. **RampSample**: shows the raw colour sampled from the ramp texture. Useful to diagnose why lighting looks wrong. |

---

## 5.2 HalftoneHatching — Material Inspector

### Base

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Base Color` | Color | Tint multiplied on the base texture. |
| `Base Map` | Texture2D | The underlying diffuse texture. Combined with ink/paper colours via `_TextureInfluence`. |
| `Ink/Pattern Color` | Color | The colour of the drawn marks (lines, dots). Defaults to near-black blue to suggest ink. |
| `Paper Color` | Color | The colour of undrawn (lit) areas. Defaults to warm off-white to suggest paper. |
| `Texture Influence` | 0 – 1 | 0 = pure flat `Ink Color` and `Paper Color`. 1 = base texture drives both colours (ink tints the texture, paper = texture itself). Mid values blend. |

### Pattern Mode

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Pattern Mode` | Dropdown | **Halftone**: circular dot grid. **Hatching**: progressive line layers (TAM). **Stipple**: random noise dots. **Combined**: halftone in midtones + hatching in shadows simultaneously. Each mode compiles to a separate shader variant. |

### Halftone

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Dot Scale` | 2 – 100 | How many dot cells fit across the surface. Higher = finer dot pattern. |
| `Dot Sharpness` | 1 – 50 | How crisp the dot edge is. Low = blurry blobs. High = hard circles. |
| `Coordinate Space` | Dropdown | **ScreenSpace**: dots fixed on screen, shimmer when object moves. **ObjectSpace**: dots follow UV layout. **WorldSpace**: triplanar, dots anchored in world — best for stable environment art. |
| `Dot Grid Angle` | 0 – 90° | Rotation of the dot grid. 45° is the classic offset used in print to reduce moiré. |

### Hatching

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Hatch Style` | Dropdown | **Line**: classic parallel strokes. **Dots**: dots arranged along hatch directions. **Composition**: lighter areas use dots, darker areas use lines, blended by tone. |
| `Hatch Scale` | 1 – 100 | Line or dot density. Higher = more lines per unit area. |
| `Primary Hatch Angle` | 0 – 180° | Direction of the first hatch layer (lightest shadow). |
| `Line Thickness` | 0.01 – 0.5 | Width of each hatch line relative to the scale cell. |
| `Cross Hatch Angle` | 0 – 180° | Direction of the second hatch layer (deeper shadow). Typically set ~90° offset from primary. |
| `Dot Size` | 0.01 – 0.4 | Radius of dots in the Dots hatch style. |

### Stipple

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Stipple Scale` | 5 – 200 | Grid resolution for the noise hash. Higher = finer, denser dot field. |
| `Stipple Density` | 0 – 2 | Scales the brightness threshold. Below 1 = fewer dots overall. Above 1 = more dots even in bright areas, giving a noisy overprinted look. |

### Lighting Response

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Tone Levels` | 2 – 8 | Exposed for artist reference — labels how many discrete tone steps the TAM layers approximate. Does not currently gate any branch directly; the `smoothstep` envelopes in code handle transitions. |
| `Shadow Bias` | −0.5 – 0.5 | Shifts the whole tone curve. Positive = surface reads as lighter overall (fewer marks drawn). Negative = darker (more marks). |

### Outline

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Outline Color` | Color | Colour of the inverted-hull outline pass. |
| `Outline Width` | 0 – 0.05 | World-space hull expansion distance. Same method as XToon. |

### Surface

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Alpha` | 0 – 1 | Master opacity multiplier applied after texture alpha. |
| `Alpha Cutoff` | 0 – 1 | Clips pixels below this alpha value when `_ALPHATEST_ON` is enabled. |
| `__src / __dst / __zw` | Hidden | Blend state driven programmatically. |

---

## 5.3 KuwaharaFilterFeature — Renderer Feature Inspector

These controls live in the **URP Renderer Data** asset, not on a material.

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Render Pass Event` | Dropdown | When in the frame the Kuwahara pass executes. `AfterRenderingTransparents` is the default — runs after all geometry and transparent objects are drawn so the filter sees the complete scene. |
| `Kuwahara Shader` | Shader asset | The `AnisotropicKuwahara.shader` file. Must be assigned or the feature does nothing. |
| `Kernel Size` | 2 – 16 | Radius of the filter neighbourhood. Larger = more smoothing, more paint-stroke-like result, slower. Each increment roughly doubles visible brushstroke scale. |
| `Sector Count` | 4 – 8 | Number of anisotropic sectors around each pixel. More sectors = more angular resolution in stroke direction, finer result, slightly slower. 8 is the paper's recommendation. |
| `Sharpness` | 1 – 18 | How strongly the filter concentrates on the winning sector. High = crisp sector boundaries, more stylised. Low = sectors blend softly, more watercolour. |
| `Hardness` | 1 – 18 | Controls how quickly the Gaussian weight falls off with distance from sector centre. High = tight, responsive to local texture. Low = larger, smoother averages. |
| `Zero Crossing` | 0.3 – 0.8 | Phase parameter for the sector weighting function (from the paper's equation). Controls the angular sharpness of sector separation. 0.58 is the paper's recommended default — only change this for experimental looks. |
| `Avatar Layer` | LayerMask | If set, the Kuwahara effect is applied **only** to objects on this layer. Objects on other layers are composited back underneath. Leave as `Nothing` for a full-screen painterly effect. |

---

## 5.4 EdgeDetectionFeature — Renderer Feature Inspector

These also live in the **URP Renderer Data** asset. Both HierarchicalEdgeDetection and SobelEdgeDetection use this same feature.

### Edge Colors

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Edge Color` | Color (RGBA) | Colour of drawn outlines. Alpha controls maximum opacity — a semi-transparent edge colour gives softer lines. |

### Layer Thresholds

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Depth Threshold` | 0.01 – 5 | Minimum world-space depth jump (in metres) needed to draw a silhouette edge. Too low = edges appear inside smooth geometry. Too high = silhouettes between close objects are missed. |
| `Normal Threshold` | 0.05 – 2 | Minimum normal difference (in radians, approximately) to draw a crease edge. Low = every slight surface bend gets a line. High = only sharp hard edges. |
| `Color Threshold` | 0.01 – 1 | Minimum luminance/colour change to draw a texture boundary edge. Low = all texture detail gets outlined. High = only strong colour jumps produce lines. |

### Layer Weights

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Depth Weight` | 0 – 1 | Scale applied to the depth edge layer before max-pooling. 0 = silhouette edges suppressed entirely. 1 = full influence. |
| `Normal Weight` | 0 – 1 | Scale for the normal/crease layer. Setting to 0 removes all within-surface crease lines, leaving only outer silhouettes. |
| `Color Weight` | 0 – 1 | Scale for the colour detail layer. Often dialled down (0.3–0.5) on textured avatars to avoid noisy lines inside skin or fabric textures. |

### Style

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Edge Width` | 0.5 – 4 | Multiplier on the sampling offset kernel. Effectively scales all three edge layers simultaneously. Higher = thicker outlines at all detail levels. This interacts with the depth-aware projection scaling so the visual width stays consistent at different camera distances. |
| `Adaptive Strength` | 0 – 1 | How much dark areas reduce edge sensitivity. 0 = edges equally aggressive everywhere. 1 = edges in dark/shadow areas are heavily suppressed to avoid noise. |

### Depth Fade

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Fade With Depth` | Toggle | Enables depth-based edge fading. Off = equal edges at all distances. On = edges fade out between `Depth Fade Start` and `Depth Fade End`. |
| `Depth Fade Start` | Float (metres) | Distance at which outline opacity begins to reduce. |
| `Depth Fade End` | Float (metres) | Distance at which outlines are fully invisible. |

### Avatar Masking

| Variable | Type | What it controls |
|----------|------|-----------------|
| `Avatar Layer` | LayerMask | Restrict edge detection to objects on this layer only. Matching the same layer as the Kuwahara feature limits both effects to the avatar. Leave `Nothing` for full-scene edges. |
