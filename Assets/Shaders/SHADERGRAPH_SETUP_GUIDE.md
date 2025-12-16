# Shader Graph Setup Guide: Adding Texture Edge Detection

## Overview
This guide shows how to add texture-based line detection to your toon shader in Shader Graph. This will reveal details like lip lines, eye features, and other texture details that would otherwise be lost in the cel shading.

## Required Files
- **Custom Function**: [TextureEdgeDetection.hlsl](TextureEdgeDetection.hlsl) (already created)
- **Target Shader**: ToonShaderGraph_2.shadergraph

## Step-by-Step Node Setup

### 1. Add Required Properties
First, add these properties to your shader graph:

- **Line Color** (Color, default: Black)
- **Line Threshold** (Float, Range: 0.001 to 0.1, default: 0.05)
- **Line Sample Distance** (Float, Range: 0.5 to 10, default: 1.0)
- **Enable Texture Lines** (Boolean, default: true)

### 2. Create the Custom Function Node
1. Right-click in the graph → **Create Node** → **Custom Function**
2. Name it "Texture Edge Detection"
3. **Set Type to "File"**
4. **Select File**: Navigate to `Assets/Shaders/TextureEdgeDetection.hlsl`
5. **Set Name** to: `TextureEdgeDetection_float`

### 3. Configure Custom Function Inputs/Outputs
The node should automatically detect these parameters:

**Inputs:**
- `MainTex` (Texture2D) - Connect your main texture here
- `MainTexSampler` (SamplerState) - Connect the sampler from your texture
- `UV` (Vector2) - Connect your UV coordinates
- `Threshold` (Float) - Connect your "Line Threshold" property
- `SampleDistance` (Float) - Connect your "Line Sample Distance" property

**Output:**
- `Edge` (Float) - Returns 1.0 where lines detected, 0.0 elsewhere

### 4. Wire the Nodes

```
[Main Texture Property] → [Sample Texture 2D]
                              ↓
                         [Split] (to get sampler)
                              ↓
                     [Custom Function: TextureEdgeDetection]
                              ↑
[UV Property] ────────────────┘
[Line Threshold Property] ────┘
[Line Sample Distance Property] ┘

[Custom Function Output: Edge] → [Lerp Node (A input)]
                                       ↓
[Your Shaded Color] → [Lerp Node (B input)]
[Line Color Property] → [Lerp Node (T input)]
                                       ↓
                              [Final Output Color]
```

### 5. Detailed Connection Flow

**Main Path:**
```
1. Sample your texture normally for base color/albedo
2. Apply your toon shading (stepped lighting, etc.)
3. Calculate rim lighting, ambient, etc.
4. This gives you "shaded color"

Parallel Edge Detection Path:
1. Use the SAME texture sample
2. Feed into Custom Function node with UV + parameters
3. Get Edge output (0 or 1)

Final Composite:
1. Use Lerp node: Lerp(shaded color, line color, edge value)
2. Where edge = 1, you get line color (black)
3. Where edge = 0, you get your shaded color
4. Connect to Fragment output
```

### 6. Optional: Branch Node for Toggle
To make the texture lines optional:

```
[Enable Texture Lines Boolean] → [Branch Node: Condition]
[Lerped Result] → [Branch Node: True]
[Original Shaded Color] → [Branch Node: False]
[Branch Output] → [Fragment Output]
```

## Alternative Functions Available

### Smooth Edges (TextureEdgeDetectionSmooth_float)
Better for organic features like facial details. Requires additional "Smoothness" parameter (0.001-0.01).

### 8-Direction Sampling (TextureEdgeDetection8Dir_float)
More accurate but more expensive. Samples 8 directions instead of 4.

## Recommended Settings by Feature

### For Lip Lines
- Threshold: 0.03-0.05
- Sample Distance: 1.0-2.0
- Line Color: Dark red or black

### For Eye Details
- Threshold: 0.04-0.06
- Sample Distance: 0.5-1.5
- Line Color: Black or dark brown

### For General Facial Features
- Threshold: 0.05-0.08
- Sample Distance: 1.0-3.0
- Line Color: Black

## Troubleshooting

**Lines too thick/noisy:**
- Increase Threshold value
- Decrease Sample Distance

**Can't see lines:**
- Decrease Threshold value (try 0.02)
- Increase Sample Distance
- Make sure your texture has sufficient detail/contrast
- Check that texture is properly sampled (not using flat color)

**Artifacts in eyes:**
- May need separate material for eyes with different threshold
- Consider using smoother variant of edge detection
- Reduce sample distance for finer details

**Performance issues in VR:**
- Use 4-direction version (default)
- Increase threshold to reduce line density
- Consider using only on close-up objects

## Testing in Unity
1. Save the shader graph
2. Unity will auto-compile
3. Select your material in the Hierarchy
4. Adjust properties in the Inspector in real-time
5. Enter Play mode to test in VR lighting conditions

## Performance Notes
- **Cost**: ~5 extra texture samples (4-direction) or ~9 (8-direction)
- **VR Impact**: Minimal on modern headsets (Quest 2+)
- **Recommendation**: Use LOD to disable on distant objects
