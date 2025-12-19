Shader "Custom/ToonShader_Improved"
{
    Properties
    {
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01

        // Outline
        _OutlineWidth ("Outline Width (world units)", Range(0, 0.5)) = 0.005
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)

        // Rim
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0

        // Ambient (safer than hardcoding)
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)

        // Ramp texture for artistic control (optional)
        _UseRamp ("Use Ramp", Float) = 0
        _RampTex ("Ramp (1D)", 2D) = "gray" {}

        // Specular (toon highlight)
        _SpecColor ("Specular Color", Color) = (1,1,1,1)
        _SpecThreshold ("Specular Threshold", Range(0,1)) = 0.9
        _SpecPower ("Specular Power", Range(1, 64)) = 16
        
        // Transparency
        [Toggle] _EnableAlphaTest ("Enable Alpha Test (for eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode (Off = Two-Sided)", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // Outline Pass - Uses stencil to prevent z-fighting
        Pass
        {
            Name "ToonOutline"
            Tags { "LightMode"="ToonOutline" }
            
            Cull Front
            ZWrite On
            ZTest LEqual
            
            Stencil
            {
                Ref 1
                Comp NotEqual
                Pass Keep
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float _OutlineWidth;
                float4 _OutlineColor;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;

                // Use URP helpers to get world-space data
                VertexPositionInputs posIn = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normIn = GetVertexNormalInputs(input.normalOS);

                // Expand in world space so outline is scale-invariant
                float3 posWS = posIn.positionWS + normIn.normalWS * _OutlineWidth;

                // Transform expanded world-space position to clip
                output.positionHCS = TransformWorldToHClip(posWS);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }

        // Main Toon Shading Pass
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            
            Cull [_CullMode]
            ZWrite On
            ZTest LEqual
            
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

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
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 viewDirWS : TEXCOORD3;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_RampTex);
            SAMPLER(sampler_RampTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _ToonSteps;
                float _ToonThreshold;
                float _ToonSmoothness;
                float4 _RimColor;
                float _RimPower;
                float4 _AmbientColor;
                float _UseRamp;
                float4 _SpecColor;
                float _SpecThreshold;
                float _SpecPower;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                output.positionHCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.viewDirWS = GetWorldSpaceViewDir(positionInputs.positionWS);
                output.uv = TRANSFORM_TEX(input.uv, _MainTex);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                half4 albedo = texColor * _Color;

                float3 normalWS = normalize(input.normalWS);
                float3 viewDirWS = normalize(input.viewDirWS);

                // Main directional light
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);

                // Diffuse dot and clamping (safe input for smoothstep)
                float NdotL = saturate(dot(normalWS, lightDir));

                // Option 1: Ramp texture lookup (artist controlled) ----------------
                float toonValue;
                if (_UseRamp > 0.5)
                {
                    // Sample ramp along x. Ramp texture should be set up as a gradient horizontally.
                    // Use NdotL as UV.x, uv.y free (0.5).
                    float2 rampUV = float2(NdotL, 0.5);
                    half4 rampSample = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, rampUV);
                    toonValue = rampSample.r; // assume ramp encodes intensity in R channel
                }
                else
                {
                    // Option 2: Smoothstep + quantize (previous behavior)
                    float stepped = smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL);
                    toonValue = floor(stepped * max(1.0, _ToonSteps)) / max(1.0, _ToonSteps);
                }

                half3 lighting = mainLight.color * toonValue;

                // Ambient (from property to start)
                lighting += _AmbientColor.rgb;

                // Specular (toon-style): Blinn-vector based quantized highlight
                float3 halfVec = normalize(viewDirWS + lightDir);
                float NdotH = saturate(dot(normalWS, halfVec));
                // Soft-power then threshold for toon spec
                float spec = pow(NdotH, _SpecPower);
                // quantize/spec threshold
                spec = step(_SpecThreshold, spec);
                lighting += _SpecColor.rgb * spec;

                // Rim lighting
                float rim = 1.0 - saturate(dot(viewDirWS, normalWS));
                rim = pow(rim, _RimPower);
                half3 rimLighting = rim * _RimColor.rgb;

                half3 finalColor = albedo.rgb * lighting + rimLighting;

                return half4(finalColor, albedo.a);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}