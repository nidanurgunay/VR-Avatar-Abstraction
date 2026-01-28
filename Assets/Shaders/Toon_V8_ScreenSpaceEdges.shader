// Version 8: Screen-Space Depth/Normal Edge Detection
// Detects edges from depth buffer discontinuities and normal buffer discontinuities
// Three-layer edge detection system:
// 1. Depth edges - detect silhouettes and depth discontinuities
// 2. Normal edges - detect surface angle changes
// 3. Combined with texture edges for complete avatar abstraction
// Requires: Depth texture enabled in URP settings

Shader "Custom/ToonShader_V8_ScreenSpaceEdges"
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

        [Header(Outer Outline)]
        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset (fix z-fighting)", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        [Header(Screen Space Depth Edges)]
        [Toggle] _EnableDepthEdges ("Enable Depth Edges", Float) = 1
        _DepthEdgeThreshold ("Depth Edge Threshold", Range(0.0001, 0.1)) = 0.01
        _DepthEdgeStrength ("Depth Edge Strength", Range(0, 1)) = 1.0
        _DepthEdgeSampleDistance ("Depth Sample Distance", Range(0.1, 5.0)) = 1.0

        [Header(Screen Space Normal Edges)]
        [Toggle] _EnableScreenNormalEdges ("Enable Screen Normal Edges", Float) = 1
        _ScreenNormalEdgeThreshold ("Normal Edge Threshold", Range(0.0, 1.0)) = 0.3
        _ScreenNormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 1.0
        _ScreenNormalSampleDistance ("Normal Sample Distance", Range(0.1, 5.0)) = 1.0

        [Header(Combined Edge Settings)]
        _EdgeColor ("Edge Color", Color) = (0,0,0,1)
        _EdgeSmoothness ("Edge Smoothness", Range(0.01, 0.5)) = 0.1

        [Header(Rim Lighting)]
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

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

        // MAIN TOON PASS WITH SCREEN-SPACE EDGE DETECTION
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

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
                float4 screenPos : TEXCOORD3;
                float3 viewDirWS : TEXCOORD4;
            };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _EdgeColor, _OuterOutlineColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower;
            float _EnableDepthEdges, _DepthEdgeThreshold, _DepthEdgeStrength, _DepthEdgeSampleDistance;
            float _EnableScreenNormalEdges, _ScreenNormalEdgeThreshold, _ScreenNormalEdgeStrength, _ScreenNormalSampleDistance;
            float _EdgeSmoothness;
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
                o.screenPos = ComputeScreenPos(o.pos);
                o.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                return o;
            }

            // Roberts Cross edge detection for depth
            float RobertsCrossDepth(float2 screenUV, float2 texelSize, float sampleDist)
            {
                float2 offset = texelSize * sampleDist;

                // Sample depth at 4 corners (Roberts Cross pattern)
                float d00 = SampleSceneDepth(screenUV);
                float d11 = SampleSceneDepth(screenUV + offset);
                float d01 = SampleSceneDepth(screenUV + float2(0, offset.y));
                float d10 = SampleSceneDepth(screenUV + float2(offset.x, 0));

                // Convert to linear depth for more accurate comparison
                float l00 = Linear01Depth(d00, _ZBufferParams);
                float l11 = Linear01Depth(d11, _ZBufferParams);
                float l01 = Linear01Depth(d01, _ZBufferParams);
                float l10 = Linear01Depth(d10, _ZBufferParams);

                // Roberts Cross operator
                float edge1 = l00 - l11;
                float edge2 = l01 - l10;

                return sqrt(edge1 * edge1 + edge2 * edge2);
            }

            // Sobel edge detection for depth (more accurate)
            float SobelDepth(float2 screenUV, float2 texelSize, float sampleDist)
            {
                float2 offset = texelSize * sampleDist;

                // Sample 3x3 neighborhood
                float tl = Linear01Depth(SampleSceneDepth(screenUV + float2(-offset.x, offset.y)), _ZBufferParams);
                float t  = Linear01Depth(SampleSceneDepth(screenUV + float2(0, offset.y)), _ZBufferParams);
                float tr = Linear01Depth(SampleSceneDepth(screenUV + float2(offset.x, offset.y)), _ZBufferParams);
                float l  = Linear01Depth(SampleSceneDepth(screenUV + float2(-offset.x, 0)), _ZBufferParams);
                float r  = Linear01Depth(SampleSceneDepth(screenUV + float2(offset.x, 0)), _ZBufferParams);
                float bl = Linear01Depth(SampleSceneDepth(screenUV + float2(-offset.x, -offset.y)), _ZBufferParams);
                float b  = Linear01Depth(SampleSceneDepth(screenUV + float2(0, -offset.y)), _ZBufferParams);
                float br = Linear01Depth(SampleSceneDepth(screenUV + float2(offset.x, -offset.y)), _ZBufferParams);

                // Sobel operator
                float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);

                return sqrt(sobelX * sobelX + sobelY * sobelY);
            }

            // Sobel edge detection for normals
            float SobelNormal(float2 screenUV, float2 texelSize, float sampleDist)
            {
                float2 offset = texelSize * sampleDist;

                // Sample 3x3 neighborhood of normals
                float3 tl = SampleSceneNormals(screenUV + float2(-offset.x, offset.y));
                float3 t  = SampleSceneNormals(screenUV + float2(0, offset.y));
                float3 tr = SampleSceneNormals(screenUV + float2(offset.x, offset.y));
                float3 l  = SampleSceneNormals(screenUV + float2(-offset.x, 0));
                float3 c  = SampleSceneNormals(screenUV);
                float3 r  = SampleSceneNormals(screenUV + float2(offset.x, 0));
                float3 bl = SampleSceneNormals(screenUV + float2(-offset.x, -offset.y));
                float3 b  = SampleSceneNormals(screenUV + float2(0, -offset.y));
                float3 br = SampleSceneNormals(screenUV + float2(offset.x, -offset.y));

                // Calculate normal differences using dot product (1 - dot = angle difference)
                float diffTL = 1.0 - saturate(dot(c, tl));
                float diffT  = 1.0 - saturate(dot(c, t));
                float diffTR = 1.0 - saturate(dot(c, tr));
                float diffL  = 1.0 - saturate(dot(c, l));
                float diffR  = 1.0 - saturate(dot(c, r));
                float diffBL = 1.0 - saturate(dot(c, bl));
                float diffB  = 1.0 - saturate(dot(c, b));
                float diffBR = 1.0 - saturate(dot(c, br));

                // Sobel operator on normal differences
                float sobelX = (diffTR + 2.0 * diffR + diffBR) - (diffTL + 2.0 * diffL + diffBL);
                float sobelY = (diffTL + 2.0 * diffT + diffTR) - (diffBL + 2.0 * diffB + diffBR);

                return sqrt(sobelX * sobelX + sobelY * sobelY);
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

                // Get screen UV
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                float2 texelSize = _ScreenParams.zw - 1.0; // 1/width, 1/height

                float totalEdgeStrength = 0.0;

                // ==================== DEPTH EDGE DETECTION ====================
                if (_EnableDepthEdges > 0.5)
                {
                    float depthEdge = SobelDepth(screenUV, texelSize, _DepthEdgeSampleDistance);

                    // Apply threshold with smoothstep
                    float minThresh = _DepthEdgeThreshold - _EdgeSmoothness * 0.5;
                    float maxThresh = _DepthEdgeThreshold + _EdgeSmoothness * 0.5;
                    depthEdge = smoothstep(minThresh, maxThresh, depthEdge);

                    totalEdgeStrength += depthEdge * _DepthEdgeStrength;
                }

                // ==================== SCREEN NORMAL EDGE DETECTION ====================
                if (_EnableScreenNormalEdges > 0.5)
                {
                    float normalEdge = SobelNormal(screenUV, texelSize, _ScreenNormalSampleDistance);

                    // Apply threshold with smoothstep
                    float minThresh = _ScreenNormalEdgeThreshold - _EdgeSmoothness;
                    float maxThresh = _ScreenNormalEdgeThreshold + _EdgeSmoothness;
                    normalEdge = smoothstep(minThresh, maxThresh, normalEdge);

                    totalEdgeStrength += normalEdge * _ScreenNormalEdgeStrength;
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

                // Apply edges
                shaded = lerp(shaded, _EdgeColor.rgb, totalEdgeStrength);

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
