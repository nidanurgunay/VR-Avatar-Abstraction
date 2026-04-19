// =============================================================================
// Halftone & Hatching Shader - Unity URP
// =============================================================================
// Combines multiple stylization patterns driven by lighting intensity:
//   - Halftone dots (screen-space or object-space)
//   - Cross-hatching lines (single, cross, and dense variants)
//   - Stippling (noise-based dot pattern)
//
// Patterns transition based on a Tonal Art Map (TAM) concept from
// Praun et al. "Real-Time Hatching" (SIGGRAPH 2001) and halftone
// techniques common in comic/manga rendering.
//
// Usage: Assign to materials. Patterns respond to scene lighting.
//        Can also be used as a post-process (see comments at bottom).
// =============================================================================

Shader "NPR/HalftoneHatching"
{
    Properties
    {
        [Header(Base)]
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _BaseMap ("Base Map", 2D) = "white" {}
        _InkColor ("Ink/Pattern Color", Color) = (0.05, 0.05, 0.1, 1)
        _PaperColor ("Paper Color", Color) = (0.95, 0.93, 0.88, 1)
        _TextureInfluence ("Texture Influence", Range(0, 1)) = 0.5

        [Header(Pattern Mode)]
        [KeywordEnum(Halftone, Hatching, Stipple, Combined)]
        _PatternMode ("Pattern Mode", Float) = 0

        [Header(Halftone)]
        _HalftoneScale ("Dot Scale", Range(2, 100)) = 30.0
        _HalftoneSharpness ("Dot Sharpness", Range(1, 50)) = 10.0
        [KeywordEnum(ScreenSpace, ObjectSpace, WorldSpace)]
        _HalftoneSpace ("Coordinate Space", Float) = 2
        _HalftoneAngle ("Dot Grid Angle", Range(0, 90)) = 45.0

        [Header(Hatching)]
        [KeywordEnum(Line, Dots, Composition)]
        _HatchStyle ("Hatch Style", Float) = 0
        _HatchScale ("Hatch Scale", Range(1, 100)) = 20.0
        _HatchAngle ("Primary Hatch Angle", Range(0, 180)) = 45.0
        _HatchThickness ("Line Thickness", Range(0.01, 0.5)) = 0.15
        _CrossHatchAngle ("Cross Hatch Angle", Range(0, 180)) = 135.0
        _DotSize ("Dot Size", Range(0.01, 0.4)) = 0.12

        [Header(Stipple)]
        _StippleScale ("Stipple Scale", Range(5, 200)) = 50.0
        _StippleDensity ("Stipple Density", Range(0, 2)) = 1.0

        [Header(Lighting Response)]
        _ToneLevels ("Tone Levels (pattern density steps)", Range(2, 8)) = 5
        _ToneBias ("Shadow Bias", Range(-0.5, 0.5)) = 0.0

        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.002

        [Header(Surface)]
        [HideInInspector] _SrcBlend  ("__src",  Float) = 1
        [HideInInspector] _DstBlend  ("__dst",  Float) = 0
        [HideInInspector] _ZWrite    ("__zw",   Float) = 1
        _Alpha       ("Alpha",              Range(0, 1)) = 1.0
        _AlphaCutoff ("Alpha Cutoff",       Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        // =================================================================
        // PASS 0: Halftone/Hatching Forward Pass
        // =================================================================
        Pass
        {
            Name "HalftoneHatchingForward"
            Tags { "LightMode" = "UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature_local _PATTERNMODE_HALFTONE _PATTERNMODE_HATCHING _PATTERNMODE_STIPPLE _PATTERNMODE_COMBINED
            #pragma shader_feature_local _HALFTONESPACE_SCREENSPACE _HALFTONESPACE_OBJECTSPACE _HALFTONESPACE_WORLDSPACE
            #pragma shader_feature_local _HATCHSTYLE_LINE _HATCHSTYLE_DOTS _HATCHSTYLE_COMPOSITION
            #pragma shader_feature_local _ALPHATEST_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _InkColor;
                float4 _PaperColor;
                float  _TextureInfluence;
                float _HalftoneScale;
                float _HalftoneSharpness;
                float _HalftoneAngle;
                float _HatchScale;
                float _HatchAngle;
                float _HatchThickness;
                float _CrossHatchAngle;
                float _StippleScale;
                float _StippleDensity;
                float _ToneLevels;
                float _ToneBias;
                float _DotSize;
                float _Alpha;
                float _AlphaCutoff;
                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

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
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 screenPos : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs nInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = vInput.positionCS;
                output.positionWS = vInput.positionWS;
                output.normalWS = nInput.normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.screenPos = ComputeScreenPos(vInput.positionCS);
                output.shadowCoord = GetShadowCoord(vInput);

                return output;
            }

            // ---- Hash function for procedural noise ----
            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            // ---- 2D rotation matrix ----
            float2 Rotate2D(float2 p, float angleDeg)
            {
                float rad = angleDeg * 0.01745329;
                float c = cos(rad);
                float s = sin(rad);
                return float2(c * p.x - s * p.y, s * p.x + c * p.y);
            }

            // ---- HALFTONE: Circular dot pattern ----
            // Returns 0 (paper) to 1 (ink) based on tone
            float HalftonePattern(float2 coords, float tone)
            {
                float2 rotCoords = Rotate2D(coords, _HalftoneAngle);
                float2 gridPos = frac(rotCoords * _HalftoneScale) - 0.5;

                // Distance from grid center = dot radius
                float dist = length(gridPos);

                // Dot radius scales with darkness (darker = bigger dots)
                float dotRadius = sqrt(1.0 - tone) * 0.5;

                // Smooth edge
                float pattern = 1.0 - smoothstep(dotRadius - 0.5 / _HalftoneSharpness,
                                                  dotRadius + 0.5 / _HalftoneSharpness, dist);
                return pattern;
            }

            // ---- HATCHING: Line-based pattern ----
            // Multiple layers activated at different tone levels
            float HatchLine(float2 coords, float angleDeg, float thickness)
            {
                float2 rotCoords = Rotate2D(coords, angleDeg);
                float linePos = frac(rotCoords.x * _HatchScale);
                float lineMask = smoothstep(thickness, thickness + 0.02, abs(linePos - 0.5));
                return 1.0 - lineMask;
            }

            float HatchingPattern(float2 coords, float tone)
            {
                // Tonal Art Map approach: more hatching layers as tone darkens
                // Level 1 (lightest shadow): single direction
                // Level 2: add cross hatch
                // Level 3: add dense fill

                float levels = _ToneLevels;
                float t = 1.0 - tone; // darkness level (0=white, 1=black)

                float pattern = 0.0;

                // Layer 1: Primary hatch (activates at moderate shadow)
                if (t > 0.15)
                {
                    float intensity = smoothstep(0.15, 0.4, t);
                    pattern = max(pattern,
                        HatchLine(coords, _HatchAngle, _HatchThickness) * intensity);
                }

                // Layer 2: Cross hatch (activates at deeper shadow)
                if (t > 0.35)
                {
                    float intensity = smoothstep(0.35, 0.6, t);
                    pattern = max(pattern,
                        HatchLine(coords, _CrossHatchAngle, _HatchThickness) * intensity);
                }

                // Layer 3: Dense diagonal (activates at very dark)
                if (t > 0.55)
                {
                    float intensity = smoothstep(0.55, 0.8, t);
                    float denseAngle = (_HatchAngle + _CrossHatchAngle) * 0.5;
                    pattern = max(pattern,
                        HatchLine(coords, denseAngle,
                            _HatchThickness * 1.5) * intensity);
                }

                // Layer 4: Fill for near-black
                if (t > 0.8)
                {
                    float intensity = smoothstep(0.8, 1.0, t);
                    pattern = max(pattern, intensity);
                }

                return pattern;
            }

            // ---- HATCHING DOTS: dots arranged along hatch direction layers ----
            float HatchDotsPattern(float2 coords, float tone)
            {
                float t = 1.0 - tone;
                float pattern = 0.0;

                // Layer 1: primary direction dots
                if (t > 0.15)
                {
                    float intensity = smoothstep(0.15, 0.4, t);
                    float2 rotCoords = Rotate2D(coords * _HatchScale, _HatchAngle);
                    float2 cell = frac(rotCoords) - 0.5;
                    float radius = _DotSize * smoothstep(0.15, 0.55, t);
                    float dot = 1.0 - smoothstep(radius - 0.04, radius + 0.04, length(cell));
                    pattern = max(pattern, dot * intensity);
                }

                // Layer 2: cross direction dots
                if (t > 0.35)
                {
                    float intensity = smoothstep(0.35, 0.6, t);
                    float2 rotCoords = Rotate2D(coords * _HatchScale, _CrossHatchAngle);
                    float2 cell = frac(rotCoords) - 0.5;
                    float radius = _DotSize * 0.8;
                    float dot = 1.0 - smoothstep(radius - 0.04, radius + 0.04, length(cell));
                    pattern = max(pattern, dot * intensity);
                }

                // Layer 3: fill for near-black
                if (t > 0.8)
                {
                    float intensity = smoothstep(0.8, 1.0, t);
                    pattern = max(pattern, intensity);
                }

                return pattern;
            }

            // ---- HATCHING COMPOSITION: lines + dots blended by tone ----
            float HatchCompositionPattern(float2 coords, float tone)
            {
                float t = 1.0 - tone;
                // Lighter areas lean toward dots, darker areas lean toward lines
                float dotWeight  = smoothstep(0.5, 0.0, t);
                float lineWeight = smoothstep(0.0, 0.5, t);
                float dots  = HatchDotsPattern(coords, tone);
                float lines = HatchingPattern(coords, tone);
                return saturate(dots * dotWeight + lines * lineWeight);
            }

            // ---- STIPPLE: Noise-based dot pattern ----
            float StipplePattern(float2 coords, float tone)
            {
                float2 gridCoords = floor(coords * _StippleScale);
                float noise = Hash21(gridCoords);

                // Darker areas have more dots
                float threshold = tone; // tone 0=dark, 1=light
                float stipple = (noise > threshold * _StippleDensity) ? 1.0 : 0.0;

                return stipple;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);

                // --- Lighting computation ---
                Light mainLight = GetMainLight(input.shadowCoord);
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                float shadow = mainLight.shadowAttenuation;
                float tone = NdotL * shadow + _ToneBias;
                tone = saturate(tone);

                // --- Determine pattern coordinates ---
                float2 patternCoords;
                #if defined(_HALFTONESPACE_OBJECTSPACE)
                    patternCoords = input.uv;
                #elif defined(_HALFTONESPACE_WORLDSPACE)
                    // World-space XZ projection — dots anchored to geometry, VR-stable.
                    // Scale by normal blend so vertical/horizontal surfaces both look good.
                    float3 absN = abs(normalize(input.normalWS));
                    float2 wsXZ = input.positionWS.xz;
                    float2 wsXY = input.positionWS.xy;
                    float2 wsYZ = input.positionWS.yz;
                    patternCoords = wsXZ * absN.y + wsXY * absN.z + wsYZ * absN.x;
                #else
                    // Screen space
                    float2 screenUV = input.screenPos.xy / input.screenPos.w;
                    patternCoords = screenUV * _ScreenParams.xy / _ScreenParams.y;
                #endif

                // --- Compute pattern based on mode ---
                float pattern = 0.0;

                #if defined(_PATTERNMODE_HALFTONE)
                    pattern = HalftonePattern(patternCoords, tone);

                #elif defined(_PATTERNMODE_HATCHING)
                    #if defined(_HATCHSTYLE_DOTS)
                        pattern = HatchDotsPattern(patternCoords, tone);
                    #elif defined(_HATCHSTYLE_COMPOSITION)
                        pattern = HatchCompositionPattern(patternCoords, tone);
                    #else
                        pattern = HatchingPattern(patternCoords, tone);
                    #endif

                #elif defined(_PATTERNMODE_STIPPLE)
                    pattern = StipplePattern(patternCoords, tone);

                #else // COMBINED
                    // Combine: halftone for mid-tones, hatching for shadows
                    float halftonePart = HalftonePattern(patternCoords, tone) *
                        smoothstep(0.0, 0.5, tone) * smoothstep(1.0, 0.5, tone);
                    float hatchPart = HatchingPattern(patternCoords, tone) *
                        (1.0 - smoothstep(0.0, 0.4, tone));
                    pattern = max(halftonePart, hatchPart);
                #endif

                // --- Color + Alpha ---
                float4 baseTex    = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                float3 baseAlbedo = baseTex.rgb * _BaseColor.rgb;
                float  alpha      = baseTex.a   * _BaseColor.a * _Alpha;

                #if defined(_ALPHATEST_ON)
                    clip(alpha - _AlphaCutoff);
                #endif

                // _TextureInfluence blends both paper and ink between flat colours and texture:
                //   0 → pure _PaperColor / _InkColor  (flat comic look)
                //   1 → baseAlbedo as paper, texture-tinted ink  (fully textured)
                float3 paperCol = lerp(_PaperColor.rgb, baseAlbedo, _TextureInfluence);
                float3 inkCol   = lerp(_InkColor.rgb,   baseAlbedo * _InkColor.rgb, _TextureInfluence);

                float3 finalColor = lerp(paperCol, inkCol, pattern);

                return float4(finalColor, alpha);
            }
            ENDHLSL
        }

        // =================================================================
        // PASS 1: Outline (same inverted hull method)
        // =================================================================
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "SRPDefaultUnlit" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vertOutline
            #pragma fragment fragOutline

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _InkColor;
                float4 _PaperColor;
                float  _TextureInfluence;
                float _HalftoneScale;
                float _HalftoneSharpness;
                float _HalftoneAngle;
                float _HatchScale;
                float _HatchAngle;
                float _HatchThickness;
                float _CrossHatchAngle;
                float _StippleScale;
                float _StippleDensity;
                float _ToneLevels;
                float _ToneBias;
                float _DotSize;
                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vertOutline(Attributes input)
            {
                Varyings output;
                float3 posWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                posWS += normalWS * _OutlineWidth;
                output.positionCS = TransformWorldToHClip(posWS);
                return output;
            }

            float4 fragOutline(Varyings input) : SV_Target
            {
                return _OutlineColor;
            }
            ENDHLSL
        }

        // =================================================================
        // PASS 2: Shadow Caster
        // =================================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_instancing
            #pragma multi_compile _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct ShadowAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct ShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            ShadowVaryings ShadowVert(ShadowAttributes input)
            {
                ShadowVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                float3 posWS    = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - posWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif

                float4 posCS = TransformWorldToHClip(ApplyShadowBias(posWS, normalWS, lightDir));
                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE * posCS.w);
                #else
                    posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE * posCS.w);
                #endif
                output.positionCS = posCS;
                return output;
            }

            float4 ShadowFrag(ShadowVaryings input) : SV_Target { return 0; }
            ENDHLSL
        }

        // =================================================================
        // PASS 3: Depth Only
        // =================================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct DepthAttributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct DepthVaryings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            DepthVaryings DepthVert(DepthAttributes input)
            {
                DepthVaryings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            float4 DepthFrag(DepthVaryings input) : SV_Target { return 0; }
            ENDHLSL
        }
    }
    CustomEditor "HalftoneHatchingGUI"
}
