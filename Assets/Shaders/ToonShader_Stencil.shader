// Stencil-Based Toon Shader - Zero Z-Fighting Outlines
// This shader uses a stencil buffer to completely eliminate outline flickering.
// Requires ToonOutlineRendererFeature to be added to your URP Renderer.

Shader "Custom/ToonShader_Stencil"
{
    Properties
    {
        [Header(Main Settings)]
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        [Header(Toon Shading)]
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        [Header(Outline)]
        _OuterOutlineWidth ("Outline Width", Range(0, 0.5)) = 0.01
        _OuterOutlineColor ("Outline Color", Color) = (0,0,0,1)
        [Toggle] _ScreenSpaceOutline ("Screen-Space Width", Float) = 0

        [Header(Rim Light)]
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0

        [Header(Ambient)]
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)
        
        [Header(Transparency)]
        [Toggle] _EnableAlphaTest ("Enable Alpha Test", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode (Off = Two-Sided)", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // ============================================================
        // PASS 1: MAIN TOON SHADING (Writes to Stencil)
        // This pass renders first and marks the stencil buffer with 1
        // ============================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            
            Cull [_CullMode]  // 0 = Off (both faces), 1 = Front, 2 = Back
            ZWrite On
            ZTest LEqual
            
            // STENCIL: Write 1 everywhere we render the main mesh
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma shader_feature_local _ENABLEALPHATEST_ON

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
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _TextureIntensity;
                float _ToonSteps;
                float _ToonThreshold;
                float _ToonSmoothness;
                float _ShadowStrength;
                float4 _RimColor;
                float _RimPower;
                float4 _AmbientColor;
                float _EnableAlphaTest;
                float _AlphaCutoff;
                float _OuterOutlineWidth;
                float4 _OuterOutlineColor;
                float _ScreenSpaceOutline;
            CBUFFER_END

            v2f vert(appdata v)
            {
                v2f o;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);

                o.pos = positionInputs.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = positionInputs.positionWS;
                o.nWS = normalInputs.normalWS;
                return o;
            }

            half4 frag(v2f IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                
                // Alpha test
                #if _ENABLEALPHATEST_ON
                    clip(texColor.a - _AlphaCutoff);
                #endif
                
                // Blend texture with color
                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);

                // Normals and view direction
                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);

                // Main light
                Light mainLight = GetMainLight();
                float NdotL = saturate(dot(nWS, mainLight.direction));

                // Toon quantization
                float smooth = smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL);
                float steps = max(1.0, _ToonSteps);
                float toon = floor(smooth * steps) / steps;
                toon = lerp(1.0, toon, _ShadowStrength);
                
                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;

                // Rim lighting
                float rim = 1.0 - saturate(dot(vWS, nWS));
                rim = pow(rim, _RimPower);
                float3 rimLighting = rim * _RimColor.rgb;

                float3 shaded = albedo.rgb * lighting + rimLighting;
                
                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }

        // ============================================================
        // PASS 2: OUTLINE (Reads Stencil - Only draws where mesh ISN'T)
        // This pass is rendered by ToonOutlineRendererFeature AFTER opaques
        // ============================================================
        Pass
        {
            Name "ToonOutline"
            Tags { "LightMode"="ToonOutline" }
            
            Cull Front
            ZWrite On
            ZTest LEqual
            
            // STENCIL: Only draw where stencil is NOT 1 (outside the mesh)
            Stencil
            {
                Ref 1
                Comp NotEqual
                Pass Keep
                Fail Keep
                ZFail Keep
            }

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline
            #pragma target 3.0
            #pragma shader_feature_local _SCREENSPACEOUTLINE_ON
            #pragma shader_feature_local _ENABLEALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata_outline
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f_outline
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _TextureIntensity;
                float _ToonSteps;
                float _ToonThreshold;
                float _ToonSmoothness;
                float _ShadowStrength;
                float4 _RimColor;
                float _RimPower;
                float4 _AmbientColor;
                float _EnableAlphaTest;
                float _AlphaCutoff;
                float _OuterOutlineWidth;
                float4 _OuterOutlineColor;
                float _ScreenSpaceOutline;
            CBUFFER_END

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;
                
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);
                
                #if _SCREENSPACEOUTLINE_ON
                    // Screen-space outline: consistent pixel width regardless of distance
                    float3 clipNormal = TransformWorldToHClipDir(normalInputs.normalWS);
                    float4 clipPos = TransformWorldToHClip(positionInputs.positionWS);
                    float2 offset = normalize(clipNormal.xy) * _OuterOutlineWidth * clipPos.w * 0.1;
                    clipPos.xy += offset;
                    o.pos = clipPos;
                #else
                    // World-space outline: fixed world units thickness
                    float3 posWS = positionInputs.positionWS + normalInputs.normalWS * _OuterOutlineWidth;
                    o.pos = TransformWorldToHClip(posWS);
                #endif
                
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                // Alpha test for transparent parts (eyelashes, etc.)
                #if _ENABLEALPHATEST_ON
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a;
                    clip(alpha - _AlphaCutoff);
                #endif
                
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // ============================================================
        // PASS 3: Shadow Caster (for casting shadows)
        // ============================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma shader_feature_local _ENABLEALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _TextureIntensity;
                float _ToonSteps;
                float _ToonThreshold;
                float _ToonSmoothness;
                float _ShadowStrength;
                float4 _RimColor;
                float _RimPower;
                float4 _AmbientColor;
                float _EnableAlphaTest;
                float _AlphaCutoff;
                float _OuterOutlineWidth;
                float4 _OuterOutlineColor;
                float _ScreenSpaceOutline;
            CBUFFER_END

            float3 _LightDirection;

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
                
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                
                output.positionCS = positionCS;
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                #if _ENABLEALPHATEST_ON
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                    clip(alpha - _AlphaCutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // ============================================================
        // PASS 4: Depth Only (for depth prepass)
        // ============================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma shader_feature_local _ENABLEALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

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

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _TextureIntensity;
                float _ToonSteps;
                float _ToonThreshold;
                float _ToonSmoothness;
                float _ShadowStrength;
                float4 _RimColor;
                float _RimPower;
                float4 _AmbientColor;
                float _EnableAlphaTest;
                float _AlphaCutoff;
                float _OuterOutlineWidth;
                float4 _OuterOutlineColor;
                float _ScreenSpaceOutline;
            CBUFFER_END

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                #if _ENABLEALPHATEST_ON
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).a;
                    clip(alpha - _AlphaCutoff);
                #endif
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
