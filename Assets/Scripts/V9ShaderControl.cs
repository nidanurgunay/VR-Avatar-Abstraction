using UnityEngine;
using UnityEngine.UI;

public class V9ShaderController : MonoBehaviour
{
    [Header("Target")]
    public Renderer[] avatarRenderers;

    [Header("Toggle Controls")]
    public Toggle debugDefaultsToggle;
    public Toggle lightFilteringToggle;
    public Toggle moderateFilteringToggle;
    public Toggle aggressiveFilteringToggle;
    public Toggle enableAlphaTestToggle;
    public Toggle useDepthOffsetToggle;

    [Header("Slider Controls")]
    public Slider outerOutlineSlider;
    public Slider innerLineThresholdSlider;
    public Slider innerLineBlurSlider;
    public Slider innerLineStrengthSlider;
    public Slider alphaCutoffSlider;

    [Header("Gaussian Blur Sliders")]
    public Slider blurRadiusSlider;
    public Slider centerWeightSlider;
    public Slider cardinalWeightSlider;
    public Slider diagonalWeightSlider;

    [Header("Edge Threshold Sliders")]
    public Slider thresholdMinSlider;
    public Slider thresholdMaxSlider;

    [Header("Smoothstep Sliders")]
    public Slider smoothstepPassesSlider;
    public Slider smoothstepTightnessSlider;
    public Slider powerCurveSlider;

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

        if (lightFilteringToggle != null)
            lightFilteringToggle.onValueChanged.AddListener(SetLightFiltering);

        if (moderateFilteringToggle != null)
            moderateFilteringToggle.onValueChanged.AddListener(SetModerateFiltering);

        if (aggressiveFilteringToggle != null)
            aggressiveFilteringToggle.onValueChanged.AddListener(SetAggressiveFiltering);

        if (enableAlphaTestToggle != null)
            enableAlphaTestToggle.onValueChanged.AddListener(SetEnableAlphaTest);

