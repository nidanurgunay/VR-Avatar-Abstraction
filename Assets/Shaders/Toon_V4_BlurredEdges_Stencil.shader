// STENCIL VERSION - Works with Forward Rendering only
// Version 4: Pre-Blurred Sobel with stencil-based outline masking
// NOTE: Does NOT work with Deferred Rendering - use non-stencil version instead

Shader "Custom/ToonShader_V4_BlurredEdges_Stencil"
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

        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.2
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.0, 10.0)) = 0.5
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

        _RimColor ("Rim Color", Color) = (0.408,0.408,0.408,1)
        _RimPower ("Rim Power", Range(0.1, 8.0)) = 3.0
        _AmbientColor ("Ambient Color", Color) = (0.3,0.3,0.3,1)
        
        // Transparency
        [Toggle] _EnableAlphaTest ("Enable Alpha Test (for eyelashes)", Float) = 0
        _AlphaCutoff ("Alpha Cutoff", Range(0, 1)) = 0.07
        [Enum(Off,0,Front,1,Back,2)] _CullMode ("Cull Mode (Off = Two-Sided)", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // OUTLINE PASS with STENCIL masking
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

            v2f_outline vert_outline(appdata_outline v)
            {
                v2f_outline o;
                VertexPositionInputs posInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(v.normal);
                o.pos = TransformWorldToHClip(posInputs.positionWS + normInputs.normalWS * _OuterOutlineWidth);
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

        // MAIN PASS with STENCIL write
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata { float4 vertex : POSITION; float3 normal : NORMAL; float2 uv : TEXCOORD0; };
            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; float3 posWS : TEXCOORD1; float3 nWS : TEXCOORD2; };

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            float4 _MainTex_ST, _Color, _RimColor, _AmbientColor, _InnerLineColor, _OuterOutlineColor;
            float _TextureIntensity, _ToonSteps, _ToonThreshold, _ToonSmoothness, _ShadowStrength;
            float _RimPower, _EnableInnerLines, _InnerLineThreshold, _InnerLineBlur, _InnerLineStrength;
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
                    _InnerLineColor = float4(0, 0, 0, 1);
                }
                
                half4 texColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);
                
                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }
                
                half3 baseColor = lerp(_Color.rgb, texColor.rgb * _Color.rgb, _TextureIntensity);
                half4 albedo = half4(baseColor, texColor.a * _Color.a);
                
                // DETECT EDGES ON RAW TEXTURE BEFORE LIGHTING
                float edgeStrength = 0.0;
                if (_EnableInnerLines > 0.5)
                {
                    float offset = _InnerLineBlur * 0.001;
                    float blurOffset = offset * 1.2;
                    
                    float tl = 0.0, t = 0.0, tr = 0.0, l = 0.0, c = 0.0, r = 0.0, bl = 0.0, b = 0.0, br = 0.0;
                    
                    // Top-left with blur
                    float2 uv_tl = IN.uv + float2(-offset, offset);
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tl + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Top center with blur
                    float2 uv_t = IN.uv + float2(0, offset);
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    t += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_t + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Top-right with blur
                    float2 uv_tr = IN.uv + float2(offset, offset);
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    tr += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_tr + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Left with blur
                    float2 uv_l = IN.uv + float2(-offset, 0);
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    l += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_l + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Right with blur
                    float2 uv_r = IN.uv + float2(offset, 0);
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    r += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_r + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Bottom-left with blur
                    float2 uv_bl = IN.uv + float2(-offset, -offset);
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    bl += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_bl + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Bottom center with blur
                    float2 uv_b = IN.uv + float2(0, -offset);
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    b += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_b + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Bottom-right with blur
                    float2 uv_br = IN.uv + float2(offset, -offset);
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br).rgb, float3(0.299, 0.587, 0.114)) * 0.25;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(-blurOffset, 0)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(0, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(0, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.125;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(-blurOffset, blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    br += dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv_br + float2(-blurOffset, -blurOffset)).rgb, float3(0.299, 0.587, 0.114)) * 0.0625;
                    
                    // Sobel operator
                    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
                    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
                    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);
                    
                    float minEdge = _InnerLineThreshold * 0.85;
                    float maxEdge = _InnerLineThreshold * 1.15;
                    float edge = smoothstep(minEdge, maxEdge, edgeMagnitude);
                    edge = smoothstep(0.47, 0.53, edge);
                    edge = smoothstep(0.35, 0.65, edge);
                    edge = smoothstep(0.25, 0.75, edge);
                    edge = pow(edge, 3.0);
                    
                    edgeStrength = edge * _InnerLineStrength;
                }
                
                // Calculate lighting
                float3 nWS = normalize(IN.nWS);
                float3 vWS = normalize(_WorldSpaceCameraPos - IN.posWS);
                Light mainLight = GetMainLight();
                
                float NdotL = saturate(dot(nWS, mainLight.direction));
                float toon = floor(smoothstep(_ToonThreshold - _ToonSmoothness, _ToonThreshold + _ToonSmoothness, NdotL) * _ToonSteps) / _ToonSteps;
                toon = lerp(1.0, toon, _ShadowStrength);
                
                float3 lighting = mainLight.color * toon + _AmbientColor.rgb;
                float rim = pow(1.0 - saturate(dot(vWS, nWS)), _RimPower);
                float3 shaded = albedo.rgb * lighting + rim * _RimColor.rgb;
                
                shaded = lerp(shaded, _InnerLineColor.rgb, edgeStrength);
                
                return half4(shaded, albedo.a);
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    CustomEditor "ToonShaderEditor"
}
