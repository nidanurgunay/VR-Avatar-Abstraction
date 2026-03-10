// Version 10: Ultimate Combined Toon Shader - MODULAR EDITION
// Combines: Toon Shading + Configurable Gaussian Pre-Blur Sobel + Normal Edge Detection
// Each processing step can be toggled independently for analysis

Shader "Custom/V4_GaussianPreFilteredSobel"
{
    Properties
    {
        [Header(DEBUG AND VISUALIZATION)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults", Float) = 0
        [KeywordEnum(Final, RawSobel, AfterThreshold, AfterBlur, NormalEdge, FresnelEdge)] _DebugView ("Debug View", Float) = 0
        [Space(10)]

        [Header(Base)]
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        [Header(Toon Shading)]
        [Toggle] _EnableToonShading ("Enable Toon Shading", Float) = 1
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        [Header(Outer Outline)]
        [Toggle] _EnableOuterOutline ("Enable Outer Outline", Float) = 1
        _OuterOutlineWidth ("Outer Outline Width", Range(0, 0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        [Header(Edge Detection Modes)]
        [Toggle] _EnableTextureSobel ("Enable Texture Sobel", Float) = 1
        [Toggle] _EnableNormalEdges ("Enable Normal Edges", Float) = 0
        [Toggle] _EnableFresnelEdge ("Enable Fresnel Silhouette", Float) = 0

        [Header(Filtering Presets)]
        [Toggle] _UseLightFiltering ("Light Filtering (V3 style)", Float) = 0
        [Toggle] _UseModerateFiltering ("Moderate Filtering (V4 style)", Float) = 0
        [Toggle] _UseAggressiveFiltering ("Aggressive Filtering (V5 style)", Float) = 0
        [Space(10)]

        [Header(Texture Sobel Settings)]
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

        [Header(Gaussian PreBlur)]
        [Toggle] _EnableGaussianBlur ("Enable Gaussian PreBlur", Float) = 1
        _BlurRadiusMultiplier ("Blur Radius Multiplier", Range(0.1, 10.0)) = 0.8
        _GaussianCenterWeight ("Center Weight", Range(0.0, 1.0)) = 0.25
        _GaussianCardinalWeight ("Cardinal Weight", Range(0.0, 0.5)) = 0.125
        _GaussianDiagonalWeight ("Diagonal Weight", Range(0.0, 0.25)) = 0.0625

        [Header(Edge Threshold)]
        [Toggle] _EnableThreshold ("Enable Threshold", Float) = 1
        _ThresholdMinMultiplier ("Threshold Min Multiplier", Range(0.0, 1.0)) = 0.2
        _ThresholdMaxMultiplier ("Threshold Max Multiplier", Range(1.0, 5.0)) = 2.0

        [Header(Smoothstep Passes  Individual Control)]
        [Toggle] _EnablePass1 ("Enable Pass 1 (Tightest)", Float) = 1
        [Toggle] _EnablePass2 ("Enable Pass 2", Float) = 1
        [Toggle] _EnablePass3 ("Enable Pass 3", Float) = 1
        [Toggle] _EnablePass4 ("Enable Pass 4 (Widest)", Float) = 1
        _SmoothstepTightness ("Smoothstep Tightness", Range(0.0, 1.0)) = 0.2

        [Header(Power Curve)]
        [Toggle] _EnablePowerCurve ("Enable Power Curve", Float) = 1
        _PowerCurve ("Power Curve", Range(0.5, 5.0)) = 1.5

        [Header(Normal Edge Settings)]
        _NormalEdgeThreshold ("Normal Edge Threshold", Range(0.0, 1.0)) = 0.5
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 0.5
        _NormalEdgeSmoothness ("Normal Edge Smoothness", Range(0.01, 0.5)) = 0.1

        [Header(Fresnel Silhouette Settings)]
        _FresnelEdgeThreshold ("Fresnel Threshold", Range(0.0, 1.0)) = 0.3
        _FresnelEdgeStrength ("Fresnel Strength", Range(0, 1)) = 0.3

        [Header(Edge Combination)]
        _EdgeColor ("Combined Edge Color", Color) = (0,0,0,1)
        [KeywordEnum(Max, Add, Multiply)] _EdgeBlendMode ("Edge Blend Mode", Float) = 0

        [Header(Rim and Ambient)]
        [Toggle] _EnableRim ("Enable Rim Lighting", Float) = 1
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

        [Header(Alpha Test)]
        [Toggle] _EnableAlphaTest ("Enable Alpha Test", Float) = 0
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

        // MAIN TOON PASS WITH ALL EDGE DETECTION METHODS
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature_local _EDGEBLENDMODE_MAX _EDGEBLENDMODE_ADD _EDGEBLENDMODE_MULTIPLY

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float3 nWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _InnerLineColor, _OuterOutlineColor, _EdgeColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower, _InnerLineThreshold, _InnerLineBlur, _InnerLineStrength;
            float _UseDebugDefaults, _EnableAlphaTest, _AlphaCutoff;

            // Debug view mode (0=Final, 1=RawSobel, 2=AfterThreshold, 3-6=AfterPass1-4, 7=AfterPower, 8=NormalEdge, 9=FresnelEdge, 10=Combined)
            float _DebugView;

            // Master toggles
            float _EnableToonShading, _EnableRim;

            // Edge detection toggles
            float _EnableTextureSobel, _EnableNormalEdges, _EnableFresnelEdge;

            // Filtering preset toggles
            float _UseLightFiltering, _UseModerateFiltering, _UseAggressiveFiltering;

            // Modular processing toggles
            float _EnableGaussianBlur, _EnableThreshold;
            float _EnablePass1, _EnablePass2, _EnablePass3, _EnablePass4;
            float _EnablePowerCurve;

            // Gaussian blur parameters
            float _BlurRadiusMultiplier, _GaussianCenterWeight, _GaussianCardinalWeight, _GaussianDiagonalWeight;
            float _ThresholdMinMultiplier, _ThresholdMaxMultiplier;
            float _SmoothstepTightness, _PowerCurve;

            // Normal edge parameters
            float _NormalEdgeThreshold, _NormalEdgeStrength, _NormalEdgeSmoothness;

            // Fresnel edge parameters
            float _FresnelEdgeThreshold, _FresnelEdgeStrength;

            // Helper: Sample with configurable 9-tap Gaussian blur
            float SampleLuminanceBlurred(float2 uv, float blurRadius, float centerW, float cardinalW, float diagonalW)
            {
                float lum = 0.0;
                float3 lumCoeff = float3(0.299, 0.587, 0.114);

                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, lumCoeff) * centerW;

                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, 0)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, 0)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, blurRadius)).rgb, lumCoeff) * cardinalW;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, -blurRadius)).rgb, lumCoeff) * cardinalW;

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
                o.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                return o;
            }

            half4 frag(v2f IN) : SV_Target
            {
                // Local copies for debug override
                float textureIntensity = _TextureIntensity;
                float toonSteps = _ToonSteps;
                float toonThreshold = _ToonThreshold;
                float toonSmoothness = _ToonSmoothness;
                float shadowStrength = _ShadowStrength;
                float rimPower = _RimPower;

                if (_UseDebugDefaults > 0.5)
                {
                    textureIntensity = 1.0;
                    toonSteps = 5.0;
                    toonThreshold = 1.0;
                    toonSmoothness = 0.03;
                    shadowStrength = 0.6;
                    rimPower = 5.0;
                }

                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, textureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);

                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(IN.viewDirWS);

                // Debug view mode
                int debugMode = (int)_DebugView;

                // ==================== TEXTURE SOBEL EDGE DETECTION (MODULAR) ====================
                float sobelEdge = 0.0;
                float debugRawSobel = 0.0;
                float debugAfterThreshold = 0.0;
                float debugAfterPass1 = 0.0;
                float debugAfterPass2 = 0.0;
                float debugAfterPass3 = 0.0;
                float debugAfterPass4 = 0.0;
                float debugAfterPower = 0.0;

                if (_EnableTextureSobel > 0.5)
                {
                    // Get blur parameters (use presets if enabled)
                    float blurRadiusMult = _BlurRadiusMultiplier;
                    float gaussCenterW = _GaussianCenterWeight;
                    float gaussCardinalW = _GaussianCardinalWeight;
                    float gaussDiagonalW = _GaussianDiagonalWeight;
                    float threshMinMult = _ThresholdMinMultiplier;
                    float threshMaxMult = _ThresholdMaxMultiplier;
                    float smoothTightness = _SmoothstepTightness;
                    float powerCurve = _PowerCurve;

                    // Light Filtering Preset (V3 style)
                    if (_UseLightFiltering > 0.5)
                    {
                        blurRadiusMult = 0.8; gaussCenterW = 0.25; gaussCardinalW = 0.125; gaussDiagonalW = 0.0625;
                        threshMinMult = 0.2; threshMaxMult = 2.0; smoothTightness = 0.2; powerCurve = 1.5;
                    }

                    // Moderate Filtering Preset (V4 style)
                    if (_UseModerateFiltering > 0.5)
                    {
                        blurRadiusMult = 1.0; gaussCenterW = 0.3; gaussCardinalW = 0.12; gaussDiagonalW = 0.05;
                        threshMinMult = 0.4; threshMaxMult = 1.6; smoothTightness = 0.3; powerCurve = 2.0;
                    }

                    // Aggressive Filtering Preset (V5 style)
                    if (_UseAggressiveFiltering > 0.5)
                    {
                        blurRadiusMult = 1.2; gaussCenterW = 0.25; gaussCardinalW = 0.125; gaussDiagonalW = 0.0625;
                        threshMinMult = 0.85; threshMaxMult = 1.15; smoothTightness = 1.0; powerCurve = 3.0;
                    }

                    float offset = _InnerLineBlur * 0.001;
                    float blurOffset = (_EnableGaussianBlur > 0.5) ? offset * blurRadiusMult : 0.0;

                    // Normalize weights
                    float totalWeight = gaussCenterW + 4.0 * gaussCardinalW + 4.0 * gaussDiagonalW;
                    float centerW = gaussCenterW / totalWeight;
                    float cardinalW = gaussCardinalW / totalWeight;
                    float diagonalW = gaussDiagonalW / totalWeight;

                    // If blur disabled, use simple sampling (center only)
                    if (_EnableGaussianBlur < 0.5)
                    {
                        centerW = 1.0; cardinalW = 0.0; diagonalW = 0.0;
                    }

                    // Sample 9 positions
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
                    debugRawSobel = edgeMagnitude;

                    // Threshold window (optional)
                    float edge = edgeMagnitude;
                    if (_EnableThreshold > 0.5)
                    {
                        float minEdge = _InnerLineThreshold * threshMinMult;
                        float maxEdge = _InnerLineThreshold * threshMaxMult;
                        edge = smoothstep(minEdge, maxEdge, edgeMagnitude);
                    }
                    debugAfterThreshold = edge;

                    // Progressive smoothstep passes (each individually toggleable)
                    float tightness = smoothTightness;

                    // Pass 1
                    if (_EnablePass1 > 0.5)
                    {
                        float hw1 = lerp(0.5, 0.03, tightness);
                        edge = smoothstep(0.5 - hw1, 0.5 + hw1, edge);
                    }
                    debugAfterPass1 = edge;

                    // Pass 2
                    if (_EnablePass2 > 0.5)
                    {
                        float hw2 = lerp(0.5, 0.15, tightness);
                        edge = smoothstep(0.5 - hw2, 0.5 + hw2, edge);
                    }
                    debugAfterPass2 = edge;

                    // Pass 3
                    if (_EnablePass3 > 0.5)
                    {
                        float hw3 = lerp(0.5, 0.25, tightness);
                        edge = smoothstep(0.5 - hw3, 0.5 + hw3, edge);
                    }
                    debugAfterPass3 = edge;

                    // Pass 4
                    if (_EnablePass4 > 0.5)
                    {
                        float hw4 = lerp(0.5, 0.35, tightness);
                        edge = smoothstep(0.5 - hw4, 0.5 + hw4, edge);
                    }
                    debugAfterPass4 = edge;

                    // Power curve (optional)
                    if (_EnablePowerCurve > 0.5)
                    {
                        edge = pow(edge, powerCurve);
                    }
                    debugAfterPower = edge;

                    sobelEdge = edge * _InnerLineStrength;
                }

                // ==================== NORMAL EDGE DETECTION ====================
                float normalEdge = 0.0;
                if (_EnableNormalEdges > 0.5)
                {
                    float3 dNdx = ddx(nWS);
                    float3 dNdy = ddy(nWS);
                    float normalVariation = length(dNdx) + length(dNdy);

                    float normalEdgeRaw = smoothstep(
                        _NormalEdgeThreshold - _NormalEdgeSmoothness,
                        _NormalEdgeThreshold + _NormalEdgeSmoothness,
                        normalVariation
                    );

                    normalEdge = normalEdgeRaw * _NormalEdgeStrength;
                }

                // ==================== FRESNEL SILHOUETTE EDGE ====================
                float fresnelEdge = 0.0;
                if (_EnableFresnelEdge > 0.5)
                {
                    float NdotV = saturate(dot(nWS, vWS));
                    float fresnel = 1.0 - NdotV;
                    float fresnelEdgeRaw = smoothstep(_FresnelEdgeThreshold, 1.0, fresnel);
                    fresnelEdge = fresnelEdgeRaw * _FresnelEdgeStrength;
                }

                // ==================== DEBUG VIEW OUTPUT ====================
                // 0=Final, 1=RawSobel, 2=AfterThreshold, 3=AfterBlur, 4=NormalEdge, 5=FresnelEdge
                // if (debugMode == 0) return half4(shaded, albedo.a); // Final - removed to avoid using undeclared shaded
                if (debugMode == 1) return half4(debugRawSobel.xxx, 1.0); // RawSobel
                if (debugMode == 2) return half4(debugAfterThreshold.xxx, 1.0); // AfterThreshold
                if (debugMode == 3) return half4(debugAfterPass1.xxx, 1.0); // AfterBlur
                if (debugMode == 4) return half4(normalEdge.xxx, 1.0); // NormalEdge
                if (debugMode == 5) return half4(fresnelEdge.xxx, 1.0); // FresnelEdge
                // Other debug modes commented out

                // ==================== COMBINE EDGES ====================
                float combinedEdge = 0.0;

                #if defined(_EDGEBLENDMODE_ADD)
                    combinedEdge = saturate(sobelEdge + normalEdge + fresnelEdge);
                #elif defined(_EDGEBLENDMODE_MULTIPLY)
                    float hasEdges = step(0.001, sobelEdge + normalEdge + fresnelEdge);
                    combinedEdge = hasEdges * saturate(max(sobelEdge, 0.001) * max(normalEdge + 1.0, 1.0) * max(fresnelEdge + 1.0, 1.0) - 1.0);
                #else // MAX (default)
                    combinedEdge = max(max(sobelEdge, normalEdge), fresnelEdge);
                #endif

                // if (debugMode == 10) return half4(combinedEdge.xxx, 1.0); // Commented out

                // ==================== TOON LIGHTING ====================
                Light mainLight = GetMainLight();

                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = 1.0;
                if (_EnableToonShading > 0.5)
                {
                    toon = floor(smoothstep(toonThreshold - toonSmoothness, toonThreshold + toonSmoothness, NdotL) * toonSteps) / toonSteps;
                    toon = lerp(1.0, toon, shadowStrength);
                }

                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float3 shaded = albedo.rgb * lighting;

                // Rim lighting (optional)
                if (_EnableRim > 0.5)
                {
                    float rim = pow(1.0 - saturate(dot(vWS, nWS)), rimPower);
                    shaded += rim * _RimColor.rgb;
                }

                // Apply combined edges
                float3 edgeColor = _EdgeColor.rgb;
                if (_EnableTextureSobel > 0.5 && _EnableNormalEdges < 0.5 && _EnableFresnelEdge < 0.5)
                {
                    edgeColor = _InnerLineColor.rgb; // Use inner line color if only Sobel is enabled
                }
                shaded = lerp(shaded, edgeColor, float3(combinedEdge, combinedEdge, combinedEdge));

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonV10MaterialEditor"
}
