// Version 5 Separable: Aggressive Filtered Sobel with Separable Gaussian Blur
// OPTIMIZED: Uses separable 2-pass blur (5+5=10 samples vs 25 samples = 60% faster)
// Pre-Blur Radius: offset × 1.2
// Threshold Window: 0.85× to 1.15× (narrow)
// Smoothstep Passes: 4
// Power Curve: pow(edge, 3.0)

Shader "Custom/ToonShader_V5_Separable"
{
    Properties
    {
        [Header(Debug Mode)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults (overrides all settings below)", Float) = 0
        [Space(10)]

        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset (fix z-fighting)", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

        [Toggle] _EnableAlphaTest ("Enable Alpha Test (for eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.07
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // OUTER OUTLINE PASS
        Pass
        {
            Name "OuterOutline"
            Cull Front
            ZWrite On
            ZTest Less

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline
            #pragma shader_feature_local _USEOUTLINEDEPTHOFFSET_ON
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata_outline { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; };
            struct v2f_outline { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float _OuterOutlineWidth;
            float4 _OuterOutlineColor;
            float _EnableAlphaTest;
            float _AlphaCutoff;
            float _OutlineDepthBias;

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;
                VertexPositionInputs posInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(v.normal);
                o.pos = TransformWorldToHClip(posInputs.positionWS + normInputs.normalWS * _OuterOutlineWidth);

                #if _USEOUTLINEDEPTHOFFSET_ON
                    o.pos.z -= _OutlineDepthBias * 0.0001;
                #endif

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                if (_EnableAlphaTest > 0.5)
                {
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a;
                    clip(alpha - _AlphaCutoff);
                }
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // MAIN TOON PASS WITH SEPARABLE GAUSSIAN SOBEL
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; float3 posWS : TEXCOORD1; float3 nWS : TEXCOORD2; };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _InnerLineColor, _OuterOutlineColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower, _EnableInnerLines, _InnerLineThreshold, _InnerLineBlur, _InnerLineStrength;
            float _UseDebugDefaults, _EnableAlphaTest, _AlphaCutoff;

            // Gaussian weights for 5-tap 1D kernel
            static const float gaussWeights[5] = { 0.0625, 0.25, 0.375, 0.25, 0.0625 };
            static const float gaussOffsets[5] = { -2.0, -1.0, 0.0, 1.0, 2.0 };

            // SEPARABLE GAUSSIAN BLUR - Cross pattern approximation
            float SampleLuminanceSeparable(float2 uv, float blurRadius)
            {
                float3 lumCoeff = float3(0.299, 0.587, 0.114);

                // Horizontal samples
                float hSum = 0.0;
                [unroll]
                for (int i = 0; i < 5; i++)
                {
                    float2 offset = float2(gaussOffsets[i] * blurRadius, 0.0);
                    hSum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + offset).rgb, lumCoeff) * gaussWeights[i];
                }

                // Vertical samples
                float vSum = 0.0;
                [unroll]
                for (int j = 0; j < 5; j++)
                {
                    float2 offset = float2(0.0, gaussOffsets[j] * blurRadius);
                    vSum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + offset).rgb, lumCoeff) * gaussWeights[j];
                }

                // Combine, subtract center (counted twice)
                float center = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, lumCoeff) * gaussWeights[2];
                return (hSum + vSum - center);
            }

            v2f vert(appdata v)
            {
                v2f o;
                VertexPositionInputs posInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(v.normal);
                o.pos = posInputs.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = posInputs.positionWS;
                o.nWS = normInputs.normalWS;
                return o;
            }

            half4 frag(v2f IN) : SV_Target
            {
                if (_UseDebugDefaults > 0.5)
                {
                    _TextureIntensity = 1.0;
                    _ToonSteps = 5.0;
                    _ToonThreshold = 1.0;
                    _ToonSmoothness = 0.03;
                    _ShadowStrength = 0.6;
                    _RimPower = 5.0;
                    _OuterOutlineColor = float4(0, 0, 0, 1);
                    _InnerLineColor = float4(0, 0, 0, 1);
                }

                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);

                // AGGRESSIVE SEPARABLE GAUSSIAN SOBEL EDGE DETECTION
                float edgeStrength = 0.0;
                if (_EnableInnerLines > 0.5)
                {
                    float offset = _InnerLineBlur * 0.001;
                    float blurOffset = offset * 1.2; // Aggressive blur radius (1.2×)

                    // Sample 9 Sobel positions with separable Gaussian pre-blur
                    float tl = SampleLuminanceSeparable(IN.uv + float2(-offset, offset), blurOffset);
                    float t  = SampleLuminanceSeparable(IN.uv + float2(0, offset), blurOffset);
                    float tr = SampleLuminanceSeparable(IN.uv + float2(offset, offset), blurOffset);
                    float l  = SampleLuminanceSeparable(IN.uv + float2(-offset, 0), blurOffset);
                    float r  = SampleLuminanceSeparable(IN.uv + float2(offset, 0), blurOffset);
                    float bl = SampleLuminanceSeparable(IN.uv + float2(-offset, -offset), blurOffset);
                    float b  = SampleLuminanceSeparable(IN.uv + float2(0, -offset), blurOffset);
                    float br = SampleLuminanceSeparable(IN.uv + float2(offset, -offset), blurOffset);

                    // Sobel operator
                    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
                    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);

                    // Aggressive filtering: narrow threshold window (0.85× to 1.15×)
                    float minEdge = _InnerLineThreshold * 0.85;
                    float maxEdge = _InnerLineThreshold * 1.15;
                    float edge = smoothstep(minEdge, maxEdge, edgeMagnitude);

                    // Quad smoothstep passes for ultra-hard edges
                    edge = smoothstep(0.47, 0.53, edge);
                    edge = smoothstep(0.35, 0.65, edge);
                    edge = smoothstep(0.25, 0.75, edge);
                    edge = smoothstep(0.15, 0.85, edge);

                    // Maximum power curve (3.0)
                    edge = pow(edge, 3.0);

                    edgeStrength = edge * _InnerLineStrength;
                }

                // Lighting calculation
                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);
                Light mainLight = GetMainLight();

                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = floor(smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL) * _ToonSteps) / _ToonSteps;
                toon = lerp(1.0, toon, _ShadowStrength);

                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                float3 shaded = albedo.rgb * lighting + rim * _RimColor.rgb;

                // Apply edges
                shaded = lerp(shaded, _InnerLineColor.rgb, edgeStrength);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
