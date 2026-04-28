// =============================================================================
// Edge Detection Renderer Feature for Unity URP
// =============================================================================
// Screen-space hierarchical edge detection post-process.
//
// Note: Requires URP depth + normals (requested via ConfigureInput).
// =============================================================================

// Suppress obsolete warnings from URP 17 compatibility-mode API
// (Execute/OnCameraSetup still work; Render Graph migration is optional)
#pragma warning disable CS0672, CS0618

using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class EdgeDetectionFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public Shader edgeShader;

        [Header("Edge Colors")]
        public Color edgeColor = Color.black;

        [Header("Layer Thresholds")]
        [Tooltip("World-space depth jump in metres that counts as an edge.")]
        [Range(0.01f, 5f)] public float depthThreshold = 0.5f;
        [Range(0.05f, 5f)] public float normalThreshold = 0.4f;
        [Range(0.01f, 1f)] public float colorThreshold = 0.15f;

        [Header("Layer Weights")]
        [Range(0, 1)] public float depthWeight = 1f;
        [Range(0, 1)] public float normalWeight = 1f;
        [Range(0, 1)] public float colorWeight = 0.5f;

        [Header("Style")]
        [Range(0.5f, 4f)] public float edgeWidth = 1f;
        [Range(0, 1)] public float adaptiveStrength = 0.5f;

        [Header("Avatar Masking")]
        [Tooltip("Set to the layer your avatar is on. Leave Nothing for full-screen edges.")]
        public LayerMask avatarLayer = 0;
    }

    public Settings settings = new Settings();
    private EdgeDetectionPass _pass;

    public override void Create()
    {
        _pass = new EdgeDetectionPass(settings);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (settings.edgeShader == null)
            return;

        renderer.EnqueuePass(_pass);
    }

    private class EdgeDetectionPass : ScriptableRenderPass
    {
        private readonly Settings _settings;
        private Material _material;
        private Material _maskMaterial;
        private RTHandle _tempRT;
        private RTHandle _avatarMaskRT;
        private bool _loggedUnsupportedShader;
        private bool _loggedExecute;

        private static readonly int AvatarMask = Shader.PropertyToID("_AvatarMask");
        private static readonly int UseMask = Shader.PropertyToID("_UseMask");

        public EdgeDetectionPass(Settings settings)
        {
            _settings = settings;
            renderPassEvent = settings.renderPassEvent;

            // This pass samples the camera color; force an intermediate texture so it works in XR/backbuffer paths.
            // Note: This can be expensive on standalone VR.
            requiresIntermediateTexture = true;

            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            if (_material == null && _settings.edgeShader != null)
            {
                if (!_settings.edgeShader.isSupported)
                {
                    if (!_loggedUnsupportedShader)
                    {
                        Debug.LogError($"EdgeDetectionFeature: shader '{_settings.edgeShader.name}' is not supported on this platform/GPU; disabling the renderer feature.");
                        _loggedUnsupportedShader = true;
                    }
                    return;
                }

                _material = CoreUtils.CreateEngineMaterial(_settings.edgeShader);
                if (_material == null && !_loggedUnsupportedShader)
                {
                    Debug.LogError($"EdgeDetectionFeature: failed to create material for shader '{_settings.edgeShader.name}'; disabling the renderer feature.");
                    _loggedUnsupportedShader = true;
                    return;
                }
            }

            if (_maskMaterial == null)
            {
                var maskShader = Shader.Find("Hidden/AvatarMaskCapture");
                if (maskShader != null)
                    _maskMaterial = CoreUtils.CreateEngineMaterial(maskShader);
            }

            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.depthBufferBits = 0;
            desc.msaaSamples = 1;
            RenderingUtils.ReAllocateHandleIfNeeded(ref _tempRT, desc, name: "_EdgeTemp");

            if (_settings.avatarLayer != 0)
            {
                var maskDesc = desc;
                maskDesc.colorFormat = RenderTextureFormat.ARGB32;
                RenderingUtils.ReAllocateHandleIfNeeded(ref _avatarMaskRT, maskDesc, name: "_EdgeAvatarMaskRT");
            }
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (_material == null)
                return;

            bool useMask = _settings.avatarLayer != 0 && _maskMaterial != null && _avatarMaskRT != null;

            if (!_loggedExecute)
            {
                Debug.Log($"EdgeDetectionFeature: executing (shader='{_settings.edgeShader?.name}', useMask={useMask}, avatarLayer={_settings.avatarLayer.value}, passEvent={renderPassEvent}).");
                _loggedExecute = true;
            }

            if (useMask)
            {
                var maskCmd = CommandBufferPool.Get("EdgeDetection_AvatarMask");
                maskCmd.SetRenderTarget(_avatarMaskRT, renderingData.cameraData.renderer.cameraDepthTargetHandle);
                maskCmd.ClearRenderTarget(false, true, Color.black);
                context.ExecuteCommandBuffer(maskCmd);
                CommandBufferPool.Release(maskCmd);

                var sortSettings = new SortingSettings(renderingData.cameraData.camera) { criteria = SortingCriteria.CommonOpaque };
                var drawSettings = new DrawingSettings(new ShaderTagId("UniversalForward"), sortSettings)
                {
                    overrideMaterial = _maskMaterial,
                    overrideMaterialPassIndex = 0
                };
                drawSettings.SetShaderPassName(1, new ShaderTagId("UniversalForwardOnly"));
                drawSettings.SetShaderPassName(2, new ShaderTagId("SRPDefaultUnlit"));

                var filterSettings = new FilteringSettings(RenderQueueRange.opaque, _settings.avatarLayer);
                context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref filterSettings);
            }

            var cmd = CommandBufferPool.Get("Edge Detection");

            _material.SetFloat("_DepthThreshold", _settings.depthThreshold);
            _material.SetFloat("_NormalThreshold", _settings.normalThreshold);
            _material.SetFloat("_ColorThreshold", _settings.colorThreshold);
            _material.SetFloat("_DepthWeight", _settings.depthWeight);
            _material.SetFloat("_NormalWeight", _settings.normalWeight);
            _material.SetFloat("_ColorWeight", _settings.colorWeight);
            _material.SetColor("_EdgeColor", _settings.edgeColor);
            _material.SetFloat("_EdgeWidth", _settings.edgeWidth);
            _material.SetFloat("_AdaptiveStrength", _settings.adaptiveStrength);

            if (useMask)
            {
                _material.SetTexture(AvatarMask, _avatarMaskRT);
                _material.SetFloat(UseMask, 1f);
            }
            else
            {
                _material.SetFloat(UseMask, 0f);
            }

            var source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            if (source == null)
            {
                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
                return;
            }

            Blitter.BlitCameraTexture(cmd, source, _tempRT, _material, 0);
            Blitter.BlitCameraTexture(cmd, _tempRT, source);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public void Dispose()
        {
            _tempRT?.Release();
            _avatarMaskRT?.Release();
            CoreUtils.Destroy(_material);
            CoreUtils.Destroy(_maskMaterial);
        }
    }

    protected override void Dispose(bool disposing)
    {
        _pass?.Dispose();
    }
}
