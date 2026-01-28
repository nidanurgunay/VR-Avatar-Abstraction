// Version 6: Normal-Based Edge Detection
// Detects edges from geometry normal discontinuities (not texture)
// Great for detecting silhouette edges between different mesh parts
// Works independently of texture detail

Shader "Custom/ToonShader_V6_NormalEdges"
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

        [Header(Normal Edge Detection)]
        [Toggle] _EnableNormalEdges ("Enable Normal Edges", Float) = 1
        _NormalEdgeColor ("Normal Edge Color", Color) = (0,0,0,1)
        _NormalEdgeThreshold ("Normal Edge Threshold", Range(0.0, 1.0)) = 0.5
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 1.0
        _NormalEdgeSmoothness ("Normal Edge Smoothness", Range(0.01, 0.5)) = 0.1

        [Header(Fresnel Silhouette)]
        [Toggle] _EnableFresnelEdge ("Enable Fresnel Silhouette Edge", Float) = 1
        _FresnelEdgeThreshold ("Fresnel Edge Threshold", Range(0.0, 1.0)) = 0.3
        _FresnelEdgeStrength ("Fresnel Edge Strength", Range(0, 1)) = 0.5

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

        // MAIN TOON PASS WITH NORMAL-BASED EDGE DETECTION
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
                float4 screenPos : TEXCOORD4;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _NormalEdgeColor, _OuterOutlineColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower, _EnableNormalEdges, _NormalEdgeThreshold, _NormalEdgeStrength, _NormalEdgeSmoothness;
            float _EnableFresnelEdge, _FresnelEdgeThreshold, _FresnelEdgeStrength;
            float _UseDebugDefaults, _EnableAlphaTest, _AlphaCutoff;

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
                o.screenPos = ComputeScreenPos(o.pos);
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
                    _NormalEdgeColor = float4(0, 0, 0, 1);
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

                // NORMAL-BASED EDGE DETECTION
                // Uses the derivative of the normal to detect sharp edges in geometry
                float edgeStrength = 0.0;

                if (_EnableNormalEdges > 0.5)
                {
                    // Calculate screen-space derivatives of the world normal
                    float3 dNdx = ddx(nWS);
                    float3 dNdy = ddy(nWS);

                    // Edge magnitude from normal discontinuity
                    float normalEdge = sqrt(dot(dNdx, dNdx) + dot(dNdy, dNdy));

                    // Smooth threshold
                    float minThresh = _NormalEdgeThreshold - _NormalEdgeSmoothness;
                    float maxThresh = _NormalEdgeThreshold + _NormalEdgeSmoothness;
                    normalEdge = smoothstep(minThresh, maxThresh, normalEdge);

                    edgeStrength += normalEdge * _NormalEdgeStrength;
                }

                // FRESNEL-BASED SILHOUETTE EDGE
                // Detects edges where the surface faces perpendicular to view
                if (_EnableFresnelEdge > 0.5)
                {
                    float NdotV = saturate(dot(nWS, vWS));
                    float fresnelEdge = 1.0 - NdotV;

                    // Only count as edge near the threshold
                    fresnelEdge = smoothstep(_FresnelEdgeThreshold - 0.1, _FresnelEdgeThreshold, fresnelEdge);
                    fresnelEdge *= smoothstep(_FresnelEdgeThreshold + 0.3, _FresnelEdgeThreshold, fresnelEdge);

                    edgeStrength += fresnelEdge * _FresnelEdgeStrength;
                }

                edgeStrength = saturate(edgeStrength);

                // Lighting calculation
                Light mainLight = GetMainLight();

                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = floor(smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL) * _ToonSteps) / _ToonSteps;
                toon = lerp(1.0, toon, _ShadowStrength);

                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                float3 shaded = albedo.rgb * lighting + rim * _RimColor.rgb;

                // Apply edges
                shaded = lerp(shaded, _NormalEdgeColor.rgb, edgeStrength);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
