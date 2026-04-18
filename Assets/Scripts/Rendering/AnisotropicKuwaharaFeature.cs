// =============================================================================
// Anisotropic Kuwahara - URP 17 (Unity 6) Renderer Feature
// =============================================================================
// Based on: Kyprianidis et al. "Image and Video Abstraction by Anisotropic
// Kuwahara Filtering" (Pacific Graphics 2009)
//
// 3-pass pipeline:
//   Pass 0 : Structure Tensor  (Sobel → E,F,G packed in RGB)
//   Pass 1 : Gaussian Blur     (separable H+V, smooths tensor field)
//   Pass 2 : Kuwahara Filter   (anisotropic oil-paint per pixel)
//
// Setup: Select PC_Renderer.asset → Add Renderer Feature → Anisotropic Kuwahara
// =============================================================================

#pragma warning disable CS0672, CS0618

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AnisotropicKuwaharaFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;

        [Header("Filter")]
        [Range(2, 8)]  public int   kernelSize  = 4;
        [Range(4, 8)]  public int   sectorCount = 8;

        [Header("Paper Parameters (Kyprianidis 2009)")]
        [Tooltip("Sharpness of sector selection. Paper uses q=8.")]
        [Range(2, 18)] public float sharpness   = 8f;
        [Tooltip("Gaussian weight falloff inside kernel.")]
        [Range(2, 18)] public float hardness    = 8f;
    }

    public Settings settings = new Settings();
    private KuwaharaPass _pass;

    public override void Create()
    {
        _pass = new KuwaharaPass(settings)
        {
            renderPassEvent = settings.renderPassEvent
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        var cameraType = renderingData.cameraData.cameraType;
        if (cameraType == CameraType.Preview || cameraType == CameraType.Reflection)
            return;

        renderer.EnqueuePass(_pass);
    }

    protected override void Dispose(bool disposing)
    {
        _pass?.Dispose();
    }

    // -------------------------------------------------------------------------

    class KuwaharaPass : ScriptableRenderPass
    {
        private readonly Settings _s;
        private Material _mat;

        private static readonly ProfilingSampler s_Sampler =
            new ProfilingSampler("AnisotropicKuwahara");

        // Shader property IDs
        private static readonly int BlurDir         = Shader.PropertyToID("_BlurDirection");
        private static readonly int StructTensor     = Shader.PropertyToID("_StructureTensor");
        private static readonly int KernelSizeProp   = Shader.PropertyToID("_KernelSize");
        private static readonly int SectorCountProp  = Shader.PropertyToID("_SectorCount");
        private static readonly int SharpnessProp    = Shader.PropertyToID("_Sharpness");
        private static readonly int HardnessProp     = Shader.PropertyToID("_Hardness");

        public KuwaharaPass(Settings s)
        {
            _s = s;
            profilingSampler = s_Sampler;
        }

        Material GetMaterial()
        {
            if (_mat != null) return _mat;
            var shader = Shader.Find("NPR/AnisotropicKuwahara");
            if (shader == null)
            {
                Debug.LogError("[AnisotropicKuwahara] Shader 'NPR/AnisotropicKuwahara' not found.");
                return null;
            }
            _mat = new Material(shader) { hideFlags = HideFlags.HideAndDontSave };
            return _mat;
        }

        // Execute path — RecordRenderGraph intentionally omitted so Unity falls back here.
        // Blitter.BlitCameraTexture with TextureHandle inside AddUnsafePass
        // does not correctly resolve RTHandles in URP 17, causing black output.
#pragma warning disable CS0672
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var mat = GetMaterial();
            if (mat == null) return;

            mat.SetInt  (KernelSizeProp,  _s.kernelSize);
            mat.SetInt  (SectorCountProp, _s.sectorCount);
            mat.SetFloat(SharpnessProp,   _s.sharpness);
            mat.SetFloat(HardnessProp,    _s.hardness);

            var cmd  = CommandBufferPool.Get("AnisotropicKuwahara");
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;

            int tensorId     = Shader.PropertyToID("_AK_TensorRT");
            int tensorBlurId = Shader.PropertyToID("_AK_TensorBlurRT");
            int tempId       = Shader.PropertyToID("_AK_TempRT");

            cmd.GetTemporaryRT(tensorId,     desc);
            cmd.GetTemporaryRT(tensorBlurId, desc);
            cmd.GetTemporaryRT(tempId,       desc);

            var src = renderingData.cameraData.renderer.cameraColorTargetHandle;

            cmd.Blit(src, tensorId, mat, 0);

            cmd.SetGlobalVector(BlurDir, new Vector2(1f, 0f));
            cmd.Blit(tensorId, tempId, mat, 1);

            cmd.SetGlobalVector(BlurDir, new Vector2(0f, 1f));
            cmd.Blit(tempId, tensorBlurId, mat, 1);

            cmd.SetGlobalTexture(StructTensor, new RenderTargetIdentifier(tensorBlurId));
            cmd.Blit(src, tempId, mat, 2);
            cmd.Blit(tempId, src);

            cmd.ReleaseTemporaryRT(tensorId);
            cmd.ReleaseTemporaryRT(tensorBlurId);
            cmd.ReleaseTemporaryRT(tempId);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
#pragma warning restore CS0672

        public void Dispose()
        {
            if (_mat != null)
                CoreUtils.Destroy(_mat);
        }
    }
}
