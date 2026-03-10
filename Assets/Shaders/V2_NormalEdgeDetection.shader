// Version 7: Combined Edge Detection Shader
// All-in-one shader with configurable edge detection methods
// Combines: Texture Sobel, Normal Edges, and Fresnel Silhouette
// Supports multiple filtering modes for Sobel
// Outer outline (geometry expansion) is now OPTIONAL - can be disabled to see only normal/inner edges

Shader "Custom/V2_NormalEdgeDetection"
{
    Properties
    {
        [Header(Debug Mode)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults (overrides all settings below)", Float) = 0
        [Space(10)]

        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        [Header(Toon Shading)]
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        [Header(Outer Outline Geometry Expansion)]
        [Toggle] _EnableOuterOutline ("Enable Outer Outline (Geometry)", Float) = 1
        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset (fix z-fighting)", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        [Header(Texture Edge Detection (Sobel) )]
        [Toggle] _EnableTextureSobel ("Enable Texture Sobel", Float) = 1
        [KeywordEnum(None, Light, Moderate, Aggressive)] _SobelFilterMode ("Sobel Filter Mode", Float) = 2
        _SobelLineColor ("Sobel Line Color", Color) = (0,0,0,1)
        _SobelThreshold ("Sobel Threshold", Range(0.001, 0.5)) = 0.2
        _SobelSampleDistance ("Sobel Sample Distance", Range(0.0, 10.0)) = 0.5
        _SobelStrength ("Sobel Strength", Range(0, 1)) = 1.0

        [Header(Normal Edge Detection)]
        [Toggle] _EnableNormalEdges ("Enable Normal Edges", Float) = 0
        _NormalEdgeThreshold ("Normal Edge Threshold", Range(0.0, 1.0)) = 0.5
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 0.5
        _NormalEdgeSmoothness ("Normal Edge Smoothness", Range(0.01, 0.5)) = 0.1

        [Header(Fresnel Silhouette Edge)]
        [Toggle] _EnableFresnelEdge ("Enable Fresnel Silhouette", Float) = 0
        _FresnelEdgeThreshold ("Fresnel Threshold", Range(0.0, 1.0)) = 0.3
        _FresnelEdgeStrength ("Fresnel Strength", Range(0, 1)) = 0.3

        [Header(Combined Edge Settings)]
        _EdgeColor ("Combined Edge Color", Color) = (0,0,0,1)

        [Header(Rim Lighting)]
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.35,0.35,0.35,1)

        [Header(Transparency)]
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
            float _EnableOuterOutline;
            float _OuterOutlineWidth;
            float4 _OuterOutlineColor;
            float _EnableAlphaTest;
            float _AlphaCutoff;
            float _OutlineDepthBias;

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;

                // If outline is disabled, collapse geometry to a degenerate triangle
                if (_EnableOuterOutline < 0.5)
                {
                    o.pos = float4(0, 0, 0, 1);
                    o.uv = float2(0, 0);
                    return o;
                }

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
                // Discard if outline is disabled
                if (_EnableOuterOutline < 0.5)
                {
                    clip(-1);
                }

                if (_EnableAlphaTest > 0.5)
                {
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a;
                    clip(alpha - _AlphaCutoff);
                }
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // MAIN TOON PASS WITH COMBINED EDGE DETECTION
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature_local _SOBELFILTERMODE_NONE _SOBELFILTERMODE_LIGHT _SOBELFILTERMODE_MODERATE _SOBELFILTERMODE_AGGRESSIVE

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
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _EdgeColor, _SobelLineColor, _OuterOutlineColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower, _EnableOuterOutline;
            float _EnableTextureSobel, _SobelFilterMode, _SobelThreshold, _SobelSampleDistance, _SobelStrength;
            float _EnableNormalEdges, _NormalEdgeThreshold, _NormalEdgeStrength, _NormalEdgeSmoothness;
            float _EnableFresnelEdge, _FresnelEdgeThreshold, _FresnelEdgeStrength;
            float _UseDebugDefaults, _EnableAlphaTest, _AlphaCutoff;

            // 9-tap Gaussian blur sampling
            float SampleLuminanceBlurred(float2 uv, float blurRadius)
            {
                float lum = 0.0;
                float3 lumCoeff = float3(0.299, 0.587, 0.114);

                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, lumCoeff) * 0.25;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, 0)).rgb, lumCoeff) * 0.125;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, 0)).rgb, lumCoeff) * 0.125;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, blurRadius)).rgb, lumCoeff) * 0.125;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(0, -blurRadius)).rgb, lumCoeff) * 0.125;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, blurRadius)).rgb, lumCoeff) * 0.0625;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, blurRadius)).rgb, lumCoeff) * 0.0625;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(blurRadius, -blurRadius)).rgb, lumCoeff) * 0.0625;
                lum += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv + float2(-blurRadius, -blurRadius)).rgb, lumCoeff) * 0.0625;

                return lum;
            }

            // Simple luminance sampling (no blur)
            float SampleLuminance(float2 uv)
            {
                return dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb, float3(0.299, 0.587, 0.114));
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
                if (_UseDebugDefaults > 0.5)
                {
                    _TextureIntensity = 1.0;
                    _ToonSteps = 5.0;
                    _ToonThreshold = 1.0;
                    _ToonSmoothness = 0.03;
                    _ShadowStrength = 0.6;
                    _RimPower = 5.0;
                    _OuterOutlineColor = float4(0, 0, 0, 1);
                    _EdgeColor = float4(0, 0, 0, 1);
                }

                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }

                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);

                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(IN.viewDirWS);

                float totalEdgeStrength = 0.0;

                // ==================== TEXTURE SOBEL EDGE DETECTION ====================
                if (_EnableTextureSobel > 0.5)
                {
                    float offset = _SobelSampleDistance * 0.001;
                    float edge = 0.0;

                    // Determine blur amount and filtering based on mode
                    float blurMultiplier = 0.0;
                    float minThreshMult = 0.0;
                    float maxThreshMult = 1.0;
                    float powerCurve = 1.0;
                    int smoothstepPasses = 0;

                    // Mode 0: None (binary step)
                    // Mode 1: Light (0.5x blur, wide window, pow 1.2)
                    // Mode 2: Moderate (0.8x blur, medium window, pow 1.5)
                    // Mode 3: Aggressive (1.2x blur, narrow window, pow 3.0)

                    #if defined(_SOBELFILTERMODE_NONE)
                        blurMultiplier = 0.0;
                    #elif defined(_SOBELFILTERMODE_LIGHT)
                        blurMultiplier = 0.5;
                        minThreshMult = 0.3;
                        maxThreshMult = 2.5;
                        powerCurve = 1.2;
                        smoothstepPasses = 1;
                    #elif defined(_SOBELFILTERMODE_MODERATE)
                        blurMultiplier = 0.8;
                        minThreshMult = 0.2;
                        maxThreshMult = 2.0;
                        powerCurve = 1.5;
                        smoothstepPasses = 2;
                    #elif defined(_SOBELFILTERMODE_AGGRESSIVE)
                        blurMultiplier = 1.2;
                        minThreshMult = 0.85;
                        maxThreshMult = 1.15;
                        powerCurve = 3.0;
                        smoothstepPasses = 4;
                    #else
                        // Default to moderate
                        blurMultiplier = 0.8;
                        minThreshMult = 0.2;
                        maxThreshMult = 2.0;
                        powerCurve = 1.5;
                        smoothstepPasses = 2;
                    #endif

                    float blurOffset = offset * blurMultiplier;

                    // Sample 9 Sobel positions
                    float tl, t, tr, l, r, bl, b, br;

                    if (blurMultiplier > 0.0)
                    {
                        // With blur
                        tl = SampleLuminanceBlurred(IN.uv + float2(-offset, offset), blurOffset);
                        t  = SampleLuminanceBlurred(IN.uv + float2(0, offset), blurOffset);
                        tr = SampleLuminanceBlurred(IN.uv + float2(offset, offset), blurOffset);
                        l  = SampleLuminanceBlurred(IN.uv + float2(-offset, 0), blurOffset);
                        r  = SampleLuminanceBlurred(IN.uv + float2(offset, 0), blurOffset);
                        bl = SampleLuminanceBlurred(IN.uv + float2(-offset, -offset), blurOffset);
                        b  = SampleLuminanceBlurred(IN.uv + float2(0, -offset), blurOffset);
                        br = SampleLuminanceBlurred(IN.uv + float2(offset, -offset), blurOffset);
                    }
                    else
                    {
                        // No blur (simple Sobel)
                        tl = SampleLuminance(IN.uv + float2(-offset, offset));
                        t  = SampleLuminance(IN.uv + float2(0, offset));
                        tr = SampleLuminance(IN.uv + float2(offset, offset));
                        l  = SampleLuminance(IN.uv + float2(-offset, 0));
                        r  = SampleLuminance(IN.uv + float2(offset, 0));
                        bl = SampleLuminance(IN.uv + float2(-offset, -offset));
                        b  = SampleLuminance(IN.uv + float2(0, -offset));
                        br = SampleLuminance(IN.uv + float2(offset, -offset));
                    }

                    // Sobel operator
                    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
                    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);

                    #if defined(_SOBELFILTERMODE_NONE)
                        // Binary step for no filtering
                        edge = step(_SobelThreshold, edgeMagnitude);
                    #else
                        // Smoothstep-based filtering
                        float minEdge = _SobelThreshold * minThreshMult;
                        float maxEdge = _SobelThreshold * maxThreshMult;
                        edge = smoothstep(minEdge, maxEdge, edgeMagnitude);

                        // Apply smoothstep passes based on mode
                        #if defined(_SOBELFILTERMODE_LIGHT)
                            // 1 pass already done above
                        #elif defined(_SOBELFILTERMODE_MODERATE)
                            edge = smoothstep(0.3, 0.7, edge);
                            edge = smoothstep(0.2, 0.8, edge);
                        #elif defined(_SOBELFILTERMODE_AGGRESSIVE)
                            edge = smoothstep(0.47, 0.53, edge);
                            edge = smoothstep(0.35, 0.65, edge);
                            edge = smoothstep(0.25, 0.75, edge);
                            edge = smoothstep(0.15, 0.85, edge);
                        #endif

                        edge = pow(edge, powerCurve);
                    #endif

                    totalEdgeStrength += edge * _SobelStrength;
                }

                // ==================== NORMAL EDGE DETECTION ====================
                if (_EnableNormalEdges > 0.5)
                {
                    float3 dNdx = ddx(nWS);
                    float3 dNdy = ddy(nWS);
                    float normalEdge = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));

                    float minThresh = _NormalEdgeThreshold - _NormalEdgeSmoothness;
                    float maxThresh = _NormalEdgeThreshold + _NormalEdgeSmoothness;
                    normalEdge = smoothstep(minThresh, maxThresh, normalEdge);

                    totalEdgeStrength += normalEdge * _NormalEdgeStrength;
                }

                // ==================== FRESNEL SILHOUETTE EDGE ====================
                if (_EnableFresnelEdge > 0.5)
                {
                    float NdotV = saturate(dot(nWS, vWS));
                    float fresnelEdge = 1.0 - NdotV;

                    fresnelEdge = smoothstep(_FresnelEdgeThreshold - 0.1, _FresnelEdgeThreshold, fresnelEdge);
                    fresnelEdge *= smoothstep(_FresnelEdgeThreshold + 0.3, _FresnelEdgeThreshold, fresnelEdge);

                    totalEdgeStrength += fresnelEdge * _FresnelEdgeStrength;
                }

                totalEdgeStrength = saturate(totalEdgeStrength);

                // ==================== LIGHTING ====================
                Light mainLight = GetMainLight();

                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = floor(smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL) * _ToonSteps) / _ToonSteps;
                toon = lerp(1.0, toon, _ShadowStrength);

                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                float3 shaded = albedo.rgb * lighting + rim * _RimColor.rgb;

                // Apply combined edges
                shaded = lerp(shaded, _EdgeColor.rgb, totalEdgeStrength);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
