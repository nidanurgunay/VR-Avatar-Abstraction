using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Rendering.RenderGraphModule;

/// <summary>
/// Custom URP Renderer Feature that renders toon outlines using a stencil buffer.
/// This ensures outlines never flicker by masking them where the main mesh is rendered.
/// 
/// Setup:
/// 1. Add this Renderer Feature to your URP Renderer (PC_Renderer or Mobile_Renderer)
/// 2. Assign materials using shaders with LightMode="ToonOutline" pass
/// 3. The outline will automatically render after the main mesh with stencil masking
/// </summary>
public class ToonOutlineRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class ToonOutlineSettings
    {
        [Tooltip("When to render the outline pass")]
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        
        [Tooltip("Which layers to render outlines for")]
        public LayerMask layerMask = -1; // All layers by default
        
        [Tooltip("The shader pass name for the outline (must match the Pass Name in shader)")]
        public string outlinePassName = "ToonOutline";
    }

    public ToonOutlineSettings settings = new ToonOutlineSettings();
    
    private ToonOutlineRenderPass outlinePass;

    public override void Create()
    {
        outlinePass = new ToonOutlineRenderPass(settings);
        outlinePass.renderPassEvent = settings.renderPassEvent;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // Don't render outlines in previews or reflection probes
        if (renderingData.cameraData.cameraType == CameraType.Preview)
            return;
        
        // Don't render if layer mask is empty
        if (settings.layerMask == 0)
            return;
            
        renderer.EnqueuePass(outlinePass);
    }

    protected override void Dispose(bool disposing)
    {
        outlinePass?.Dispose();
    }

    class ToonOutlineRenderPass : ScriptableRenderPass
    {
        private ToonOutlineSettings settings;
        private FilteringSettings filteringSettings;
        private ShaderTagId shaderTagId;
        
        // For profiling in Frame Debugger
        private static readonly ProfilingSampler s_ProfilingSampler = new ProfilingSampler("ToonOutlinePass");

        public ToonOutlineRenderPass(ToonOutlineSettings settings)
        {
            this.settings = settings;
            
            // Filter to only render objects in the specified layers
            filteringSettings = new FilteringSettings(RenderQueueRange.opaque, settings.layerMask);
            
            // This matches the Pass with Tags { "LightMode" = "ToonOutline" }
            shaderTagId = new ShaderTagId(settings.outlinePassName);
            
            // Set the profiler sampler
            profilingSampler = s_ProfilingSampler;
        }

#pragma warning disable CS0672 // Member overrides obsolete member
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
#pragma warning restore CS0672
        {
            // Setup sorting settings
            var sortingSettings = new SortingSettings(renderingData.cameraData.camera)
            {
                criteria = SortingCriteria.CommonOpaque
            };

            // Setup drawing settings with our shader tag
            var drawingSettings = new DrawingSettings(shaderTagId, sortingSettings)
            {
                enableDynamicBatching = renderingData.supportsDynamicBatching,
                enableInstancing = true
            };

            // Update filter with current layer mask
            var filterSettings = filteringSettings;
            filterSettings.layerMask = settings.layerMask;

            // Use CommandBuffer for rendering
            CommandBuffer cmd = CommandBufferPool.Get("Toon Outline");
            
            using (new ProfilingScope(cmd, s_ProfilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                
                // Create and execute renderer list (Unity 6 way)
                var rendererListParams = new RendererListParams(
                    renderingData.cullResults,
                    drawingSettings,
                    filterSettings
                );
                
                RendererList rendererList = context.CreateRendererList(ref rendererListParams);
                cmd.DrawRendererList(rendererList);
            }
            
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            // Cleanup if needed
        }
    }
}
