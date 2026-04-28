// =============================================================================
// Sobel Edge Detection for NPR Outlines - Unity URP Post-Process
// =============================================================================
// Same three-layer hierarchical structure as HierarchicalEdgeDetection, but
// uses a full 3x3 Sobel operator instead of Roberts Cross.
//
// Sobel samples all 8 neighbours with Gx/Gy kernels, so horizontal, vertical,
// and diagonal edges are detected equally — no dotted-line artefact.
//
// Three detection layers:
//   Layer 1: Depth-based silhouettes
//   Layer 2: Normal-based creases
//   Layer 3: Color/luminance detail edges
//
// Requires: URP with Depth and Normals textures enabled in pipeline settings.
// Usage: Assign to EdgeDetectionFeature.edgeShader in the Renderer Feature.
// =============================================================================

Shader "Hidden/PostProcess/SobelEdgeDetection"
{
    Properties {}

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        Pass
        {
            Name "SobelEdges"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _DepthThreshold;
            float _NormalThreshold;
            float _ColorThreshold;

            float _DepthWeight;
            float _NormalWeight;
            float _ColorWeight;

            float4 _EdgeColor;
            float _EdgeWidth;

            float _AdaptiveStrength;

            float _FadeWithDepth;
            float _DepthFadeStart;
            float _DepthFadeEnd;

            TEXTURE2D_X(_AvatarMask);
            float _UseMask;

            // ---- Utility ----

            float GetLinearEyeDepth(float2 uv)
            {
                return LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
            }

            float3 GetWorldNormal(float2 uv)
            {
                return SampleSceneNormals(uv);
            }

            float Luminance3(float3 c)
            {
                return dot(c, float3(0.2126, 0.7152, 0.0722));
            }

            // ---- LAYER 1: Depth Silhouettes (Sobel) ----
            // Raw linear-eye-depth differences are in world-space metres — threshold
            // is an absolute depth jump, consistent at any camera distance.
            float ComputeDepthEdge(float2 uv, float2 off)
            {
                float tl = GetLinearEyeDepth(uv + float2(-off.x,  off.y));
                float t  = GetLinearEyeDepth(uv + float2(     0,  off.y));
                float tr = GetLinearEyeDepth(uv + float2( off.x,  off.y));
                float l  = GetLinearEyeDepth(uv + float2(-off.x,      0));
                float r  = GetLinearEyeDepth(uv + float2( off.x,      0));
                float bl = GetLinearEyeDepth(uv + float2(-off.x, -off.y));
                float b  = GetLinearEyeDepth(uv + float2(     0, -off.y));
                float br = GetLinearEyeDepth(uv + float2( off.x, -off.y));

                float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
                return sqrt(gx*gx + gy*gy);
            }

            // ---- LAYER 2: Normal Creases (Sobel per component) ----
            float ComputeNormalEdge(float2 uv, float2 off)
            {
                float3 tl = GetWorldNormal(uv + float2(-off.x,  off.y));
                float3 t  = GetWorldNormal(uv + float2(     0,  off.y));
                float3 tr = GetWorldNormal(uv + float2( off.x,  off.y));
                float3 l  = GetWorldNormal(uv + float2(-off.x,      0));
                float3 r  = GetWorldNormal(uv + float2( off.x,      0));
                float3 bl = GetWorldNormal(uv + float2(-off.x, -off.y));
                float3 b  = GetWorldNormal(uv + float2(     0, -off.y));
                float3 br = GetWorldNormal(uv + float2( off.x, -off.y));

                float3 gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float3 gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
                return sqrt(dot(gx, gx) + dot(gy, gy));
            }

            // ---- LAYER 3: Color/Luminance Edges (Sobel on luminance) ----
            float ComputeColorEdge(float2 uv, float2 off)
            {
                float3 c_tl = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x,  off.y), 0).rgb;
                float3 c_t  = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2(     0,  off.y), 0).rgb;
                float3 c_tr = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2( off.x,  off.y), 0).rgb;
                float3 c_l  = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x,      0), 0).rgb;
                float3 c_r  = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2( off.x,      0), 0).rgb;
                float3 c_bl = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2(-off.x, -off.y), 0).rgb;
                float3 c_b  = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2(     0, -off.y), 0).rgb;
                float3 c_br = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv + float2( off.x, -off.y), 0).rgb;

                float ltl = Luminance3(c_tl), lt = Luminance3(c_t), ltr = Luminance3(c_tr);
                float ll  = Luminance3(c_l),                         lr  = Luminance3(c_r);
                float lbl = Luminance3(c_bl), lb = Luminance3(c_b),  lbr = Luminance3(c_br);

                float gx = -ltl - 2.0*ll - lbl + ltr + 2.0*lr + lbr;
                float gy = -ltl - 2.0*lt - ltr + lbl + 2.0*lb + lbr;
                return sqrt(gx*gx + gy*gy);
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
                float3 centerColor = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_LinearClamp, uv, 0).rgb;
                float brightness = Luminance3(centerColor);
                float adaptiveFactor = lerp(1.0, saturate(brightness * 2.0), _AdaptiveStrength);

                // ---- Compute each layer ----
                float depthEdge  = ComputeDepthEdge(uv, offset);
                float normalEdge = ComputeNormalEdge(uv, offset);
                float colorEdge  = ComputeColorEdge(uv, offset);

                depthEdge  *= adaptiveFactor;
                colorEdge  *= adaptiveFactor;
                normalEdge *= lerp(1.0, adaptiveFactor, 0.5);

                // ---- Threshold each layer ----
                float depthLine  = smoothstep(_DepthThreshold  - 0.01, _DepthThreshold  + 0.01, depthEdge);
                float normalLine = smoothstep(_NormalThreshold - 0.02, _NormalThreshold + 0.02, normalEdge);
                float colorLine  = smoothstep(_ColorThreshold  - 0.01, _ColorThreshold  + 0.01, colorEdge);

                // ---- Fusion: Weighted Max-Pooling ----
                float edge = max(depthLine  * _DepthWeight,
                             max(normalLine * _NormalWeight,
                                 colorLine  * _ColorWeight));

                // ---- Depth-based edge fading (optional) ----
                if (_FadeWithDepth > 0.5)
                {
                    float depth = GetLinearEyeDepth(uv);
                    float fade = 1.0 - saturate(
                        (depth - _DepthFadeStart) / max(_DepthFadeEnd - _DepthFadeStart, 0.01));
                    edge *= fade;
                }

                // ---- Composite ----
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