        if (useDepthOffsetToggle != null)
            useDepthOffsetToggle.onValueChanged.AddListener(SetUseDepthOffset);
    }

    void SetupSliderListeners()
    {
        if (outerOutlineSlider != null)
            outerOutlineSlider.onValueChanged.AddListener(SetOutlineWidth);

        if (innerLineThresholdSlider != null)
            innerLineThresholdSlider.onValueChanged.AddListener(SetInnerLineThreshold);

        if (innerLineBlurSlider != null)
            innerLineBlurSlider.onValueChanged.AddListener(SetInnerLineBlur);

        if (innerLineStrengthSlider != null)
            innerLineStrengthSlider.onValueChanged.AddListener(SetInnerLineStrength);

        if (alphaCutoffSlider != null)
            alphaCutoffSlider.onValueChanged.AddListener(SetAlphaCutoff);

        if (blurRadiusSlider != null)
            blurRadiusSlider.onValueChanged.AddListener(SetBlurRadius);

        if (centerWeightSlider != null)
            centerWeightSlider.onValueChanged.AddListener(SetCenterWeight);

        if (cardinalWeightSlider != null)
            cardinalWeightSlider.onValueChanged.AddListener(SetCardinalWeight);

        if (diagonalWeightSlider != null)
            diagonalWeightSlider.onValueChanged.AddListener(SetDiagonalWeight);

        if (thresholdMinSlider != null)
            thresholdMinSlider.onValueChanged.AddListener(SetThresholdMin);

        if (thresholdMaxSlider != null)
            thresholdMaxSlider.onValueChanged.AddListener(SetThresholdMax);

        if (smoothstepPassesSlider != null)
            smoothstepPassesSlider.onValueChanged.AddListener(SetSmoothstepPasses);

        if (smoothstepTightnessSlider != null)
            smoothstepTightnessSlider.onValueChanged.AddListener(SetSmoothstepTightness);

        if (powerCurveSlider != null)
            powerCurveSlider.onValueChanged.AddListener(SetPowerCurve);
    }

    // Toggle setters
    public void SetDebugDefaults(bool value)
    {
        SetToggleProperty("_UseDebugDefaults", value);
    }

    public void SetEnableInnerLines(bool value)
    {
        SetToggleProperty("_EnableInnerLines", value);
    }

    public void SetLightFiltering(bool value)
    {
        if (value)
        {
            // Disable other filtering presets when enabling this one
            if (moderateFilteringToggle != null) moderateFilteringToggle.isOn = false;
            if (aggressiveFilteringToggle != null) aggressiveFilteringToggle.isOn = false;

            // Apply Light Filtering preset values (V3 style)
            ApplyPresetValues(0.8f, 0.25f, 0.125f, 0.0625f, 0.2f, 2.0f, 2f, 0.2f, 1.5f);
        }
        SetToggleProperty("_UseLightFiltering", value);
    }

    public void SetModerateFiltering(bool value)
    {
        if (value)
        {
            if (lightFilteringToggle != null) lightFilteringToggle.isOn = false;
            if (aggressiveFilteringToggle != null) aggressiveFilteringToggle.isOn = false;

            // Apply Moderate Filtering preset values (V4 style)
            ApplyPresetValues(1.0f, 0.3f, 0.12f, 0.05f, 0.4f, 1.6f, 3f, 0.3f, 2.0f);
        }
        SetToggleProperty("_UseModerateFiltering", value);
    }

    public void SetAggressiveFiltering(bool value)
    {
        if (value)
        {
            if (lightFilteringToggle != null) lightFilteringToggle.isOn = false;
            if (moderateFilteringToggle != null) moderateFilteringToggle.isOn = false;

            // Apply Aggressive Filtering preset values (V5 style) - tightness 1.0 = exact V5 match
            ApplyPresetValues(1.2f, 0.25f, 0.125f, 0.0625f, 0.85f, 1.15f, 4f, 1.0f, 3.0f);
        }
        SetToggleProperty("_UseAggressiveFiltering", value);
    }

    void ApplyPresetValues(float blurRadius, float centerWeight, float cardinalWeight, float diagonalWeight,
        float thresholdMin, float thresholdMax, float smoothPasses, float smoothTightness, float powerCurve)
    {
        // Set material properties
        SetFloatProperty("_BlurRadiusMultiplier", blurRadius);
        SetFloatProperty("_GaussianCenterWeight", centerWeight);
        SetFloatProperty("_GaussianCardinalWeight", cardinalWeight);
        SetFloatProperty("_GaussianDiagonalWeight", diagonalWeight);
        SetFloatProperty("_ThresholdMinMultiplier", thresholdMin);
        SetFloatProperty("_ThresholdMaxMultiplier", thresholdMax);
        SetFloatProperty("_SmoothstepPasses", smoothPasses);
        SetFloatProperty("_SmoothstepTightness", smoothTightness);
        SetFloatProperty("_PowerCurve", powerCurve);

        // Update sliders to reflect preset values (without triggering listeners)
        UpdateSliderWithoutNotify(blurRadiusSlider, blurRadius);
        UpdateSliderWithoutNotify(centerWeightSlider, centerWeight);
        UpdateSliderWithoutNotify(cardinalWeightSlider, cardinalWeight);
        UpdateSliderWithoutNotify(diagonalWeightSlider, diagonalWeight);
        UpdateSliderWithoutNotify(thresholdMinSlider, thresholdMin);
        UpdateSliderWithoutNotify(thresholdMaxSlider, thresholdMax);
        UpdateSliderWithoutNotify(smoothstepPassesSlider, smoothPasses);
        UpdateSliderWithoutNotify(smoothstepTightnessSlider, smoothTightness);
        UpdateSliderWithoutNotify(powerCurveSlider, powerCurve);
    }

    void UpdateSliderWithoutNotify(Slider slider, float value)
    {
        if (slider != null)
        {
            slider.SetValueWithoutNotify(value);
        }
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

    void SetFloatProperty(string property, float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat(property, value);
        }
    }

    // Slider setters
    public void SetOutlineWidth(float value)
    {
        SetFloatProperty("_OuterOutlineWidth", value);
    }

    public void SetInnerLineThreshold(float value)
    {
        SetFloatProperty("_InnerLineThreshold", value);
    }

    public void SetInnerLineBlur(float value)
    {
        SetFloatProperty("_InnerLineBlur", value);
    }

    public void SetInnerLineStrength(float value)
    {
        SetFloatProperty("_InnerLineStrength", value);
    }

    public void SetAlphaCutoff(float value)
    {
        SetFloatProperty("_AlphaCutoff", value);
    }

    public void SetBlurRadius(float value)
    {
        SetFloatProperty("_BlurRadiusMultiplier", value);
    }

    public void SetCenterWeight(float value)
    {
        SetFloatProperty("_GaussianCenterWeight", value);
    }

    public void SetCardinalWeight(float value)
    {
        SetFloatProperty("_GaussianCardinalWeight", value);
    }

    public void SetDiagonalWeight(float value)
    {
        SetFloatProperty("_GaussianDiagonalWeight", value);
    }

    public void SetThresholdMin(float value)
    {
        SetFloatProperty("_ThresholdMinMultiplier", value);
    }

    public void SetThresholdMax(float value)
    {
        SetFloatProperty("_ThresholdMaxMultiplier", value);
    }

    public void SetSmoothstepPasses(float value)
    {
        SetFloatProperty("_SmoothstepPasses", value);
    }

    public void SetSmoothstepTightness(float value)
    {
        SetFloatProperty("_SmoothstepTightness", value);
    }

    public void SetPowerCurve(float value)
    {
        SetFloatProperty("_PowerCurve", value);
    }

    void SetSliderRanges()
    {
        if (outerOutlineSlider != null) { outerOutlineSlider.minValue = 0; outerOutlineSlider.maxValue = 0.5f; }
        if (innerLineThresholdSlider != null) { innerLineThresholdSlider.minValue = 0.001f; innerLineThresholdSlider.maxValue = 0.5f; }
        if (innerLineBlurSlider != null) { innerLineBlurSlider.minValue = 0; innerLineBlurSlider.maxValue = 10; }
        if (innerLineStrengthSlider != null) { innerLineStrengthSlider.minValue = 0; innerLineStrengthSlider.maxValue = 1; }
        if (alphaCutoffSlider != null) { alphaCutoffSlider.minValue = 0; alphaCutoffSlider.maxValue = 1; }
        if (blurRadiusSlider != null) { blurRadiusSlider.minValue = 0.1f; blurRadiusSlider.maxValue = 3.0f; }
        if (centerWeightSlider != null) { centerWeightSlider.minValue = 0; centerWeightSlider.maxValue = 1; }
        if (cardinalWeightSlider != null) { cardinalWeightSlider.minValue = 0; cardinalWeightSlider.maxValue = 0.5f; }
        if (diagonalWeightSlider != null) { diagonalWeightSlider.minValue = 0; diagonalWeightSlider.maxValue = 0.25f; }
        if (thresholdMinSlider != null) { thresholdMinSlider.minValue = 0; thresholdMinSlider.maxValue = 1; }
        if (thresholdMaxSlider != null) { thresholdMaxSlider.minValue = 1; thresholdMaxSlider.maxValue = 5; }
        if (smoothstepPassesSlider != null) { smoothstepPassesSlider.minValue = 1; smoothstepPassesSlider.maxValue = 4; }
        if (smoothstepTightnessSlider != null) { smoothstepTightnessSlider.minValue = 0; smoothstepTightnessSlider.maxValue = 1; }
        if (powerCurveSlider != null) { powerCurveSlider.minValue = 0.5f; powerCurveSlider.maxValue = 5.0f; }
    }
}
