// Texture-based Edge Detection for Toon Shaders
// Detects edges in texture detail (like lip lines, eye details, etc.)
// Use this as a Custom Function in Shader Graph

void TextureEdgeDetection_float(
    Texture2D MainTex, 
    SamplerState MainTexSampler, 
    float2 UV, 
    float Threshold, 
    float SampleDistance,
    out float Edge)
{
    // Convert sample distance to UV offset
    float offset = SampleDistance * 0.001;
    
    // Sample center pixel
    float3 centerSample = MainTex.Sample(MainTexSampler, UV).rgb;
    float center = dot(centerSample, float3(0.299, 0.587, 0.114)); // Convert to luminance
    
    // Sample 4 cardinal directions (N, S, E, W)
    float n = dot(MainTex.Sample(MainTexSampler, UV + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
    float s = dot(MainTex.Sample(MainTexSampler, UV + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float e = dot(MainTex.Sample(MainTexSampler, UV + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float w = dot(MainTex.Sample(MainTexSampler, UV + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    
    // Find maximum absolute difference from center
    float maxDiff = 0.0;
    maxDiff = max(maxDiff, abs(center - n));
    maxDiff = max(maxDiff, abs(center - s));
    maxDiff = max(maxDiff, abs(center - e));
    maxDiff = max(maxDiff, abs(center - w));
    
    // Apply threshold - returns 1.0 where edges detected, 0.0 otherwise
    Edge = (maxDiff > Threshold) ? 1.0 : 0.0;
}

// Alternative version with smoother edges
void TextureEdgeDetectionSmooth_float(
    Texture2D MainTex, 
    SamplerState MainTexSampler, 
    float2 UV, 
    float Threshold, 
    float SampleDistance,
    float Smoothness,
    out float Edge)
{
    float offset = SampleDistance * 0.001;
    
    float3 centerSample = MainTex.Sample(MainTexSampler, UV).rgb;
    float center = dot(centerSample, float3(0.299, 0.587, 0.114));
    
    float n = dot(MainTex.Sample(MainTexSampler, UV + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
    float s = dot(MainTex.Sample(MainTexSampler, UV + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float e = dot(MainTex.Sample(MainTexSampler, UV + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float w = dot(MainTex.Sample(MainTexSampler, UV + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    
    float maxDiff = 0.0;
    maxDiff = max(maxDiff, abs(center - n));
    maxDiff = max(maxDiff, abs(center - s));
    maxDiff = max(maxDiff, abs(center - e));
    maxDiff = max(maxDiff, abs(center - w));
    
    // Smooth threshold instead of hard cutoff
    Edge = smoothstep(Threshold - Smoothness, Threshold + Smoothness, maxDiff);
}

// 8-directional sampling for more accurate edge detection
void TextureEdgeDetection8Dir_float(
    Texture2D MainTex, 
    SamplerState MainTexSampler, 
    float2 UV, 
    float Threshold, 
    float SampleDistance,
    out float Edge)
{
    float offset = SampleDistance * 0.001;
    
    float3 centerSample = MainTex.Sample(MainTexSampler, UV).rgb;
    float center = dot(centerSample, float3(0.299, 0.587, 0.114));
    
    // Sample 8 directions
    float n  = dot(MainTex.Sample(MainTexSampler, UV + float2(0, offset)).rgb, float3(0.299, 0.587, 0.114));
    float s  = dot(MainTex.Sample(MainTexSampler, UV + float2(0, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float e  = dot(MainTex.Sample(MainTexSampler, UV + float2(offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float w  = dot(MainTex.Sample(MainTexSampler, UV + float2(-offset, 0)).rgb, float3(0.299, 0.587, 0.114));
    float ne = dot(MainTex.Sample(MainTexSampler, UV + float2(offset, offset)).rgb, float3(0.299, 0.587, 0.114));
    float nw = dot(MainTex.Sample(MainTexSampler, UV + float2(-offset, offset)).rgb, float3(0.299, 0.587, 0.114));
    float se = dot(MainTex.Sample(MainTexSampler, UV + float2(offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    float sw = dot(MainTex.Sample(MainTexSampler, UV + float2(-offset, -offset)).rgb, float3(0.299, 0.587, 0.114));
    
    // Find maximum difference
    float maxDiff = 0.0;
    maxDiff = max(maxDiff, abs(center - n));
    maxDiff = max(maxDiff, abs(center - s));
    maxDiff = max(maxDiff, abs(center - e));
    maxDiff = max(maxDiff, abs(center - w));
    maxDiff = max(maxDiff, abs(center - ne));
    maxDiff = max(maxDiff, abs(center - nw));
    maxDiff = max(maxDiff, abs(center - se));
    maxDiff = max(maxDiff, abs(center - sw));
    
    Edge = (maxDiff > Threshold) ? 1.0 : 0.0;
}
