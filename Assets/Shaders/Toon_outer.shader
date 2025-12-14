Shader "Custom/ToonShader_OuterInner_Fixed"
{
    Properties
    {
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        // Toon shading
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        // Outer outline (geometry-based)
        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.01
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)

        // Inner lines
        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 1.0)) = 0.05
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.5, 10.0)) = 1.0

        // Rim
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0

        // Ambient
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)
        
        // Debug
        [Toggle] _ShowTextureOnly ("Show Texture Only (Debug)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        // OUTER OUTLINE PASS
        Pass
        {
            Name "OuterOutline"
            Tags { "Queue"="Geometry+1" } 
            Cull Front
            ZWrite Off
            ZTest LEqual
            Blend Off

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata_outline
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f_outline
            {
                float4 pos : SV_POSITION;
            };

            float _OuterOutlineWidth;
            float4 _OuterOutlineColor;

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;

                // World position and normal using URP functions
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);

                // Expand along world normal
                float3 posWS = positionInputs.positionWS + normalInputs.normalWS * _OuterOutlineWidth;

                // Transform to clip
                o.pos = TransformWorldToHClip(posWS);
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // MAIN TOON PASS (includes inner-line detection)
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT

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
                float3 nWS  : TEXCOORD2;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
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

            float _EnableInnerLines;
            float4 _InnerLineColor;
            float _InnerLineThreshold;
            float _InnerLineBlur;
            float _ShowTextureOnly;

            v2f vert(appdata v)
            {
                v2f o;
                // World-space pos and normal using URP functions
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);

                o.pos = positionInputs.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.posWS = positionInputs.positionWS;
                o.nWS = normalInputs.normalWS;
                return o;
            }

            // Helper to sample the main directional light using URP functions
            static inline void GetDirectionalLight(out float3 dir, out float3 color)
            {
                // Get main light from URP
                Light mainLight = GetMainLight();
                dir = mainLight.direction;
                color = mainLight.color;
            }

            half4 frag(v2f IN) : SV_Target
            {
                // Sample albedo
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                // Blend texture with color, controlled by texture intensity
                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);
                
                // Debug mode: show texture only
                if (_ShowTextureOnly > 0.5)
                {
                    return albedo;
                }

                // Normals and view dir
                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);

                // Main directional light
                float3 lightDir;
                float3 lightColor;
                GetDirectionalLight(lightDir, lightColor);
                // Ensure lightDir points from surface toward light (legacy _WorldSpaceLightPos0 is that already)
                float NdotL = saturate(dot(nWS, lightDir));

                // Toon quantization: smooth the threshold area a little, then quantize into steps
                float smooth = smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL);
                float steps = max(1.0, _ToonSteps);
                float toon = floor(smooth * steps) / steps;

                // Apply shadow strength to make shadows more visible
                toon = lerp(1.0, toon, _ShadowStrength);
                
                float3 lighting = lightColor * toon + _AmbientColor.rgb;

                // Rim (Fresnel-like)
                float rim = 1.0 - saturate(dot(vWS, nWS));
                rim = pow(rim, _RimPower);
                float3 rimLighting = rim * _RimColor.rgb;

                float3 shaded = albedo.rgb * lighting + rimLighting;

                // -------- INNER-LINE DETECTION (Simple Max Difference) --------
                if (_EnableInnerLines > 0.5)
                {
                    // Sample offset based on blur parameter
                    float offset = _InnerLineBlur * 0.01;
                    
                    // Sample RAW texture at center
                    half4 centerSample = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                    float center = dot(centerSample.rgb, float3(0.299, 0.587, 0.114));
                    
                    // Sample 4 cardinal directions from RAW texture
                    float n  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
                    float s  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
                    float e  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
                    float w  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
                    
                    // Find maximum absolute difference from center
                    float maxDiff = 0.0;
                    maxDiff = max(maxDiff, abs(center - n));
                    maxDiff = max(maxDiff, abs(center - s));
                    maxDiff = max(maxDiff, abs(center - e));
                    maxDiff = max(maxDiff, abs(center - w));
                    
                    // Simple hard threshold
                    float edge = (maxDiff > _InnerLineThreshold) ? 1.0 : 0.0;
                    
                    // Mix inner line color
                    shaded = lerp(shaded, _InnerLineColor.rgb, edge);
                }

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        } // End main pass
    } // End SubShader

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}

