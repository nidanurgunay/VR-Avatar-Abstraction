// STENCIL VERSION - Works with Forward Rendering only
// Uses stencil buffer to mask outlines (main pass writes, outline reads)
// NOTE: Does NOT work with Deferred Rendering - use non-stencil version instead

Shader "Custom/ToonShader_OuterInner_Stencil"
{
    Properties
    {
        [Header(Debug Mode)]
        [Toggle] _UseDebugDefaults ("Use Debug Defaults (overrides all settings below)", Float) = 0
        [Space(10)]
        
        _Color ("Main Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _TextureIntensity ("Texture Intensity", Range(0, 1)) = 1.0

        // Toon shading
        _ToonSteps ("Shading Steps", Range(1, 10)) = 3
        _ToonThreshold ("Threshold", Range(0, 1)) = 0.5
        _ToonSmoothness ("Smoothness", Range(0.001, 0.1)) = 0.01
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.7

        // Outer outline (geometry-based)
        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.005
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)

        // Inner lines
        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

        // Rim
        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0

        // Ambient
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)
        
        // Transparency
        [Toggle] _EnableAlphaTest ("Enable Alpha Test (for eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.07
        [Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode (Off = Two-Sided)", Float) = 2
        
        // Debug
        [Toggle] _ShowTextureOnly ("Show Texture Only (Debug)", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // OUTER OUTLINE PASS - Uses stencil to prevent z-fighting
        // Rendered by ToonOutlineRendererFeature AFTER the main pass
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
                float2 uv : TEXCOORD0;
            };

            struct v2f_outline
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            float4 _MainTex_ST;
            float _OuterOutlineWidth;
            float4 _OuterOutlineColor;
            float _AlphaCutoff;
            float _EnableAlphaTest;

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
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag_outline(v2f_outline i) : SV_Target
            {
                // Sample texture alpha and clip transparent pixels (if enabled)
                if (_EnableAlphaTest > 0.5)
                {
                    half alpha = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).a;
                    clip(alpha - _AlphaCutoff);
                }
                return _OuterOutlineColor;
            }
            ENDHLSL
        }

        // MAIN TOON PASS (includes inner-line detection)
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_CullMode]
            ZWrite On
            ZTest LEqual
            
            // STENCIL: Write 1 to mark where main mesh is rendered
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
            float _InnerLineBlur;
            float _InnerLineStrength;
            float _EnableAlphaTest;
            float _ShowTextureOnly;
            float _AlphaCutoff;
            float _UseDebugDefaults;
            float4 _OuterOutlineColor;

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
                
                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }
                
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
                    float offset = _InnerLineBlur * 0.001;
                    
                    float blurOffset = offset * 0.7;
                    float c = 0.0;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    c += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, offset)).rgb, float3(0.299, 0.587, 0.114));
                    float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
                    float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, offset)).rgb, float3(0.299, 0.587, 0.114));
                    float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
                    float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
                    float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
                    float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
                    float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
                    
                    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
                    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);
                    
                    float minEdge = _InnerLineThreshold * 0.2;
                    float maxEdge = _InnerLineThreshold * 2.0;
                    
                    float edge = smoothstep(minEdge, maxEdge, edgeMagnitude);
                    edge = smoothstep(0.3, 0.7, edge);
                    edge = pow(edge, 1.5);
                    edge *= _InnerLineStrength;
                    
                    shaded = lerp(shaded, _InnerLineColor.rgb, edge);
                }
  
                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
