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
        _MainTex ("Texture", 2D) = "white" {}
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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_TexelSize;

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

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

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
            // Detects object boundaries using depth discontinuities
            float ComputeDepthEdge(float2 uv, float2 offset)
            {
                float d_tl = GetLinearEyeDepth(uv + float2(-offset.x,  offset.y));
                float d_tr = GetLinearEyeDepth(uv + float2( offset.x,  offset.y));
                float d_bl = GetLinearEyeDepth(uv + float2(-offset.x, -offset.y));
                float d_br = GetLinearEyeDepth(uv + float2( offset.x, -offset.y));

                float centerDepth = GetLinearEyeDepth(uv);

                // Normalize by center depth for scale-invariance
                float normalizer = max(centerDepth * 0.1, 0.01);
                float edge = RobertsCross(d_tl, d_tr, d_bl, d_br) / normalizer;

                return edge;
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
                float3 c_tl = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,
                    uv + float2(-offset.x,  offset.y)).rgb;
                float3 c_tr = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,
                    uv + float2( offset.x,  offset.y)).rgb;
                float3 c_bl = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,
                    uv + float2(-offset.x, -offset.y)).rgb;
                float3 c_br = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex,
                    uv + float2( offset.x, -offset.y)).rgb;

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
                float2 uv = input.uv;
                float2 offset = _MainTex_TexelSize.xy * _EdgeWidth;

                // ---- Adaptive Sensitivity ----
                // In dark areas, reduce sensitivity to avoid noisy edges
                float3 centerColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;
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
                float4 source = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                float3 result = lerp(source.rgb, _EdgeColor.rgb, edge * _EdgeColor.a);

                return float4(result, source.a);
            }
            ENDHLSL
        }
    }
}
