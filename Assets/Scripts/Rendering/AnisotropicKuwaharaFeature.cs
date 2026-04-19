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
        [Range(2, 16)] public int   kernelSize  = 4;
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

        private RTHandle _structureTensorRT;
        private RTHandle _tensorBlurTempRT;
        private RTHandle _tempRT;

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

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (GetMaterial() == null) return;

            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;

            var tensorDesc = desc;
            tensorDesc.colorFormat = RenderTextureFormat.ARGBFloat;

            RenderingUtils.ReAllocateHandleIfNeeded(ref _structureTensorRT, tensorDesc, name: "_AK_TensorRT");
            RenderingUtils.ReAllocateHandleIfNeeded(ref _tensorBlurTempRT,  tensorDesc, name: "_AK_TensorBlurRT");
            RenderingUtils.ReAllocateHandleIfNeeded(ref _tempRT,            desc,       name: "_AK_TempRT");
        }

#pragma warning disable CS0672
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var mat = GetMaterial();
            if (mat == null) return;

            mat.SetInt  (KernelSizeProp,  _s.kernelSize);
            mat.SetInt  (SectorCountProp, _s.sectorCount);
            mat.SetFloat(SharpnessProp,   _s.sharpness);
            mat.SetFloat(HardnessProp,    _s.hardness);

            var cmd = CommandBufferPool.Get("AnisotropicKuwahara");
            var src = renderingData.cameraData.renderer.cameraColorTargetHandle;

            // Pass 0: Compute Structure Tensor
            Blitter.BlitCameraTexture(cmd, src, _structureTensorRT, mat, 0);

            // Pass 1a: Blur tensor horizontally
            _mat.SetVector(BlurDir, new Vector4(1f, 0f, 0f, 0f));
            Blitter.BlitCameraTexture(cmd, _structureTensorRT, _tensorBlurTempRT, mat, 1);

            // Pass 1b: Blur tensor vertically
            _mat.SetVector(BlurDir, new Vector4(0f, 1f, 0f, 0f));
            Blitter.BlitCameraTexture(cmd, _tensorBlurTempRT, _structureTensorRT, mat, 1);

            // Pass 2: Anisotropic Kuwahara
            _mat.SetTexture(StructTensor, _structureTensorRT);
            Blitter.BlitCameraTexture(cmd, src, _tempRT, mat, 2);
            Blitter.BlitCameraTexture(cmd, _tempRT, src);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
#pragma warning restore CS0672

        public override void OnCameraCleanup(CommandBuffer cmd) { }

        public void Dispose()
        {
            _structureTensorRT?.Release();
            _tensorBlurTempRT?.Release();
            _tempRT?.Release();
            CoreUtils.Destroy(_mat);
        }
    }
}
