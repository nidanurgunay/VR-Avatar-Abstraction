// =============================================================================
// Hierarchical Edge Detection for NPR Outlines - Unity URP Post-Process
// =============================================================================
// Inspired by "AHEAD: Adaptive Hierarchical Edge Detection for Real-Time
// Artistic Stylization" and classic multi-layer NPR edge techniques.
//
// Three detection layers fused together:
//   Layer 1: Depth-based silhouettes (object boundaries, occlusion edges)
//   Layer 2: Normal-based creases (surface folds, hard edges)
//   Layer 3: Color/luminance detail edges (texture boundaries, fine detail)
//
// Fusion: Max-pooling across layers, with per-layer adaptive sensitivity
// that adjusts to local lighting conditions.
//
// Requires: URP with Depth and Normals textures enabled in pipeline settings.
// Usage: Add as a URP Renderer Feature
// =============================================================================

Shader "Hidden/PostProcess/HierarchicalEdgeDetection"
{
    Properties
    {
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "HierarchicalEdges"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            // Per-layer controls
            float _DepthThreshold;       // Sensitivity for depth edges (0.01 - 0.5)
            float _NormalThreshold;      // Sensitivity for normal edges (0.1 - 1.0)
            float _ColorThreshold;       // Sensitivity for color edges (0.05 - 0.5)

            float _DepthWeight;          // Blend weight for depth layer (0-1)
            float _NormalWeight;         // Blend weight for normal layer (0-1)
            float _ColorWeight;          // Blend weight for color layer (0-1)

            float4 _EdgeColor;           // Color of the outlines
            float _EdgeWidth;            // Width multiplier for sampling offset (1-3)

            // Adaptive sensitivity
            float _AdaptiveStrength;     // How much edges adapt to local brightness (0-1)

            // Style controls
            float _FadeWithDepth;        // Edges fade at distance (0=no, 1=full)
            float _DepthFadeStart;       // Distance where fading begins
            float _DepthFadeEnd;         // Distance where edges fully disappear

            // Avatar masking (optional)
            TEXTURE2D_X(_AvatarMask);
            float _UseMask;

            // ---- Utility functions ----

            float GetLinearEyeDepth(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            float3 GetWorldNormal(float2 uv)
            {
                return SampleSceneNormals(uv);
            }

            float Luminance3(float3 c)
            {
                return dot(c, float3(0.2126, 0.7152, 0.0722));
            }

            // Roberts Cross operator for a scalar field
            float RobertsCross(float tl, float tr, float bl, float br)
            {
                return abs(tl - br) + abs(tr - bl);
            }

            // ---- LAYER 1: Depth Silhouettes ----
            // Detects object boundaries using depth discontinuities.
            // Raw linear-eye-depth differences are in world-space metres, so the
            // threshold is an absolute depth jump, consistent at any camera distance.
            float ComputeDepthEdge(float2 uv, float2 offset)
            {
                float d_tl = GetLinearEyeDepth(uv + float2(-offset.x,  offset.y));
                float d_tr = GetLinearEyeDepth(uv + float2( offset.x,  offset.y));
                float d_bl = GetLinearEyeDepth(uv + float2(-offset.x, -offset.y));
                float d_br = GetLinearEyeDepth(uv + float2( offset.x, -offset.y));
                return RobertsCross(d_tl, d_tr, d_bl, d_br);
            }

            // ---- LAYER 2: Normal Creases ----
            // Detects surface folds and hard edges using normal discontinuities
            float ComputeNormalEdge(float2 uv, float2 offset)
            {
                float3 n_tl = GetWorldNormal(uv + float2(-offset.x,  offset.y));
                float3 n_tr = GetWorldNormal(uv + float2( offset.x,  offset.y));
                float3 n_bl = GetWorldNormal(uv + float2(-offset.x, -offset.y));
                float3 n_br = GetWorldNormal(uv + float2( offset.x, -offset.y));

                // Roberts Cross on each component, then combine
                float3 diff1 = abs(n_tl - n_br);
                float3 diff2 = abs(n_tr - n_bl);

                float edge = dot(diff1 + diff2, float3(1, 1, 1)) / 3.0;
                return edge;
            }

            // ---- LAYER 3: Color/Luminance Detail Edges ----
            // Detects texture boundaries and fine surface detail
            float ComputeColorEdge(float2 uv, float2 offset)
            {
                float3 c_tl = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp,
                    uv + float2(-offset.x,  offset.y), 0).rgb;
                float3 c_tr = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp,
                    uv + float2( offset.x,  offset.y), 0).rgb;
                float3 c_bl = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp,
                    uv + float2(-offset.x, -offset.y), 0).rgb;
                float3 c_br = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp,
                    uv + float2( offset.x, -offset.y), 0).rgb;

                // Use luminance for main detection, add color difference for chromatic edges
                float lumEdge = RobertsCross(
                    Luminance3(c_tl), Luminance3(c_tr),
                    Luminance3(c_bl), Luminance3(c_br));

                // Chromatic edge (catches color-only boundaries)
                float3 colDiff1 = abs(c_tl - c_br);
                float3 colDiff2 = abs(c_tr - c_bl);
                float chromaEdge = length(colDiff1 + colDiff2) * 0.3;

                return max(lumEdge, chromaEdge);
            }

            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;

                // Projection-aware world-space kernel.
                // projScale = cot(fov/2) * aspect — encodes both FOV and aspect ratio.
                // Dividing by depth AND projScale keeps the physical sampling distance
                // constant regardless of camera distance or zoom level.
                float centerDepth = GetLinearEyeDepth(uv);
                float2 projScale = float2(unity_CameraProjection[0][0],
                                          unity_CameraProjection[1][1]);
                float2 offset = _BlitTexture_TexelSize.xy * _EdgeWidth
                                 * projScale / max(centerDepth, 0.1);

                // ---- Adaptive Sensitivity ----
                // In dark areas, reduce sensitivity to avoid noisy edges
                float3 centerColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv, 0).rgb;
                float brightness = Luminance3(centerColor);
                float adaptiveFactor = lerp(1.0, saturate(brightness * 2.0), _AdaptiveStrength);

                // ---- Compute each layer ----
                float depthEdge  = ComputeDepthEdge(uv, offset);
                float normalEdge = ComputeNormalEdge(uv, offset);
                float colorEdge  = ComputeColorEdge(uv, offset);

                // Apply adaptive sensitivity per layer
                depthEdge  *= adaptiveFactor;
                colorEdge  *= adaptiveFactor;
                // Normal edges are less affected by brightness
                normalEdge *= lerp(1.0, adaptiveFactor, 0.5);

                // ---- Threshold each layer ----
                float depthLine  = smoothstep(_DepthThreshold - 0.01,
                    _DepthThreshold + 0.01, depthEdge);
                float normalLine = smoothstep(_NormalThreshold - 0.02,
                    _NormalThreshold + 0.02, normalEdge);
                float colorLine  = smoothstep(_ColorThreshold - 0.01,
                    _ColorThreshold + 0.01, colorEdge);

                // ---- Fusion: Weighted Max-Pooling ----
                // Each layer contributes based on its weight, fused with max
                float edge = max(depthLine * _DepthWeight,
                             max(normalLine * _NormalWeight,
                                 colorLine * _ColorWeight));

                // ---- Depth-based edge fading (optional) ----
                if (_FadeWithDepth > 0.5)
                {
                    float depth = GetLinearEyeDepth(uv);
                    float fade = 1.0 - saturate(
                        (depth - _DepthFadeStart) / max(_DepthFadeEnd - _DepthFadeStart, 0.01));
                    edge *= fade;
                }

                // ---- Composite edges over source image ----
                float4 source = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv, 0);
                float avatarMask = _UseMask > 0.5
                    ? SAMPLE_TEXTURE2D_X_LOD(_AvatarMask, sampler_LinearClamp, uv, 0).r
                    : 1.0;
                float3 result = lerp(source.rgb, _EdgeColor.rgb, edge * _EdgeColor.a * avatarMask);

                return float4(result, source.a);
            }
            ENDHLSL
        }
    }
}
