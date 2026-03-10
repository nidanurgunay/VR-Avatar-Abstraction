# Abstracting Realistic VR Avatars Using Toon Shading and Edge Detection

A Unity URP project implementing and comparing four non-photorealistic rendering (NPR) techniques for VR avatar stylisation. Developed as part of a practical research study evaluating toon shading and edge detection approaches for real-time use.

📄 **Full report**: `NidanurGunay_Project_Report.pdf`

---

## Overview

Photorealistic VR avatars risk triggering the uncanny valley effect. This project explores toon/cel shading as an alternative, progressively introducing different edge detection methods to evaluate their suitability for VR avatar rendering.

Four shader versions are implemented and compared:

| Version | Shader | Technique |
|---------|--------|-----------|
| V1 | `V1_ToonShading_GeometryOutline` | Quantised toon shading + geometry-expansion silhouette outline |
| V2 | `V2_NormalEdgeDetection` | V1 + screen-space normal edge detection (ddx/ddy derivatives) |
| V3 | `V3_SobelEdgeDetection` | V1 + texture-based Sobel edge detection (raw, no pre-filtering) |
| V4 | `V4_GaussianPreFilteredSobel` | V1 + Gaussian pre-filtered Sobel with multi-pass smoothstep sharpening |

---

## Key Findings

- **Geometry outlines (V1)** provide stable, distance-independent silhouettes — best choice for VR
- **Normal-based edges (V2)** produce distance-dependent artefacts, unsuitable for variable-distance VR scenarios
- **Raw Sobel (V3)** detects internal texture features but is extremely parameter-sensitive (especially on facial regions)
- **Gaussian-filtered Sobel (V4)** compresses artefacts at lower thresholds but does not clearly outperform well-tuned V3 — the primary effect is smoother inner lines at 81 texture samples/fragment vs V3's 9

---

## Project Structure

```
Assets/
├── Shaders/
│   ├── V1_ToonShading_GeometryOutline.shader   # V1: Base toon + geometry outline
│   ├── V2_NormalEdgeDetection.shader           # V2: Normal-based edge detection
│   ├── V3_SobelEdgeDetection.shader            # V3: Raw Sobel inner lines
│   ├── V4_GaussianPreFilteredSobel.shader      # V4: Gaussian pre-filtered Sobel
│   └── *.shadergraph                     # Shader graph experiments
├── Materials/
│   ├── CToon V1 Toon only/               # V1 materials (body, hair, clothing, eyelash)
│   ├── CToon V2 Sobel/                   # V3 materials
│   ├── Ctoon V7 Combined/               # V2 materials
│   ├── CToon V10/                        # V4 materials
│   └── Original/                         # Unmodified PBR avatar materials
├── Characters/
│   └── Jade.fbx                          # Humanoid avatar (Mixamo rig)
├── Scenes/
│   └── Custom Shader.unity               # Main comparison scene
└── Animations/                           # Idle animation + animator controller
```

---

## Setup

**Requirements:** Unity 2022.3 LTS or later, Universal Render Pipeline (URP)

1. Clone the repository
2. Open in Unity 2022.3+
3. Open `Assets/Scenes/Custom Shader.unity`
4. Select avatar in the scene and swap materials to compare shader versions

Each version's materials are pre-configured in the corresponding `Materials/` subfolder.

---

## Techniques

### Toon Shading (all versions)
Quantised diffuse lighting using the `floor()` function on Lambert dot product, producing discrete shading bands.

### Geometry-Expansion Outline (all versions)
Inverted hull method: back-face pass expands vertices along normals in world space, producing distance-independent silhouettes.

### Normal-Based Edge Detection (V2)
Screen-space derivative computation via HLSL `ddx()`/`ddy()` intrinsics. Detects surface orientation discontinuities without additional texture samples.

### Sobel Edge Detection (V3, V4)
3×3 convolution kernel applied to texture luminance. Detects colour/intensity boundaries in painted texture features (facial details, clothing).

### Gaussian Pre-Filtering (V4)
9-tap Gaussian approximation applied at each of the 9 Sobel sample positions — 81 texture samples total. Suppresses high-frequency noise before differentiation.

---

## Report

The full academic report is included as `NidanurGunay_Project_Report.pdf`, covering:
- Related work (NPR, silhouette rendering, edge detection theory)
- Methodology and implementation details
- Per-version results with observations
- Discussion with comparison tables
- Conclusion and practical recommendations

---

## Requirements

- Unity 2022.3 LTS or later
- Universal Render Pipeline (URP)
- XR Interaction Toolkit (included in project)
