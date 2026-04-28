// =============================================================================
// NPR Post-Process Renderer Features for Unity URP
// =============================================================================
// Drop-in Renderer Features for the Anisotropic Kuwahara filter and
// Hierarchical Edge Detection post-process shaders.
//
// Setup:
// 1. Add these scripts to your project (e.g., Assets/Scripts/Rendering/)
// 2. Add the shader files to your project (e.g., Assets/Shaders/)
// 3. In your URP Renderer Data asset, click "Add Renderer Feature"
// 4. Select "Kuwahara Filter Feature" or "Edge Detection Feature"
// 5. Assign the corresponding shader in the feature's inspector
// 6. Adjust parameters to taste
//
// Note: Edge Detection requires Depth Texture and Opaque Texture enabled
//       in your URP Pipeline Asset settings.
// =============================================================================

// Suppress obsolete warnings from URP 17 compatibility-mode API
// (Execute/OnCameraSetup still work; Render Graph migration is optional)
#pragma warning disable CS0672, CS0618

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// =============================================================================
// KUWAHARA FILTER RENDERER FEATURE
// =============================================================================
public class KuwaharaFilterFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Shader kuwaharaShader;

        [Header("Filter Settings")]
        [Range(2, 16)] public int kernelSize = 4;
        [Range(4, 8)]  public int sectorCount = 8;
        [Range(1, 18)] public float sharpness = 8f;
        [Range(1, 18)] public float hardness = 8f;
        [Range(0.3f, 0.8f)] public float zeroCrossing = 0.58f;

        [Header("Avatar Masking")]
        [Tooltip("Set to the layer your avatar is on. Leave Nothing for full-screen effect.")]
        public LayerMask avatarLayer = 0;
    }

    public Settings settings = new Settings();
    KuwaharaPass m_Pass;

    public override void Create()
    {
        m_Pass = new KuwaharaPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.kuwaharaShader == null) return;
        renderer.EnqueuePass(m_Pass);
    }

    class KuwaharaPass : ScriptableRenderPass
    {
        Settings m_Settings;
        Material m_Material;
        Material m_MaskMaterial;
        bool m_LoggedUnsupportedShader;
        bool m_LoggedExecute;

        RTHandle m_StructureTensorRT;
        RTHandle m_TensorBlurTempRT;
        RTHandle m_TempRT;
        RTHandle m_AvatarMaskRT;
        RTHandle m_OutputRT;

        static readonly int _BlurDirection   = Shader.PropertyToID("_BlurDirection");
        static readonly int _StructureTensor = Shader.PropertyToID("_StructureTensor");
        static readonly int _KernelSize      = Shader.PropertyToID("_KernelSize");
        static readonly int _SectorCount     = Shader.PropertyToID("_SectorCount");
        static readonly int _Sharpness       = Shader.PropertyToID("_Sharpness");
        static readonly int _Hardness        = Shader.PropertyToID("_Hardness");
        static readonly int _ZeroCrossing    = Shader.PropertyToID("_ZeroCrossing");
        static readonly int _KuwaharaResult  = Shader.PropertyToID("_KuwaharaResult");
        static readonly int _AvatarMask      = Shader.PropertyToID("_AvatarMask");

        public KuwaharaPass(Settings settings)
        {
            m_Settings = settings;
            renderPassEvent = settings.renderPassEvent;

            // This pass samples the camera color; force an intermediate texture so it works in XR/backbuffer paths.
            // Note: This can be expensive on standalone VR.
            requiresIntermediateTexture = true;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (m_Material == null && m_Settings.kuwaharaShader != null)
            {
                if (!m_Settings.kuwaharaShader.isSupported)
                {
                    if (!m_LoggedUnsupportedShader)
                    {
                        Debug.LogError($"KuwaharaFilterFeature: shader '{m_Settings.kuwaharaShader.name}' is not supported on this platform/GPU; disabling the renderer feature.");
                        m_LoggedUnsupportedShader = true;
                    }
                    return;
                }

                m_Material = CoreUtils.CreateEngineMaterial(m_Settings.kuwaharaShader);
                if (m_Material == null && !m_LoggedUnsupportedShader)
                {
                    Debug.LogError($"KuwaharaFilterFeature: failed to create material for shader '{m_Settings.kuwaharaShader.name}'; disabling the renderer feature.");
                    m_LoggedUnsupportedShader = true;
                    return;
                }
            }

            if (m_MaskMaterial == null)
            {
                var maskShader = Shader.Find("Hidden/AvatarMaskCapture");
                if (maskShader != null)
                    m_MaskMaterial = CoreUtils.CreateEngineMaterial(maskShader);
            }

            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;

            var tensorDesc = desc;
            tensorDesc.colorFormat = RenderTextureFormat.ARGBHalf;

            RenderingUtils.ReAllocateHandleIfNeeded(ref m_StructureTensorRT, tensorDesc, name: "_StructureTensor");
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_TensorBlurTempRT,  tensorDesc, name: "_TensorBlurTemp");
            RenderingUtils.ReAllocateHandleIfNeeded(ref m_TempRT,            desc,       name: "_KuwaharaTemp");

            if (m_Settings.avatarLayer != 0)
            {
                var maskDesc = desc;
                maskDesc.colorFormat = RenderTextureFormat.ARGB32;
                RenderingUtils.ReAllocateHandleIfNeeded(ref m_AvatarMaskRT, maskDesc, name: "_AvatarMaskRT");
                RenderingUtils.ReAllocateHandleIfNeeded(ref m_OutputRT,     desc,     name: "_KuwaharaOutputRT");
            }

        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (m_Material == null) return;

            var source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            if (source == null) return;

            bool useMask = m_Settings.avatarLayer != 0 && m_MaskMaterial != null
                           && m_AvatarMaskRT != null && m_OutputRT != null;

            if (!m_LoggedExecute)
            {
                Debug.Log($"KuwaharaFilterFeature: executing (shader='{m_Settings.kuwaharaShader?.name}', useMask={useMask}, avatarLayer={m_Settings.avatarLayer.value}, kernelSize={m_Settings.kernelSize}, passEvent={renderPassEvent}).");
                m_LoggedExecute = true;
            }

            // ---- Step 1: Render avatar silhouette to mask ----
            if (useMask)
            {
                var maskCmd = CommandBufferPool.Get("AvatarMask");
                maskCmd.SetRenderTarget(m_AvatarMaskRT,
                    renderingData.cameraData.renderer.cameraDepthTargetHandle);
                maskCmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(maskCmd);
                CommandBufferPool.Release(maskCmd);

                var sortSettings = new SortingSettings(renderingData.cameraData.camera)
                    { criteria = SortingCriteria.CommonOpaque };
                var drawSettings = new DrawingSettings(
                    new ShaderTagId("UniversalForward"), sortSettings)
                {
                    overrideMaterial = m_MaskMaterial,
                    overrideMaterialPassIndex = 0
                };
                drawSettings.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
                drawSettings.SetShaderPassName(2, new ShaderTagId("SRPDefaultUnlit"));
                var filterSettings = new FilteringSettings(
                    RenderQueueRange.opaque, m_Settings.avatarLayer);
                context.DrawRenderers(
                    renderingData.cullResults, ref drawSettings, ref filterSettings);
            }

            var cmd = CommandBufferPool.Get("Kuwahara Filter");

            // ---- Step 2: Kuwahara computation ----
            m_Material.SetInt  (_KernelSize,    m_Settings.kernelSize);
            m_Material.SetInt  (_SectorCount,   m_Settings.sectorCount);
            m_Material.SetFloat(_Sharpness,     m_Settings.sharpness);
            m_Material.SetFloat(_Hardness,      m_Settings.hardness);
            m_Material.SetFloat(_ZeroCrossing,  m_Settings.zeroCrossing);

            Blitter.BlitCameraTexture(cmd, source, m_StructureTensorRT, m_Material, 0);

            cmd.SetGlobalVector(_BlurDirection, new Vector4(1, 0, 0, 0));
            Blitter.BlitCameraTexture(cmd, m_StructureTensorRT, m_TensorBlurTempRT, m_Material, 1);

            cmd.SetGlobalVector(_BlurDirection, new Vector4(0, 1, 0, 0));
            Blitter.BlitCameraTexture(cmd, m_TensorBlurTempRT, m_StructureTensorRT, m_Material, 1);

            cmd.SetGlobalTexture(_StructureTensor, m_StructureTensorRT);
            Blitter.BlitCameraTexture(cmd, source, m_TempRT, m_Material, 2);

            // ---- Step 4: Composite (masked or full-screen) ----
            if (useMask)
            {
                m_Material.SetTexture(_KuwaharaResult, m_TempRT);
                m_Material.SetTexture(_AvatarMask,     m_AvatarMaskRT);
                Blitter.BlitCameraTexture(cmd, source,     m_OutputRT, m_Material, 3);
                Blitter.BlitCameraTexture(cmd, m_OutputRT, source);
            }
            else
            {
                Blitter.BlitCameraTexture(cmd, m_TempRT, source);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void Dispose()
        {
            m_StructureTensorRT?.Release();
            m_TensorBlurTempRT?.Release();
            m_TempRT?.Release();
            m_AvatarMaskRT?.Release();
            m_OutputRT?.Release();
            CoreUtils.Destroy(m_Material);
            CoreUtils.Destroy(m_MaskMaterial);
        }
    }

    protected override void Dispose(bool disposing)
    {
        m_Pass?.Dispose();
    }
}
