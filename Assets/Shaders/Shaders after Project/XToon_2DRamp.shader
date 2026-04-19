// =============================================================================
// X-Toon: Extended Toon Shader with 2D Ramp - Unity URP
// =============================================================================
// Based on Barla, Thollot & Markosian "X-Toon: An Extended Toon Shader"
// (NPAR 2006)
//
// Key concept: Replace the traditional 1D NdotL toon ramp with a 2D texture.
//   - U axis: lighting intensity (NdotL, same as classic toon)
//   - V axis: "tone detail" / abstraction level, driven by:
//     * Depth (objects farther away become more abstract)
//     * Curvature (flat areas simplify, curved areas keep detail)
//     * Custom parameter (artist control)
//
// Also implements Normal Field Abstraction: interpolate between original
// normals and a smoothed set for shape-level abstraction control.
//
// Usage: Assign to materials on 3D objects. Provide a 2D ramp texture.
//        The ramp's U axis = light intensity, V axis = detail level.
// =============================================================================

Shader "NPR/XToon_2DRamp"
{
    Properties
    {
        [Header(Base)]
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Map", 2D) = "white" {}

        [Header(Toon Ramp)]
        _ToonRamp ("2D Toon Ramp (U=NdotL, V=Detail)", 2D) = "white" {}
        _RampSmoothing ("Ramp Edge Smoothing", Range(0.0, 0.1)) = 0.01
        _LightSensitivity ("Light Sensitivity", Range(0.0, 1.0)) = 1.0

        [Header(Abstraction Control)]
        [KeywordEnum(Depth, Curvature, Manual)]
        _DetailMode ("Detail Axis Mode", Float) = 0
        _DetailBias ("Detail Bias", Range(0, 1)) = 0.5
        _DepthNear ("Depth Near (Full Detail)", Float) = 5.0
        _DepthFar ("Depth Far (Max Abstraction)", Float) = 50.0
        _ManualDetail ("Manual Detail Level", Range(0, 1)) = 0.0

        [Header(Normal Abstraction)]
        _NormalSmoothing ("Normal Smoothing (Shape Abstraction)", Range(0, 1)) = 0.0
        _AbstractNormalMap ("Abstract Normal Map (optional)", 2D) = "bump" {}
        _UseAbstractNormals ("Use Abstract Normal Map", Float) = 0

        [Header(Shadow)]
        _ShadowColor ("Shadow Color", Color) = (0.25, 0.25, 0.35, 1)
        _ShadowStrength ("Shadow Strength", Range(0.0, 1.0)) = 0.6

        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecularSize ("Specular Size", Range(0.0, 1.0)) = 0.03
        _SpecularSmoothness ("Specular Smoothness", Range(0.001, 0.5)) = 0.02
        _SpecularStrength ("Specular Strength", Range(0.0, 1.0)) = 0.5

        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
        _RimPower ("Rim Power", Range(0.5, 10.0)) = 3.0
        _RimThreshold ("Rim Threshold", Range(0, 1)) = 0.1
        _RimStrength ("Rim Strength", Range(0.0, 1.0)) = 0.3

        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.003

        [Header(Alpha)]
        [Toggle(_ALPHA_BLEND)] _AlphaBlend ("Alpha Blend (Eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff (Shadow)", Range(0.0, 1.0)) = 0.5

        [Header(Debug)]
        [KeywordEnum(Off, NdotL, RampUV, Albedo, RampSample)]
        _DebugMode ("Debug Mode", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Transparent"
        }

        // =================================================================
        // PASS 0: Main Toon Shading Pass
        // =================================================================
        Pass
        {
            Name "XToonForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma shader_feature_local _DETAILMODE_DEPTH _DETAILMODE_CURVATURE _DETAILMODE_MANUAL
            #pragma shader_feature_local _DEBUGMODE_OFF _DEBUGMODE_NDOTL _DEBUGMODE_RAMPUV _DEBUGMODE_ALBEDO _DEBUGMODE_RAMPSAMPLE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap);       SAMPLER(sampler_BaseMap);
            TEXTURE2D(_ToonRamp);      SAMPLER(sampler_ToonRamp);
            TEXTURE2D(_AbstractNormalMap); SAMPLER(sampler_AbstractNormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float _RampSmoothing;
                float _LightSensitivity;
                float _DetailBias;
                float _DepthNear;
                float _DepthFar;
                float _ManualDetail;
                float _NormalSmoothing;
                float _UseAbstractNormals;
                float4 _SpecularColor;
                float _SpecularSize;
                float _SpecularSmoothness;
                float4 _ShadowColor;
                float _ShadowStrength;
                float _SpecularStrength;
                float _RimStrength;
                float4 _RimColor;
                float _RimPower;
                float _RimThreshold;
                float _AlphaCutoff;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
                float3 tangentWS : TEXCOORD5;
                float3 bitangentWS : TEXCOORD6;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.tangentWS = normalInput.tangentWS;
                output.bitangentWS = normalInput.bitangentWS;
                output.viewDirWS = GetWorldSpaceNormalizeViewDir(vertexInput.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.shadowCoord = GetShadowCoord(vertexInput);

                return output;
            }

            // Compute the V coordinate of the 2D ramp based on chosen mode
            float ComputeDetailAxis(float3 posWS, float3 normalWS, float3 viewDir)
            {
                #if defined(_DETAILMODE_DEPTH)
                    float depth = length(_WorldSpaceCameraPos - posWS);
                    float t = saturate((depth - _DepthNear) / (_DepthFar - _DepthNear));
                    return lerp(0.0, 1.0, t) + _DetailBias;

                #elif defined(_DETAILMODE_CURVATURE)
                    float3 dNdx = ddx(normalWS);
                    float3 dNdy = ddy(normalWS);
                    float curvature = length(dNdx) + length(dNdy);
                    float t = 1.0 - saturate(curvature * 10.0);
                    return t * (1.0 - _DetailBias) + _DetailBias;

                #else // _DETAILMODE_MANUAL
                    return _ManualDetail;
                #endif
            }

            float4 frag(Varyings input) : SV_Target
            {
                // --- Normal Abstraction ---
                float3 normalWS = normalize(input.normalWS);

                if (_UseAbstractNormals > 0.5)
                {
                    float3 abstractN = UnpackNormal(
                        SAMPLE_TEXTURE2D(_AbstractNormalMap, sampler_AbstractNormalMap, input.uv));
                    float3x3 TBN = float3x3(input.tangentWS, input.bitangentWS, normalWS);
                    float3 abstractWS = normalize(mul(abstractN, TBN));
                    normalWS = normalize(lerp(normalWS, abstractWS, _NormalSmoothing));
                }
                else
                {
                    float3 smoothN = normalize(
                        normalWS + _NormalSmoothing * (normalize(input.positionWS) - normalWS));
                    normalWS = normalize(lerp(normalWS, smoothN, _NormalSmoothing * 0.5));
                }

                float3 viewDir = normalize(input.viewDirWS);

                // --- Lighting ---
                Light mainLight = GetMainLight(input.shadowCoord);
                float3 lightDir = normalize(mainLight.direction);
                float NdotL = dot(normalWS, lightDir);

                float shadow = mainLight.shadowAttenuation;
                NdotL = NdotL * shadow;

                // Lerp toward 0.5 (ramp center) to reduce light sensitivity
                float rampU = lerp(0.5, saturate(NdotL * 0.5 + 0.5), _LightSensitivity);

                // --- Detail Axis (V coordinate of 2D ramp) ---
                float rampV = saturate(ComputeDetailAxis(input.positionWS, normalWS, viewDir));

                // --- Sample 2D Toon Ramp ---
                float3 rampColor = SAMPLE_TEXTURE2D(_ToonRamp, sampler_ToonRamp,
                    float2(rampU, rampV)).rgb;

                // --- Base color ---
                float4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                float3 albedo = baseMap.rgb * _BaseColor.rgb;

                // Use ramp.r as shadow mask: lit areas (ramp=1) show full albedo,
                // shadow areas (ramp=0) blend toward shadow color.
                float shadowMask = rampColor.r;
                float3 shadowedAlbedo = lerp(albedo * _ShadowColor.rgb, albedo, shadowMask);
                float3 finalColor = lerp(albedo, shadowedAlbedo, _ShadowStrength);

                // --- Specular (stylized) ---
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = dot(normalWS, halfDir);
                float specular = smoothstep(1.0 - _SpecularSize - _SpecularSmoothness,
                                            1.0 - _SpecularSize + _SpecularSmoothness,
                                            NdotH) * shadow;
                finalColor = lerp(finalColor, _SpecularColor.rgb, specular * _SpecularStrength);

                // --- Rim Light ---
                float NdotV = dot(normalWS, viewDir);
                float rim = 1.0 - saturate(NdotV);
                rim = smoothstep(_RimThreshold - 0.01, _RimThreshold + 0.01,
                    rim * pow(saturate(NdotL + 0.5), 0.2));
                finalColor = lerp(finalColor, _RimColor.rgb, rim * _RimStrength);

                // --- Debug Output ---
                #if defined(_DEBUGMODE_NDOTL)
                    // Shows NdotL as grayscale — should NOT be all white
                    float debugNdotL = saturate(NdotL * 0.5 + 0.5);
                    return float4(debugNdotL, debugNdotL, debugNdotL, 1);
                #elif defined(_DEBUGMODE_RAMPUV)
                    // Shows rampU (red) and rampV (green) — lets you see what UV is being sampled
                    return float4(rampU, rampV, 0, 1);
                #elif defined(_DEBUGMODE_ALBEDO)
                    // Shows just the base texture color — should show your diffuse
                    return float4(albedo, 1);
                #elif defined(_DEBUGMODE_RAMPSAMPLE)
                    // Shows just the ramp sample — should show colors from your ramp texture
                    return float4(rampColor, 1);
                #endif

                return float4(finalColor, baseMap.a * _BaseColor.a);
            }
            ENDHLSL
        }

        // =================================================================
        // PASS 1: Outline Pass (inverted hull method)
        // =================================================================
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }

            Cull Front

            HLSLPROGRAM
            #pragma vertex vertOutline
            #pragma fragment fragOutline

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vertOutline(Attributes input)
            {
                Varyings output;
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                posWS += normalWS * _OutlineWidth;
                output.positionCS = TransformWorldToHClip(posWS);
                return output;
            }

            float4 fragOutline(Varyings input) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }

        // =================================================================
        // PASS 2: Shadow Caster (self-contained, no UsePass)
        // =================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            float3 _LightDirection;
            float3 _LightPosition;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _AlphaCutoff;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            Varyings ShadowVert(Attributes input)
            {
                Varyings output;
                output.positionCS = GetShadowPositionHClip(input);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 ShadowFrag(Varyings input) : SV_TARGET
            {
                float alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                clip(alpha - _AlphaCutoff);
                return 0;
            }
            ENDHLSL
        }

        // =================================================================
        // PASS 3: Depth Only (self-contained, no UsePass)
        // =================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _AlphaCutoff;
            CBUFFER_END

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

            Varyings DepthVert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 DepthFrag(Varyings input) : SV_TARGET
            {
                float alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                clip(alpha - _AlphaCutoff);
                return 0;
            }
            ENDHLSL
        }
    }

    // No CustomEditor 
}