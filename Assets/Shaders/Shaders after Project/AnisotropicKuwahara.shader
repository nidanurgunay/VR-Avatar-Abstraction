// =============================================================================
// Anisotropic Kuwahara Filter - Unity URP Post-Processing Shader
// =============================================================================
// Based on Kyprianidis et al. "Image and Video Abstraction by Anisotropic
// Kuwahara Filtering" (Pacific Graphics 2009)
//
// Compatible with Blitter.BlitCameraTexture (URP 14+)
// Uses Blit.hlsl: vertex shader + _BlitTexture are provided by URP.
//
// Usage: Assign to KuwaharaFilterFeature.kuwaharaShader in the Renderer Feature.
// =============================================================================

Shader "NPR/AnisotropicKuwahara"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off Cull Off ZTest Always

        // =====================================================================
        // PASS 0: Structure Tensor
        // Sobel on luminance → packs (gx², gx·gy, gy²) into RGB
        // =====================================================================
        Pass
        {
            Name "StructureTensor"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragStructureTensor

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float Luminance3(float3 c)
            {
                return dot(c, float3(0.2126, 0.7152, 0.0722));
            }

            float4 FragStructureTensor(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 d  = _BlitTexture_TexelSize.xy;

                float tl = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x,  d.y))).rgb);
                float  l = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x,  0.0))).rgb);
                float bl = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2(-d.x, -d.y))).rgb);
                float  t = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( 0.0,  d.y))).rgb);
                float  b = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( 0.0, -d.y))).rgb);
                float tr = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x,  d.y))).rgb);
                float  r = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x,  0.0))).rgb);
                float br = Luminance3(SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, saturate(uv + float2( d.x, -d.y))).rgb);

                float gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
                float gy = -tl - 2.0*t - tr + bl + 2.0*b + br;

                return float4(gx*gx, gx*gy, gy*gy, 1.0);
            }
            ENDHLSL
        }

        // =====================================================================
        // PASS 1: Gaussian Blur on Structure Tensor (separable, 5-tap)
        // =====================================================================
        Pass
        {
            Name "TensorBlur"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragTensorBlur

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float4 _BlurDirection;

            float4 FragTensorBlur(Varyings input) : SV_Target
            {
                float2 uv     = input.texcoord;
                float2 offset = _BlurDirection.xy * _BlitTexture_TexelSize.xy;

                float4 result  = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv - 2.0*offset) * 0.0625;
                       result += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv -     offset)  * 0.25;
                       result += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv             )  * 0.375;
                       result += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv +     offset)  * 0.25;
                       result += SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + 2.0*offset)  * 0.0625;
                return result;
            }
            ENDHLSL
        }

        // =====================================================================
        // PASS 2: Anisotropic Kuwahara Filter
        // =====================================================================
        Pass
        {
            Name "KuwaharaFilter"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragKuwahara

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_StructureTensor);
            SAMPLER(sampler_StructureTensor);

            #define MAX_RADIUS 16

            int   _KernelSize;
            int   _SectorCount;
            float _Sharpness;
            float _Hardness;
            float _ZeroCrossing;

            float4 FragKuwahara(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 d  = _BlitTexture_TexelSize.xy;

                // --- Read smoothed structure tensor ---
                float3 tensor = SAMPLE_TEXTURE2D(_StructureTensor, sampler_StructureTensor, uv).rgb;
                float E = tensor.r;
                float F = tensor.g;
                float G = tensor.b;

                // --- Eigenvalue decomposition (paper eq. 1) ---
                float disc    = sqrt(max((E-G)*(E-G) + 4.0*F*F, 0.0));
                float lambda1 = 0.5*(E+G+disc);
                float lambda2 = 0.5*(E+G-disc);

                // Local orientation angle φ
                float angle = 0.5 * atan2(2.0*F, E-G);

                // Anisotropy A = (λ1-λ2)/(λ1+λ2)
                float anisotropy = (lambda1+lambda2 > 0.0)
                    ? (lambda1-lambda2)/(lambda1+lambda2) : 0.0;

                // --- Ellipse axes scaled by anisotropy ---
                int radius = min(_KernelSize, MAX_RADIUS);
                float a = float(radius) * clamp((1.0+anisotropy)*0.5, 0.5, 2.0);
                float b = float(radius) * clamp((1.0-anisotropy)*0.5, 0.25, 1.0);

                float cosA = cos(angle);
                float sinA = sin(angle);

                int N = _SectorCount;
                float sectorAngle = 6.28318530718 / float(N);

                // Per-sector accumulators (fixed 8)
                float4 sectorMean    [8];
                float  sectorWeight  [8];
                float  sectorVariance[8];

                [unroll]
                for (int s = 0; s < 8; s++)
                {
                    sectorMean[s]     = 0;
                    sectorWeight[s]   = 0;
                    sectorVariance[s] = 0;
                }

                // --- Accumulate samples into sectors ---
                [loop]
                for (int j = -MAX_RADIUS; j <= MAX_RADIUS; j++)
                {
                    [loop]
                    for (int i = -MAX_RADIUS; i <= MAX_RADIUS; i++)
                    {
                        if (abs(i) > radius || abs(j) > radius) continue;

                        float2 pos = float2(
                             cosA*float(i) + sinA*float(j),
                            -sinA*float(i) + cosA*float(j)
                        );

                        if ((pos.x*pos.x)/(a*a) + (pos.y*pos.y)/(b*b) > 1.0) continue;

                        float sampleAngle = atan2(pos.y, pos.x) + 3.14159265359;
                        int   sectorIdx   = clamp(int(sampleAngle / sectorAngle), 0, N-1);

                        float dist = length(pos) / float(radius);
                        float w    = exp(-2.0*dist*dist);

                        float2 sampleUV = saturate(uv + float2(float(i), float(j)) * d);
                        float4 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, sampleUV);

                        sectorMean    [sectorIdx] += col * w;
                        sectorWeight  [sectorIdx] += w;
                        sectorVariance[sectorIdx] += dot(col.rgb, col.rgb) * w;
                    }
                }

                // --- Blend sectors weighted by inverse variance (paper eq. αi) ---
                float4 result = 0;
                float  totalW = 0;

                [unroll]
                for (int k = 0; k < 8; k++)
                {
                    if (k >= N) break;
                    if (sectorWeight[k] < 0.001) continue;

                    float4 mean      = sectorMean[k] / sectorWeight[k];
                    float  meanSqLen = sectorVariance[k] / sectorWeight[k];
                    float  variance  = max(meanSqLen - dot(mean.rgb, mean.rgb), 0.0);

                    // αi = 1 / (1 + ||si||^q)  — paper eq.
                    float w = 1.0 / (1.0 + pow(variance * 1000.0, 0.5*_Sharpness));

                    result += mean * w;
                    totalW += w;
                }

                return (totalW > 0.0)
                    ? result / totalW
                    : SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
            }
            ENDHLSL
        }
        // =====================================================================
        // PASS 3: Masked Composite
        // Blends original scene with Kuwahara result using an avatar mask
        // =====================================================================
        Pass
        {
            Name "MaskedComposite"
            ZWrite Off Cull Off ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment FragMaskedComposite

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            TEXTURE2D(_KuwaharaResult);
            TEXTURE2D(_AvatarMask);

            float4 FragMaskedComposite(Varyings input) : SV_Target
            {
                float2 uv      = input.texcoord;
                float4 original = SAMPLE_TEXTURE2D_X(_BlitTexture,    sampler_LinearClamp, uv);
                float4 kuwahara = SAMPLE_TEXTURE2D  (_KuwaharaResult, sampler_LinearClamp, uv);
                float  mask     = SAMPLE_TEXTURE2D  (_AvatarMask,     sampler_LinearClamp, uv).r;
                return lerp(original, kuwahara, mask);
            }
            ENDHLSL
        }
    }
}
