Shader "Custom/ToonShader_OuterInner_Fixed"
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
        _OuterOutlineWidth ("Outer Outline Width (world units)", Range(0,0.5)) = 0.01
        _OuterOutlineColor ("Outer Outline Color", Color) = (0,0,0,1)
        [Toggle] _UseOutlineDepthOffset ("Use Depth Offset (fix z-fighting)", Float) = 0
        _OutlineDepthBias ("Outline Depth Bias", Range(0, 5)) = 1.0

        // Inner lines
        [Toggle] _EnableInnerLines ("Enable Inner Lines", Float) = 1
        _InnerLineColor ("Inner Line Color", Color) = (0,0,0,1)
        _InnerLineThreshold ("Inner Line Threshold", Range(0.001, 0.5)) = 0.03
        _InnerLineBlur ("Inner Line Sample Distance", Range(0.5, 10.0)) = 2.0
        _InnerLineStrength ("Inner Line Strength", Range(0, 1)) = 1.0

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
            #pragma shader_feature_local _USEOUTLINEDEPTHOFFSET_ON

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
            float _OutlineDepthBias;

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
                
                // Apply depth bias in clip space if enabled
                #if _USEOUTLINEDEPTHOFFSET_ON
                    // Push outline away from camera (increase depth) to render behind mesh edges
                    o.pos.z += _OutlineDepthBias * 0.001;
                #endif
                
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
                
                // Alpha test - discard transparent pixels (for eyelashes, if enabled)
                if (_EnableAlphaTest > 0.5)
                {
                    clip(texColor.a - _AlphaCutoff);
                }
                
                // Debug mode: override with default values
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

//                // -------- INNER-LINE DETECTION (Sobel + Non-Maximum Suppression) --------
// if (_EnableInnerLines > 0.5)
// {
//     float offset = _InnerLineBlur * 0.001;
    
//     // Sobel sampling (same as above)
//     float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float c  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv).rgb, float3(0.299, 0.587, 0.114));
//     float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
//     float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
//     float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    
//     float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
//     float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
//     float edgeMag = sqrt(sobelX * sobelX + sobelY * sobelY);
    
//     // Determine gradient direction and check if we're at a local maximum
//     float2 gradDir = normalize(float2(sobelX, sobelY) + 0.0001);
    
//     // Sample along gradient direction
//     float2 posOffset = gradDir * offset;
//     float edgePlus = sqrt(
//         pow(dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + posOffset + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114)) -
//             dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + posOffset + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114)), 2.0) +
//         pow(dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + posOffset + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114)) -
//             dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + posOffset + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114)), 2.0));
    
//     float edgeMinus = sqrt(
//         pow(dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv - posOffset + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114)) -
//             dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv - posOffset + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114)), 2.0) +
//         pow(dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv - posOffset + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114)) -
//             dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv - posOffset + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114)), 2.0));
    
//     // Only keep if local maximum
//     float isMax = (edgeMag >= edgePlus && edgeMag >= edgeMinus) ? 1.0 : 0.0;
//     float edge = step(_InnerLineThreshold, edgeMag) * isMax * _InnerLineStrength;
    
//     shaded = lerp(shaded, _InnerLineColor.rgb, edge);
// }


// // -------- IMPROVED INNER-LINE DETECTION (Normal + Texture Sobel) --------
// if (_EnableInnerLines > 0.5)
// {
//     float offset = _InnerLineBlur * 0.001;
    
//     // ===== NORMAL-BASED EDGE DETECTION =====
//     // Sample neighboring normals using screen-space derivatives
//     float3 normalCenter = nWS;
    
//     // Use ddx/ddy to detect normal discontinuities (geometry edges)
//     float3 normalDdx = ddx(nWS);
//     float3 normalDdy = ddy(nWS);
    
//     // Calculate normal variation magnitude
//     float normalEdge = length(normalDdx) + length(normalDdy);
//     normalEdge = saturate(normalEdge * 10.0); // Scale for visibility
    
//     // ===== IMPROVED TEXTURE-BASED EDGE DETECTION =====
//     // Use larger kernel for smoother edges
//     float offset2 = offset * 2.0;
    
