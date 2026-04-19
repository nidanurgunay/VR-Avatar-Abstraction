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
            TEXTURE2D(_AvatarMask);
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

            // ---- LAYER 1: Depth Silhouettes ----
            float ComputeDepthEdge(float2 uv, float2 offset)
            {
                float tl = GetLinearEyeDepth(uv + float2(-offset.x,  offset.y));
                float t  = GetLinearEyeDepth(uv + float2(       0,   offset.y));
                float tr = GetLinearEyeDepth(uv + float2( offset.x,  offset.y));
                float l  = GetLinearEyeDepth(uv + float2(-offset.x,        0));
                float r  = GetLinearEyeDepth(uv + float2( offset.x,        0));
                float bl = GetLinearEyeDepth(uv + float2(-offset.x, -offset.y));
                float b  = GetLinearEyeDepth(uv + float2(       0,  -offset.y));
                float br = GetLinearEyeDepth(uv + float2( offset.x, -offset.y));

                float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;

                float centerDepth = GetLinearEyeDepth(uv);
                float normalizer = max(centerDepth * 0.1, 0.01);
                return sqrt(gx*gx + gy*gy) / normalizer;
            }

            // ---- LAYER 2: Normal Creases ----
            float ComputeNormalEdge(float2 uv, float2 offset)
            {
                float3 tl = GetWorldNormal(uv + float2(-offset.x,  offset.y));
                float3 t  = GetWorldNormal(uv + float2(       0,   offset.y));
                float3 tr = GetWorldNormal(uv + float2( offset.x,  offset.y));
                float3 l  = GetWorldNormal(uv + float2(-offset.x,        0));
                float3 r  = GetWorldNormal(uv + float2( offset.x,        0));
                float3 bl = GetWorldNormal(uv + float2(-offset.x, -offset.y));
                float3 b  = GetWorldNormal(uv + float2(       0,  -offset.y));
                float3 br = GetWorldNormal(uv + float2( offset.x, -offset.y));

                float3 gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float3 gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
                return sqrt(dot(gx, gx) + dot(gy, gy));
            }

            // ---- LAYER 3: Color/Luminance Detail Edges ----
            float ComputeColorEdge(float2 uv, float2 offset)
            {
                float3 c_tl = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,  offset.y)).rgb;
                float3 c_t  = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(       0,   offset.y)).rgb;
                float3 c_tr = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,  offset.y)).rgb;
                float3 c_l  = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x,        0)).rgb;
                float3 c_r  = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x,        0)).rgb;
                float3 c_bl = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-offset.x, -offset.y)).rgb;
                float3 c_b  = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(       0,  -offset.y)).rgb;
                float3 c_br = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( offset.x, -offset.y)).rgb;

                float ltl = Luminance3(c_tl), lt = Luminance3(c_t), ltr = Luminance3(c_tr);
                float ll  = Luminance3(c_l),                         lr  = Luminance3(c_r);
                float lbl = Luminance3(c_bl), lb = Luminance3(c_b),  lbr = Luminance3(c_br);

                float gx = -ltl - 2.0*ll - lbl + ltr + 2.0*lr + lbr;
                float gy = -ltl - 2.0*lt - ltr + lbl + 2.0*lb + lbr;
                return sqrt(gx*gx + gy*gy);
            }

            float4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float centerDepth = GetLinearEyeDepth(uv);
                float2 offset = _BlitTexture_TexelSize.xy * _EdgeWidth;

                // ---- Adaptive Sensitivity ----
                // In dark areas, reduce sensitivity to avoid noisy edges
                float3 centerColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
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
                float4 source = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                float avatarMask = _UseMask > 0.5
                    ? SAMPLE_TEXTURE2D(_AvatarMask, sampler_LinearClamp, uv).r
                    : 1.0;
                float3 result = lerp(source.rgb, _EdgeColor.rgb, edge * _EdgeColor.a * avatarMask);

                return float4(result, source.a);
            }
            ENDHLSL
        }
    }
}
