using UnityEngine;
using UnityEngine.UI;

public class V7ShaderController : MonoBehaviour
{
    [Header("Target")]
    public Renderer[] avatarRenderers;

    [Header("Toggle Controls")]
    public Toggle debugDefaultsToggle;
    public Toggle enableTextureSobelToggle;
    public Toggle enableNormalEdgesToggle;
    public Toggle enableFresnelEdgeToggle;
    public Toggle enableAlphaTestToggle;
    public Toggle useDepthOffsetToggle;

    [Header("Sobel Filter Mode (0=None, 1=Light, 2=Moderate, 3=Aggressive)")]
    public Slider sobelFilterModeSlider;

    [Header("Slider Controls - Basic")]
    public Slider outerOutlineSlider;
    public Slider alphaCutoffSlider;

    [Header("Slider Controls - Texture Sobel")]
    public Slider sobelThresholdSlider;
    public Slider sobelSampleDistanceSlider;
    public Slider sobelStrengthSlider;

    [Header("Slider Controls - Normal Edges")]
    public Slider normalEdgeThresholdSlider;
    public Slider normalEdgeStrengthSlider;
    public Slider normalEdgeSmoothnessSlider;

    [Header("Slider Controls - Fresnel")]
    public Slider fresnelEdgeThresholdSlider;
    public Slider fresnelEdgeStrengthSlider;

    Material[] runtimeMats;

    void Start()
    {
        InitializeMaterials();
        SetupToggleListeners();
        SetupSliderListeners();
        SetSliderRanges();
    }

    void InitializeMaterials()
    {
        if (avatarRenderers == null || avatarRenderers.Length == 0)
        {
            avatarRenderers = GetComponentsInChildren<Renderer>();
        }

        System.Collections.Generic.List<Material> allMats = new System.Collections.Generic.List<Material>();
        foreach (Renderer rend in avatarRenderers)
        {
            foreach (Material mat in rend.materials)
            {
                allMats.Add(mat);
            }
        }

        runtimeMats = new Material[allMats.Count];
        for (int i = 0; i < allMats.Count; i++)
        {
            runtimeMats[i] = Instantiate(allMats[i]);
        }

        int matIndex = 0;
        foreach (Renderer rend in avatarRenderers)
        {
            Material[] newMats = new Material[rend.materials.Length];
            for (int j = 0; j < rend.materials.Length; j++)
            {
                newMats[j] = runtimeMats[matIndex++];
            }
            rend.materials = newMats;
        }
    }

    void SetupToggleListeners()
    {
        if (debugDefaultsToggle != null)
            debugDefaultsToggle.onValueChanged.AddListener(SetDebugDefaults);

        if (enableTextureSobelToggle != null)
            enableTextureSobelToggle.onValueChanged.AddListener(SetEnableTextureSobel);

        if (enableNormalEdgesToggle != null)
            enableNormalEdgesToggle.onValueChanged.AddListener(SetEnableNormalEdges);

        if (enableFresnelEdgeToggle != null)
            enableFresnelEdgeToggle.onValueChanged.AddListener(SetEnableFresnelEdge);

        if (enableAlphaTestToggle != null)
            enableAlphaTestToggle.onValueChanged.AddListener(SetEnableAlphaTest);

        if (useDepthOffsetToggle != null)
            useDepthOffsetToggle.onValueChanged.AddListener(SetUseDepthOffset);
    }

    void SetupSliderListeners()
    {
        if (sobelFilterModeSlider != null)
            sobelFilterModeSlider.onValueChanged.AddListener(SetSobelFilterMode);

        if (outerOutlineSlider != null)
            outerOutlineSlider.onValueChanged.AddListener(SetOutlineWidth);

        if (alphaCutoffSlider != null)
            alphaCutoffSlider.onValueChanged.AddListener(SetAlphaCutoff);

        if (sobelThresholdSlider != null)
            sobelThresholdSlider.onValueChanged.AddListener(SetSobelThreshold);

        if (sobelSampleDistanceSlider != null)
            sobelSampleDistanceSlider.onValueChanged.AddListener(SetSobelSampleDistance);

        if (sobelStrengthSlider != null)
            sobelStrengthSlider.onValueChanged.AddListener(SetSobelStrength);

        if (normalEdgeThresholdSlider != null)
            normalEdgeThresholdSlider.onValueChanged.AddListener(SetNormalEdgeThreshold);

        if (normalEdgeStrengthSlider != null)
            normalEdgeStrengthSlider.onValueChanged.AddListener(SetNormalEdgeStrength);

        if (normalEdgeSmoothnessSlider != null)
            normalEdgeSmoothnessSlider.onValueChanged.AddListener(SetNormalEdgeSmoothness);

        if (fresnelEdgeThresholdSlider != null)
            fresnelEdgeThresholdSlider.onValueChanged.AddListener(SetFresnelEdgeThreshold);

        if (fresnelEdgeStrengthSlider != null)
            fresnelEdgeStrengthSlider.onValueChanged.AddListener(SetFresnelEdgeStrength);
    }

    // Toggle setters
    public void SetDebugDefaults(bool value)
    {
        SetToggleProperty("_UseDebugDefaults", value);
    }