//     // Sample with wider spacing to reduce noise
//     float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset2, offset2)).rgb, float3(0.299, 0.587, 0.114));
//     float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, offset2)).rgb, float3(0.299, 0.587, 0.114));
//     float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(offset2, offset2)).rgb, float3(0.299, 0.587, 0.114));
//     float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(-offset2, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float c  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv).rgb, float3(0.299, 0.587, 0.114));
//     float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset2, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(-offset2, -offset2)).rgb, float3(0.299, 0.587, 0.114));
//     float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset2)).rgb, float3(0.299, 0.587, 0.114));
//     float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(offset2, -offset2)).rgb, float3(0.299, 0.587, 0.114));
    
//     float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
//     float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
//     float textureEdge = sqrt(sobelX * sobelX + sobelY * sobelY);
    
//     // ===== COMBINE EDGES WITH SMOOTH THRESHOLD =====
//     // Combine normal and texture edges (normal edges are more reliable for geometry)
//     float combinedEdge = max(normalEdge * 0.8, textureEdge);
    
//     // Use smoothstep instead of hard step for cleaner lines
//     float lowerThreshold = _InnerLineThreshold * 0.5;
//     float upperThreshold = _InnerLineThreshold * 1.5;
//     float edge = smoothstep(lowerThreshold, upperThreshold, combinedEdge) * _InnerLineStrength;
    
//     // Apply inner line color
//     shaded = lerp(shaded, _InnerLineColor. rgb, edge);
// }


// // -------- CAMERA-INDEPENDENT INNER-LINE DETECTION --------
// if (_EnableInnerLines > 0.5)
// {
//     // Use UV-space offset instead of screen-space
//     // This makes lines stable regardless of camera position
//     float2 texelSize = float2(1.0 / 1024.0, 1.0 / 1024.0); // Adjust to your texture resolution
//     float offset = _InnerLineBlur * texelSize. x * 10.0;
    
//     // ===== UV-SPACE SOBEL (Camera Independent) =====
//     float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(offset, offset)).rgb, float3(0.299, 0.587, 0.114));
//     float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
//     float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
//     float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
//     float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN. uv + float2(offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    
//     float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
//     float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
//     float textureEdge = sqrt(sobelX * sobelX + sobelY * sobelY);
    
//     // ===== OBJECT-SPACE NORMAL EDGE (Camera Independent) =====
//     // Use fwidth in UV space for stable normal discontinuity
//     float3 normalDdx = ddx(IN.nWS) / max(0.0001, fwidth(IN.uv. x));
//     float3 normalDdy = ddy(IN.nWS) / max(0.0001, fwidth(IN.uv.y));
//     float normalEdge = saturate((length(normalDdx) + length(normalDdy)) * _InnerLineBlur);
    
//     // Combine:  prioritize texture edges (they're fully UV-based and stable)
//     float combinedEdge = max(textureEdge, normalEdge * 0.3);
    
//     // Smooth threshold
//     float edge = smoothstep(_InnerLineThreshold * 0.7, _InnerLineThreshold * 1.3, combinedEdge) * _InnerLineStrength;
    
//     shaded = lerp(shaded, _InnerLineColor. rgb, edge);
// }
if (_EnableInnerLines > 0.5)
{
    // Texture-based edge detection with aggressive blur to eliminate artifacts
    float offset = _InnerLineBlur * 0.001;
    
    // Pre-blur with larger 9-tap Gaussian filter to smooth noise
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
    
    // Sample 8 directions for Sobel operator
    float tl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, offset)).rgb, float3(0.299, 0.587, 0.114));
    float t  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
    float tr = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, offset)).rgb, float3(0.299, 0.587, 0.114));
    float l  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float r  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float bl = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(-offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float b  = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float br = dot(SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv + float2(offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    
    // Sobel operator
    float sobelX = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float sobelY = (tl + 2.0 * t + tr) - (bl + 2.0 * b + br);
    float edgeMagnitude = sqrt(sobelX * sobelX + sobelY * sobelY);
    
    // Aggressive filtering: only show edges above noise threshold
    // Use wider smoothstep range and add minimum cutoff
    float minEdge = _InnerLineThreshold * 0.2; // Ignore very weak edges (noise)
    float maxEdge = _InnerLineThreshold * 2.0; // Wider range for smoother transition
    
    float edge = smoothstep(minEdge, maxEdge, edgeMagnitude);
    edge = smoothstep(0.3, 0.7, edge); // Second pass for ultra-smooth result
    edge = pow(edge, 1.5); // Power curve to suppress weak edges further
    edge *= _InnerLineStrength;
    
    shaded = lerp(shaded, _InnerLineColor.rgb, edge);
}
  
                return half4(shaded, albedo.a);
            }
            ENDHLSL
        } // End main pass
    } // End SubShader

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}

