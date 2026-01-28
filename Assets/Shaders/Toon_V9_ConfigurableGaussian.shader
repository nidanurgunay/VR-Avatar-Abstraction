// Version 9: Configurable Gaussian Blur Edge Detection
// All Gaussian blur and edge filtering parameters are exposed for user adjustment
// Allows fine-tuning between light filtering (like V3) and aggressive filtering (like V5)

Shader "Custom/ToonShader_V9_ConfigurableGaussian"
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

        [Header(Inner Lines Basic)]
        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

        [Header(Filtering Presets)]
        [Toggle] _UseLightFiltering ("Light Filtering (V3 style)", Float) = 0
        [Toggle] _UseModerateFiltering ("Moderate Filtering (V4 style)", Float) = 0
        [Toggle] _UseAggressiveFiltering ("Aggressive Filtering (V5 style)", Float) = 0
        [Space(10)]

        [Header(Gaussian Blur Settings)]
        _BlurRadiusMultiplier ("Blur Radius Multiplier", Range(0.1, 10.0)) = 0.8
        _GaussianCenterWeight ("Center Weight", Range(0.0, 1.0)) = 0.25
        _GaussianCardinalWeight ("Cardinal Weight (per sample)", Range(0.0, 0.5)) = 0.125
        _GaussianDiagonalWeight ("Diagonal Weight (per sample)", Range(0.0, 0.25)) = 0.0625

        [Header(Edge Threshold Settings)]
        _ThresholdMinMultiplier ("Threshold Min Multiplier", Range(0.0, 1.0)) = 0.2
        _ThresholdMaxMultiplier ("Threshold Max Multiplier", Range(1.0, 5.0)) = 2.0

        [Header(Smoothstep Filtering)]
        _SmoothstepPasses ("Smoothstep Passes (1-4)", Range(1, 4)) = 2
        _SmoothstepTightness ("Smoothstep Tightness", Range(0.0, 1.0)) = 0.2
        _PowerCurve ("Power Curve (noise suppression)", Range(0.5, 5.0)) = 1.5

        [Header(Rim and Ambient)]
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

        [Header(Alpha Test)]
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

        // MAIN TOON PASS WITH CONFIGURABLE GAUSSIAN BLUR
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

            // Filtering preset toggles
            float _UseLightFiltering;
            float _UseModerateFiltering;
            float _UseAggressiveFiltering;

            // Configurable Gaussian blur parameters
            float _BlurRadiusMultiplier;
            float _GaussianCenterWeight;
            float _GaussianCardinalWeight;
            float _GaussianDiagonalWeight;
            float _ThresholdMinMultiplier;
            float _ThresholdMaxMultiplier;
            float _SmoothstepPasses;
            float _SmoothstepTightness;
            float _PowerCurve;

            // Helper function: Sample with configurable 9-tap Gaussian blur
            float SampleLuminanceBlurred(float2 uv, float blurRadius,
                float centerW, float cardinalW, float diagonalW)
            {
                float lum = 0.0;
                float3 lumCoeff = float3(0.299, 0.587, 0.114);

                // Center sample
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, lumCoeff) * centerW;

                // Cardinal samples (4 directions)
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, 0)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, 0)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, blurRadius)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, -blurRadius)).rgb, lumCoeff) * cardinalW;

                // Diagonal samples (4 corners)
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, blurRadius)).rgb, lumCoeff) * diagonalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, blurRadius)).rgb, lumCoeff) * diagonalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, -blurRadius)).rgb, lumCoeff) * diagonalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, -blurRadius)).rgb, lumCoeff) * diagonalW;

                return lum;
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
                // Local copies for modification
                float textureIntensity = _TextureIntensity;
                float toonSteps = _ToonSteps;
                float toonThreshold = _ToonThreshold;
                float toonSmoothness = _ToonSmoothness;
                float shadowStrength = _ShadowStrength;
                float rimPower = _RimPower;
                float4 outerOutlineColor = _OuterOutlineColor;
                float4 innerLineColor = _InnerLineColor;

                if (_UseDebugDefaults > 0.5)
                {
                    textureIntensity = 1.0;
                    toonSteps = 5.0;
                    toonThreshold = 1.0;
                    toonSmoothness = 0.03;
                    shadowStrength = 0.6;
                    rimPower = 5.0;
                    outerOutlineColor = float4(0, 0, 0, 1);
                    innerLineColor = float4(0, 0, 0, 1);
                }

                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, textureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);

                // CONFIGURABLE GAUSSIAN BLUR SOBEL EDGE DETECTION
                float edgeStrength = 0.0;
                if (_EnableInnerLines > 0.5)
                {
                    // Get blur parameters (use presets if enabled, otherwise use custom values)
                    float blurRadiusMult = _BlurRadiusMultiplier;
                    float gaussCenterW = _GaussianCenterWeight;
                    float gaussCardinalW = _GaussianCardinalWeight;
                    float gaussDiagonalW = _GaussianDiagonalWeight;
                    float threshMinMult = _ThresholdMinMultiplier;
                    float threshMaxMult = _ThresholdMaxMultiplier;
                    float smoothPasses = _SmoothstepPasses;
                    float smoothTightness = _SmoothstepTightness;
                    float powerCurve = _PowerCurve;

                    // Light Filtering Preset (V3 style) - soft edges, wide threshold
                    if (_UseLightFiltering > 0.5)
                    {
                        blurRadiusMult = 0.8;
                        gaussCenterW = 0.25;
                        gaussCardinalW = 0.125;
                        gaussDiagonalW = 0.0625;
                        threshMinMult = 0.2;
                        threshMaxMult = 2.0;
                        smoothPasses = 2.0;
                        smoothTightness = 0.2;
                        powerCurve = 1.5;
                    }

                    // Moderate Filtering Preset (V4 style) - balanced
                    if (_UseModerateFiltering > 0.5)
                    {
                        blurRadiusMult = 1.0;
                        gaussCenterW = 0.3;
                        gaussCardinalW = 0.12;
                        gaussDiagonalW = 0.05;
                        threshMinMult = 0.4;
                        threshMaxMult = 1.6;
                        smoothPasses = 3.0;
                        smoothTightness = 0.3;
                        powerCurve = 2.0;
                    }

                    // Aggressive Filtering Preset (V5 style) - hard edges, narrow threshold
                    // Uses tightness = 1.0 to exactly match V5's progressive smoothstep ranges
                    if (_UseAggressiveFiltering > 0.5)
                    {
                        blurRadiusMult = 1.2;
                        gaussCenterW = 0.25;
                        gaussCardinalW = 0.125;
                        gaussDiagonalW = 0.0625;
                        threshMinMult = 0.85;
                        threshMaxMult = 1.15;
                        smoothPasses = 4.0;
                        smoothTightness = 1.0;  // 1.0 = exact V5 match
                        powerCurve = 3.0;
                    }

                    float offset = _InnerLineBlur * 0.001;
                    float blurOffset = offset * blurRadiusMult;

                    // Normalize weights to ensure they sum to 1.0
                    float totalWeight = gaussCenterW + 4.0 * gaussCardinalW + 4.0 * gaussDiagonalW;
                    float centerW = gaussCenterW / totalWeight;
                    float cardinalW = gaussCardinalW / totalWeight;
                    float diagonalW = gaussDiagonalW / totalWeight;

                    // Sample 9 positions with configurable Gaussian pre-blur
                    float tl = SampleLuminanceBlurred(IN.uv + float2(-offset, offset), blurOffset, centerW, cardinalW, diagonalW);
                    float t  = SampleLuminanceBlurred(IN.uv + float2(0, offset), blurOffset, centerW, cardinalW, diagonalW);
                    float tr = SampleLuminanceBlurred(IN.uv + float2(offset, offset), blurOffset, centerW, cardinalW, diagonalW);
                    float l  = SampleLuminanceBlurred(IN.uv + float2(-offset, 0), blurOffset, centerW, cardinalW, diagonalW);
                    float r  = SampleLuminanceBlurred(IN.uv + float2(offset, 0), blurOffset, centerW, cardinalW, diagonalW);
                    float bl = SampleLuminanceBlurred(IN.uv + float2(-offset, -offset), blurOffset, centerW, cardinalW, diagonalW);
                    float b  = SampleLuminanceBlurred(IN.uv + float2(0, -offset), blurOffset, centerW, cardinalW, diagonalW);
                    float br = SampleLuminanceBlurred(IN.uv + float2(offset, -offset), blurOffset, centerW, cardinalW, diagonalW);

                    // Sobel operator
                    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
                    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);

                    // Configurable threshold window
                    float minEdge = _InnerLineThreshold * threshMinMult;
                    float maxEdge = _InnerLineThreshold * threshMaxMult;
                    float edge = smoothstep(minEdge, maxEdge, edgeMagnitude);

                    // Progressive smoothstep passes (matches V5 exactly when tightness = 1.0)
                    // V5 uses: Pass1(0.47,0.53), Pass2(0.35,0.65), Pass3(0.25,0.75), Pass4(0.15,0.85)
                    float tightness = smoothTightness;
                    int passes = (int)smoothPasses;

                    // Pass 1: Tightest window (0.03 half-width at t=1.0)
                    // V5: smoothstep(0.47, 0.53) = 0.5 ± 0.03
                    float hw1 = lerp(0.5, 0.03, tightness);
                    edge = smoothstep(0.5 - hw1, 0.5 + hw1, edge);

                    // Pass 2: Wider window (0.15 half-width at t=1.0)
                    // V5: smoothstep(0.35, 0.65) = 0.5 ± 0.15
                    if (passes >= 2)
                    {
                        float hw2 = lerp(0.5, 0.15, tightness);
                        edge = smoothstep(0.5 - hw2, 0.5 + hw2, edge);
                    }

                    // Pass 3: Even wider (0.25 half-width at t=1.0)
                    // V5: smoothstep(0.25, 0.75) = 0.5 ± 0.25
                    if (passes >= 3)
                    {
                        float hw3 = lerp(0.5, 0.25, tightness);
                        edge = smoothstep(0.5 - hw3, 0.5 + hw3, edge);
                    }

                    // Pass 4: Widest window (0.35 half-width at t=1.0)
                    // V5: smoothstep(0.15, 0.85) = 0.5 ± 0.35
                    if (passes >= 4)
                    {
                        float hw4 = lerp(0.5, 0.35, tightness);
                        edge = smoothstep(0.5 - hw4, 0.5 + hw4, edge);
                    }

                    // Configurable power curve for noise suppression
                    edge = pow(edge, powerCurve);

                    edgeStrength = edge * _InnerLineStrength;
                }

                // Lighting calculation
                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);
                Light mainLight = GetMainLight();

                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = floor(smoothstep(toonThreshold - toonSmoothness, toonThreshold + toonSmoothness, NdotL) * toonSteps) / toonSteps;
                toon = lerp(1.0, toon, shadowStrength);

                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float rim = pow(1.0 - saturate(dot(vWS, nWS)), rimPower);
                float3 shaded = albedo.rgb * lighting + rim * _RimColor.rgb;

                // Apply edges
                shaded = lerp(shaded, innerLineColor.rgb, edgeStrength);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