    public void SetEnableTextureSobel(bool value)
    {
        SetToggleProperty("_EnableTextureSobel", value);
    }

    public void SetEnableNormalEdges(bool value)
    {
        SetToggleProperty("_EnableNormalEdges", value);
    }

    public void SetEnableFresnelEdge(bool value)
    {
        SetToggleProperty("_EnableFresnelEdge", value);
    }

    public void SetEnableAlphaTest(bool value)
    {
        SetToggleProperty("_EnableAlphaTest", value);
    }

    public void SetUseDepthOffset(bool value)
    {
        SetToggleProperty("_UseOutlineDepthOffset", value);
        foreach (Material mat in runtimeMats)
        {
            if (value)
                mat.EnableKeyword("_USEOUTLINEDEPTHOFFSET_ON");
            else
                mat.DisableKeyword("_USEOUTLINEDEPTHOFFSET_ON");
        }
    }

    void SetToggleProperty(string propertyName, bool value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat(propertyName, value ? 1f : 0f);
        }
    }

    // Slider setters
    public void SetSobelFilterMode(float value)
    {
        int mode = Mathf.RoundToInt(value);
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_SobelFilterMode", mode);
            // Update shader keywords
            mat.DisableKeyword("_SOBELFILTERMODE_NONE");
            mat.DisableKeyword("_SOBELFILTERMODE_LIGHT");
            mat.DisableKeyword("_SOBELFILTERMODE_MODERATE");
            mat.DisableKeyword("_SOBELFILTERMODE_AGGRESSIVE");

            switch (mode)
            {
                case 0: mat.EnableKeyword("_SOBELFILTERMODE_NONE"); break;
                case 1: mat.EnableKeyword("_SOBELFILTERMODE_LIGHT"); break;
                case 2: mat.EnableKeyword("_SOBELFILTERMODE_MODERATE"); break;
                case 3: mat.EnableKeyword("_SOBELFILTERMODE_AGGRESSIVE"); break;
            }
        }
    }

    public void SetOutlineWidth(float value)
    {
        SetFloatProperty("_OuterOutlineWidth", value);
    }

    public void SetAlphaCutoff(float value)
    {
        SetFloatProperty("_AlphaCutoff", value);
    }

    public void SetSobelThreshold(float value)
    {
        SetFloatProperty("_SobelThreshold", value);
    }

    public void SetSobelSampleDistance(float value)
    {
        SetFloatProperty("_SobelSampleDistance", value);
    }

    public void SetSobelStrength(float value)
    {
        SetFloatProperty("_SobelStrength", value);
    }

    public void SetNormalEdgeThreshold(float value)
    {
        SetFloatProperty("_NormalEdgeThreshold", value);
    }

    public void SetNormalEdgeStrength(float value)
    {
        SetFloatProperty("_NormalEdgeStrength", value);
    }

    public void SetNormalEdgeSmoothness(float value)
    {
        SetFloatProperty("_NormalEdgeSmoothness", value);
    }

    public void SetFresnelEdgeThreshold(float value)
    {
        SetFloatProperty("_FresnelEdgeThreshold", value);
    }

    public void SetFresnelEdgeStrength(float value)
    {
        SetFloatProperty("_FresnelEdgeStrength", value);
    }

    private void SetFloatProperty(string property, float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat(property, value);
        }
    }

    private void SetSliderRanges()
    {
        if (sobelFilterModeSlider != null) { sobelFilterModeSlider.minValue = 0; sobelFilterModeSlider.maxValue = 3; }
        if (outerOutlineSlider != null) { outerOutlineSlider.minValue = 0; outerOutlineSlider.maxValue = 0.5f; }
        if (alphaCutoffSlider != null) { alphaCutoffSlider.minValue = 0; alphaCutoffSlider.maxValue = 1; }
        if (sobelThresholdSlider != null) { sobelThresholdSlider.minValue = 0.001f; sobelThresholdSlider.maxValue = 0.5f; }
        if (sobelSampleDistanceSlider != null) { sobelSampleDistanceSlider.minValue = 0; sobelSampleDistanceSlider.maxValue = 10; }
        if (sobelStrengthSlider != null) { sobelStrengthSlider.minValue = 0; sobelStrengthSlider.maxValue = 1; }
        if (normalEdgeThresholdSlider != null) { normalEdgeThresholdSlider.minValue = 0; normalEdgeThresholdSlider.maxValue = 1; }
        if (normalEdgeStrengthSlider != null) { normalEdgeStrengthSlider.minValue = 0; normalEdgeStrengthSlider.maxValue = 1; }
        if (normalEdgeSmoothnessSlider != null) { normalEdgeSmoothnessSlider.minValue = 0.01f; normalEdgeSmoothnessSlider.maxValue = 0.5f; }
        if (fresnelEdgeThresholdSlider != null) { fresnelEdgeThresholdSlider.minValue = 0; fresnelEdgeThresholdSlider.maxValue = 1; }
        if (fresnelEdgeStrengthSlider != null) { fresnelEdgeStrengthSlider.minValue = 0; fresnelEdgeStrengthSlider.maxValue = 1; }
    }
}
