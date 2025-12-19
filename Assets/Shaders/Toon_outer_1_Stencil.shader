// STENCIL VERSION - Works with Forward Rendering only
// Screen-space outline width variant with stencil masking
// NOTE: Does NOT work with Deferred Rendering - use non-stencil version instead

Shader "Custom/ToonShader_OuterInner_Backup_Stencil"
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
        _InnerLineThreshold ("Inner Line Threshold", Range(0.01, 50.0)) = 25.0
        _InnerLineSmooth ("Inner Line Smoothness", Range(0.001, 5.0)) = 0.5
        _InnerLineWidth ("Inner Line Width", Range(0.5, 3.0)) = 1.0
        _InnerLineBlur ("Inner Line Blur/Soften", Range(0.0, 3.0)) = 0.5

        // Rim
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0

        // Ambient
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)
        
        // Transparency
        [Toggle] _EnableAlphaTest ("Enable Alpha Test (for eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode (Off = Two-Sided)", Float) = 2
        
        // Debug
        [Toggle] _ShowTextureOnly ("Show Texture Only (Debug)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // OUTER OUTLINE PASS - Uses stencil to prevent z-fighting
        Pass
        {
            Name "ToonOutline"
            Tags { "LightMode"="ToonOutline" }
            
            Cull Front
            ZWrite On
            ZTest LEqual
            
            // STENCIL: Only draw where stencil is NOT 1
            Stencil
            {
                Ref 1
                Comp NotEqual
                Pass Keep
            }

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

                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal);
                
                // Screen-space consistent outline
                float3 clipNormal = TransformWorldToHClipDir(normalInputs.normalWS);
                float4 clipPos = TransformWorldToHClip(positionInputs.positionWS);
                float2 offset = normalize(clipNormal.xy) * _OuterOutlineWidth * clipPos.w * 0.1;
                clipPos.xy += offset;
                
                o.pos = clipPos;
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // MAIN TOON PASS
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_CullMode]
            ZWrite On
            ZTest LEqual
            
            // STENCIL: Write 1 to mark mesh pixels
            Stencil
            {
                Ref 1
                Comp Always
                Pass Replace
            }

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
            float _InnerLineSmooth;
            float _InnerLineWidth;
            float _InnerLineBlur;
            float _ShowTextureOnly;

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

            static inline void GetDirectionalLight(out float3 dir, out float3 color)
            {
                Light mainLight = GetMainLight();
                dir = mainLight.direction;
                color = mainLight.color;
            }

            half4 frag(v2f IN) : SV_Target
            {
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);
                
                if (_ShowTextureOnly > 0.5)
                {
                    return albedo;
                }

                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);

                float3 lightDir;
                float3 lightColor;
                GetDirectionalLight(lightDir, lightColor);
                float NdotL = saturate(dot(nWS, lightDir));

                float smooth = smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL);
                float steps = max(1.0, _ToonSteps);
                float toon = floor(smooth * steps) / steps;
                toon = lerp(1.0, toon, _ShadowStrength);
                
                float3 lighting = lightColor * toon + _AmbientColor.rgb;

                float rim = 1.0 - saturate(dot(vWS, nWS));
                rim = pow(rim, _RimPower);
                float3 rimLighting = rim * _RimColor.rgb;

                float3 shaded = albedo.rgb * lighting + rimLighting;

                // Inner line detection
                if (_EnableInnerLines > 0.5)
                {
                    float texLum = dot(texColor.rgb, float3(0.299, 0.587, 0.114));
                    
                    float blurOffset = _InnerLineBlur * length(fwidth(IN.uv));
                    float texLumBlurred = texLum;
                    if (_InnerLineBlur > 0.01)
                    {
                        texLumBlurred += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114));
                        texLumBlurred += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114));
                        texLumBlurred += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114));
                        texLumBlurred += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114));
                        texLumBlurred /= 5.0;
                    }
                    
                    float2 texGrad = float2(ddx(texLumBlurred), ddy(texLumBlurred));
                    float gradMag = length(texGrad);
                    
                    float uvScale = length(fwidth(IN.uv));
                    uvScale = max(uvScale, 0.0001);
                    float normalizedGrad = gradMag / uvScale;
                    
                    normalizedGrad *= _InnerLineWidth;
                    
                    float smoothRange = _InnerLineSmooth * 2.0;
                    float edge = smoothstep(_InnerLineThreshold - smoothRange, _InnerLineThreshold + smoothRange, normalizedGrad);
                    
                    float innerEdge = pow(edge, 0.5);
                    innerEdge = smoothstep(0.2, 0.8, innerEdge);
                    
                    shaded = lerp(shaded, _InnerLineColor.rgb, innerEdge);
                }

                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
