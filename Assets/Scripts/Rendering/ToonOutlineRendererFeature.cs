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
            
            // CRITICAL: Request depth and stencil attachments for this pass
            ConfigureInput(ScriptableRenderPassInput.Depth);
        }

        // Unity 6 Render Graph path (new API)
        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            var resourceData = frameData.Get<UniversalResourceData>();
            var renderingData = frameData.Get<UniversalRenderingData>();
            var cameraData = frameData.Get<UniversalCameraData>();
            
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("Toon Outline Pass", out var passData, s_ProfilingSampler))
            {
                // Setup pass data
                passData.shaderTagId = shaderTagId;
                passData.filteringSettings = filteringSettings;
                passData.settings = settings;
                passData.defaultSortingSettings = new SortingSettings(cameraData.camera)
                {
                    criteria = SortingCriteria.CommonOpaque
                };
                
                // Set render targets - use the current color and depth
                builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
                builder.SetRenderAttachmentDepth(resourceData.activeDepthTexture, AccessFlags.ReadWrite);
                
                // Enable depth/stencil testing
                builder.AllowPassCulling(false);
                
                // Create renderer list for the outline pass
                var drawingSettings = new DrawingSettings(shaderTagId, passData.defaultSortingSettings)
                {
                    enableDynamicBatching = true,
                    enableInstancing = true
                };
                
                var filterSettings = filteringSettings;
                filterSettings.layerMask = settings.layerMask;
                
                var rendererListParams = new RendererListParams(renderingData.cullResults, drawingSettings, filterSettings);
                passData.rendererListHandle = renderGraph.CreateRendererList(rendererListParams);
                builder.UseRendererList(passData.rendererListHandle);
                
                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    context.cmd.DrawRendererList(data.rendererListHandle);
                });
            }
        }
        
        private class PassData
        {
            public ShaderTagId shaderTagId;
            public FilteringSettings filteringSettings;
            public ToonOutlineSettings settings;
            public SortingSettings defaultSortingSettings;
            public RendererListHandle rendererListHandle;
        }

        // Legacy Execute path (for compatibility mode)
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
