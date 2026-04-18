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

        [Header(Pattern Mode)]
        [KeywordEnum(Halftone, Hatching, Stipple, Combined)]
        _PatternMode ("Pattern Mode", Float) = 0

        [Header(Halftone)]
        _HalftoneScale ("Dot Scale", Range(2, 100)) = 30.0
        _HalftoneSharpness ("Dot Sharpness", Range(1, 50)) = 10.0
        [KeywordEnum(ScreenSpace, ObjectSpace)]
        _HalftoneSpace ("Coordinate Space", Float) = 0
        _HalftoneAngle ("Dot Grid Angle", Range(0, 90)) = 45.0

        [Header(Hatching)]
        _HatchScale ("Hatch Scale", Range(1, 100)) = 20.0
        _HatchAngle ("Primary Hatch Angle", Range(0, 180)) = 45.0
        _HatchThickness ("Line Thickness", Range(0.01, 0.5)) = 0.15
        _CrossHatchAngle ("Cross Hatch Angle", Range(0, 180)) = 135.0

        [Header(Stipple)]
        _StippleScale ("Stipple Scale", Range(5, 200)) = 50.0
        _StippleDensity ("Stipple Density", Range(0, 2)) = 1.0

        [Header(Lighting Response)]
        _ToneLevels ("Tone Levels (pattern density steps)", Range(2, 8)) = 5
        _ShadowBias ("Shadow Bias", Range(-0.5, 0.5)) = 0.0

        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0, 0, 0, 1)
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.002
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
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma shader_feature_local _PATTERNMODE_HALFTONE _PATTERNMODE_HATCHING _PATTERNMODE_STIPPLE _PATTERNMODE_COMBINED
            #pragma shader_feature_local _HALFTONESPACE_SCREENSPACE _HALFTONESPACE_OBJECTSPACE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);    SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float4 _InkColor;
                float4 _PaperColor;
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
                float _ShadowBias;
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
                float line = smoothstep(thickness, thickness + 0.02, abs(linePos - 0.5));
                return 1.0 - line; // 1 = ink, 0 = paper
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
                float tone = NdotL * shadow + _ShadowBias;
                tone = saturate(tone);

                // --- Determine pattern coordinates ---
                float2 patternCoords;
                #if defined(_HALFTONESPACE_OBJECTSPACE)
                    patternCoords = input.uv;
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
                    pattern = HatchingPattern(patternCoords, tone);

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

                // --- Color: interpolate between paper and ink based on pattern ---
                float3 baseAlbedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).rgb
                    * _BaseColor.rgb;

                // Option A: Pure ink-on-paper (classic manga/comic)
                float3 inkPaper = lerp(_PaperColor.rgb, _InkColor.rgb, pattern);

                // Tint with base color for colored hatching
                float3 finalColor = lerp(
                    inkPaper,
                    baseAlbedo * inkPaper,
                    0.5 // Blend factor: 0 = pure ink/paper, 1 = fully colored
                );

                return float4(finalColor, 1.0);
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

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
    }
}
