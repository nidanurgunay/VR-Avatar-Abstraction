using UnityEngine;
using UnityEngine.UI;
using TMPro;

public class V10ShaderController : MonoBehaviour
{
    public enum MaterialTarget
    {
        All = 0,
        Body = 1,
        Clothing = 2,
        Eyelash = 3,
        Hair = 4
    }

    [Header("Material Selection")]
    public TMP_Dropdown materialSelector;
    public MaterialTarget currentTarget = MaterialTarget.All;

    [Header("Debug View Control")]
    public TMP_Dropdown debugViewDropdown;

    [Header("Individual Materials (assign in inspector or auto-detect)")]
    public Material bodyMaterial;
    public Material clothingMaterial;
    public Material eyelashMaterial;
    public Material hairMaterial;

    [Header("Target Renderers (for auto-detection)")]
    public Renderer[] avatarRenderers;

    [Header("Toggle Controls - Modes")]
    public Toggle debugDefaultsToggle;
    public Toggle enableTextureSobelToggle;
    public Toggle enableNormalEdgesToggle;
    public Toggle enableFresnelEdgeToggle;
    public Toggle enableAlphaTestToggle;

    [Header("Toggle Controls - Filtering Presets")]
    public Toggle lightFilteringToggle;
    public Toggle moderateFilteringToggle;
    public Toggle aggressiveFilteringToggle;

    [Header("Slider Controls - Basic")]
    public Slider outerOutlineSlider;
    public Slider alphaCutoffSlider;

    [Header("Slider Controls - Sobel")]
    public Slider innerLineThresholdSlider;
    public Slider innerLineBlurSlider;
    public Slider innerLineStrengthSlider;

    [Header("Slider Controls - Gaussian Blur")]
    public Slider blurRadiusSlider;
    public Slider centerWeightSlider;
    public Slider cardinalWeightSlider;
    public Slider diagonalWeightSlider;

    [Header("Slider Controls - Threshold")]
    public Slider thresholdMinSlider;
    public Slider thresholdMaxSlider;

    [Header("Slider Controls - Smoothstep")]
    public Slider smoothstepPassesSlider;
    public Slider smoothstepTightnessSlider;
    public Slider powerCurveSlider;

    [Header("Slider Controls - Normal Edges")]
    public Slider normalEdgeThresholdSlider;
    public Slider normalEdgeStrengthSlider;
    public Slider normalEdgeSmoothnessSlider;

    [Header("Slider Controls - Fresnel")]
    public Slider fresnelEdgeThresholdSlider;
    public Slider fresnelEdgeStrengthSlider;

    // Runtime instanced materials
    private Material runtimeBodyMat;
    private Material runtimeClothingMat;
    private Material runtimeEyelashMat;
    private Material runtimeHairMat;

    void Start()
    {
        InitializeMaterials();
        SetupMaterialSelector();
        SetupToggleListeners();
        SetupSliderListeners();
        SetSliderRanges();
        SetupDebugViewDropdown();
        LoadCurrentMaterialValues();
    }

    void InitializeMaterials()
    {
        // Get all renderers if not assigned
        if (avatarRenderers == null || avatarRenderers.Length == 0)
        {
            avatarRenderers = GetComponentsInChildren<Renderer>();
        }

        // Try to find materials by name if not assigned
        foreach (Renderer rend in avatarRenderers)
        {
            foreach (Material mat in rend.materials)
            {
                string matName = mat.name.ToLower().Replace(" (instance)", "");

                if (matName.Contains("body") && bodyMaterial == null)
                    bodyMaterial = mat;
                else if (matName.Contains("clothing") && clothingMaterial == null)
                    clothingMaterial = mat;
                else if (matName.Contains("eyelash") && eyelashMaterial == null)
                    eyelashMaterial = mat;
                else if (matName.Contains("hair") && hairMaterial == null)
                    hairMaterial = mat;
            }
        }

        // Create runtime instances
        if (bodyMaterial != null)
        {
            runtimeBodyMat = Instantiate(bodyMaterial);
            ReplaceMaterialOnRenderers(bodyMaterial, runtimeBodyMat);
        }
        if (clothingMaterial != null)
        {
            runtimeClothingMat = Instantiate(clothingMaterial);
            ReplaceMaterialOnRenderers(clothingMaterial, runtimeClothingMat);
        }
        if (eyelashMaterial != null)
        {
            runtimeEyelashMat = Instantiate(eyelashMaterial);
            ReplaceMaterialOnRenderers(eyelashMaterial, runtimeEyelashMat);
        }
        if (hairMaterial != null)
        {
            runtimeHairMat = Instantiate(hairMaterial);
            ReplaceMaterialOnRenderers(hairMaterial, runtimeHairMat);
        }
    }

    void ReplaceMaterialOnRenderers(Material original, Material replacement)
    {
        foreach (Renderer rend in avatarRenderers)
        {
            Material[] mats = rend.materials;
            for (int i = 0; i < mats.Length; i++)
            {
                if (mats[i].name.Replace(" (Instance)", "") == original.name.Replace(" (Instance)", ""))
                {
                    mats[i] = replacement;
                }
            }
            rend.materials = mats;
        }
    }

    void SetupMaterialSelector()
    {
        if (materialSelector != null)
        {
            materialSelector.ClearOptions();
            materialSelector.AddOptions(new System.Collections.Generic.List<string>
            {
                "All Materials",
                "Body",
                "Clothing",
                "Eyelash",
                "Hair"
            });
            materialSelector.value = (int)currentTarget;
            materialSelector.onValueChanged.AddListener(OnMaterialTargetChanged);
        }
    }

    void OnMaterialTargetChanged(int index)
    {
        currentTarget = (MaterialTarget)index;
        LoadCurrentMaterialValues();
    }

    // Load values from the currently selected material into the UI
    void LoadCurrentMaterialValues()
    {
        Material mat = GetPrimaryTargetMaterial();
        if (mat == null) return;

        // Load toggle states
        if (debugDefaultsToggle != null)
            debugDefaultsToggle.SetIsOnWithoutNotify(mat.GetFloat("_UseDebugDefaults") > 0.5f);
        if (enableTextureSobelToggle != null)
            enableTextureSobelToggle.SetIsOnWithoutNotify(mat.GetFloat("_EnableTextureSobel") > 0.5f);
        if (enableNormalEdgesToggle != null)
            enableNormalEdgesToggle.SetIsOnWithoutNotify(mat.GetFloat("_EnableNormalEdges") > 0.5f);
        if (enableFresnelEdgeToggle != null)
            enableFresnelEdgeToggle.SetIsOnWithoutNotify(mat.GetFloat("_EnableFresnelEdge") > 0.5f);
        if (enableAlphaTestToggle != null)
            enableAlphaTestToggle.SetIsOnWithoutNotify(mat.GetFloat("_EnableAlphaTest") > 0.5f);

        // Load filtering preset states
        if (lightFilteringToggle != null)
            lightFilteringToggle.SetIsOnWithoutNotify(mat.GetFloat("_UseLightFiltering") > 0.5f);
        if (moderateFilteringToggle != null)
            moderateFilteringToggle.SetIsOnWithoutNotify(mat.GetFloat("_UseModerateFiltering") > 0.5f);
        if (aggressiveFilteringToggle != null)
            aggressiveFilteringToggle.SetIsOnWithoutNotify(mat.GetFloat("_UseAggressiveFiltering") > 0.5f);

        // Load slider values
        UpdateSlider(outerOutlineSlider, mat.GetFloat("_OuterOutlineWidth"));
        UpdateSlider(alphaCutoffSlider, mat.GetFloat("_AlphaCutoff"));
        UpdateSlider(innerLineThresholdSlider, mat.GetFloat("_InnerLineThreshold"));
        UpdateSlider(innerLineBlurSlider, mat.GetFloat("_InnerLineBlur"));
        UpdateSlider(innerLineStrengthSlider, mat.GetFloat("_InnerLineStrength"));
        UpdateSlider(blurRadiusSlider, mat.GetFloat("_BlurRadiusMultiplier"));
        UpdateSlider(centerWeightSlider, mat.GetFloat("_GaussianCenterWeight"));
        UpdateSlider(cardinalWeightSlider, mat.GetFloat("_GaussianCardinalWeight"));
        UpdateSlider(diagonalWeightSlider, mat.GetFloat("_GaussianDiagonalWeight"));
        UpdateSlider(thresholdMinSlider, mat.GetFloat("_ThresholdMinMultiplier"));
        UpdateSlider(thresholdMaxSlider, mat.GetFloat("_ThresholdMaxMultiplier"));
        UpdateSlider(smoothstepPassesSlider, mat.GetFloat("_SmoothstepPasses"));
        UpdateSlider(smoothstepTightnessSlider, mat.GetFloat("_SmoothstepTightness"));
        UpdateSlider(powerCurveSlider, mat.GetFloat("_PowerCurve"));
        UpdateSlider(normalEdgeThresholdSlider, mat.GetFloat("_NormalEdgeThreshold"));
        UpdateSlider(normalEdgeStrengthSlider, mat.GetFloat("_NormalEdgeStrength"));
        UpdateSlider(normalEdgeSmoothnessSlider, mat.GetFloat("_NormalEdgeSmoothness"));
        UpdateSlider(fresnelEdgeThresholdSlider, mat.GetFloat("_FresnelEdgeThreshold"));
        UpdateSlider(fresnelEdgeStrengthSlider, mat.GetFloat("_FresnelEdgeStrength"));

        // Load debug view
        if (debugViewDropdown != null)
        {
            debugViewDropdown.SetValueWithoutNotify((int)mat.GetFloat("_DebugView"));
        }
    }

    // Get the primary material for reading values (when a specific material is selected)
    Material GetPrimaryTargetMaterial()
    {
        switch (currentTarget)
        {
            case MaterialTarget.Body: return runtimeBodyMat;
            case MaterialTarget.Clothing: return runtimeClothingMat;
            case MaterialTarget.Eyelash: return runtimeEyelashMat;
            case MaterialTarget.Hair: return runtimeHairMat;
            default: return runtimeBodyMat ?? runtimeClothingMat ?? runtimeEyelashMat ?? runtimeHairMat;
        }
    }

    // Get all materials that should be affected by changes
    Material[] GetTargetMaterials()
    {
        switch (currentTarget)
        {
            case MaterialTarget.Body:
                return runtimeBodyMat != null ? new Material[] { runtimeBodyMat } : new Material[0];
            case MaterialTarget.Clothing:
                return runtimeClothingMat != null ? new Material[] { runtimeClothingMat } : new Material[0];
            case MaterialTarget.Eyelash:
                return runtimeEyelashMat != null ? new Material[] { runtimeEyelashMat } : new Material[0];
            case MaterialTarget.Hair:
                return runtimeHairMat != null ? new Material[] { runtimeHairMat } : new Material[0];
            default: // All
                var mats = new System.Collections.Generic.List<Material>();
                if (runtimeBodyMat != null) mats.Add(runtimeBodyMat);
                if (runtimeClothingMat != null) mats.Add(runtimeClothingMat);
                if (runtimeEyelashMat != null) mats.Add(runtimeEyelashMat);
                if (runtimeHairMat != null) mats.Add(runtimeHairMat);
                return mats.ToArray();
        }
    }

    void SetupToggleListeners()
    {
        if (debugDefaultsToggle != null)
            debugDefaultsToggle.onValueChanged.AddListener(v => SetToggle("_UseDebugDefaults", v));

        if (enableTextureSobelToggle != null)
            enableTextureSobelToggle.onValueChanged.AddListener(v => SetToggle("_EnableTextureSobel", v));

        if (enableNormalEdgesToggle != null)
            enableNormalEdgesToggle.onValueChanged.AddListener(v => SetToggle("_EnableNormalEdges", v));

        if (enableFresnelEdgeToggle != null)
            enableFresnelEdgeToggle.onValueChanged.AddListener(v => SetToggle("_EnableFresnelEdge", v));

        if (enableAlphaTestToggle != null)
            enableAlphaTestToggle.onValueChanged.AddListener(v => SetToggle("_EnableAlphaTest", v));

        if (lightFilteringToggle != null)
            lightFilteringToggle.onValueChanged.AddListener(SetLightFiltering);

        if (moderateFilteringToggle != null)
            moderateFilteringToggle.onValueChanged.AddListener(SetModerateFiltering);

        if (aggressiveFilteringToggle != null)
            aggressiveFilteringToggle.onValueChanged.AddListener(SetAggressiveFiltering);
    }

    void SetupSliderListeners()
    {
        if (outerOutlineSlider != null)
            outerOutlineSlider.onValueChanged.AddListener(v => SetFloat("_OuterOutlineWidth", v));

        if (alphaCutoffSlider != null)
            alphaCutoffSlider.onValueChanged.AddListener(v => SetFloat("_AlphaCutoff", v));

        if (innerLineThresholdSlider != null)
            innerLineThresholdSlider.onValueChanged.AddListener(v => SetFloat("_InnerLineThreshold", v));

        if (innerLineBlurSlider != null)
            innerLineBlurSlider.onValueChanged.AddListener(v => SetFloat("_InnerLineBlur", v));

        if (innerLineStrengthSlider != null)
            innerLineStrengthSlider.onValueChanged.AddListener(v => SetFloat("_InnerLineStrength", v));

        if (blurRadiusSlider != null)
            blurRadiusSlider.onValueChanged.AddListener(v => SetFloat("_BlurRadiusMultiplier", v));

        if (centerWeightSlider != null)
            centerWeightSlider.onValueChanged.AddListener(v => SetFloat("_GaussianCenterWeight", v));

        if (cardinalWeightSlider != null)
            cardinalWeightSlider.onValueChanged.AddListener(v => SetFloat("_GaussianCardinalWeight", v));

        if (diagonalWeightSlider != null)
            diagonalWeightSlider.onValueChanged.AddListener(v => SetFloat("_GaussianDiagonalWeight", v));

        if (thresholdMinSlider != null)
            thresholdMinSlider.onValueChanged.AddListener(v => SetFloat("_ThresholdMinMultiplier", v));

        if (thresholdMaxSlider != null)
            thresholdMaxSlider.onValueChanged.AddListener(v => SetFloat("_ThresholdMaxMultiplier", v));

        if (smoothstepPassesSlider != null)
            smoothstepPassesSlider.onValueChanged.AddListener(v => SetFloat("_SmoothstepPasses", v));

        if (smoothstepTightnessSlider != null)
            smoothstepTightnessSlider.onValueChanged.AddListener(v => SetFloat("_SmoothstepTightness", v));

        if (powerCurveSlider != null)
            powerCurveSlider.onValueChanged.AddListener(v => SetFloat("_PowerCurve", v));

        if (normalEdgeThresholdSlider != null)
            normalEdgeThresholdSlider.onValueChanged.AddListener(v => SetFloat("_NormalEdgeThreshold", v));

        if (normalEdgeStrengthSlider != null)
            normalEdgeStrengthSlider.onValueChanged.AddListener(v => SetFloat("_NormalEdgeStrength", v));

        if (normalEdgeSmoothnessSlider != null)
            normalEdgeSmoothnessSlider.onValueChanged.AddListener(v => SetFloat("_NormalEdgeSmoothness", v));

        if (fresnelEdgeThresholdSlider != null)
            fresnelEdgeThresholdSlider.onValueChanged.AddListener(v => SetFloat("_FresnelEdgeThreshold", v));

        if (fresnelEdgeStrengthSlider != null)
            fresnelEdgeStrengthSlider.onValueChanged.AddListener(v => SetFloat("_FresnelEdgeStrength", v));
    }

    void SetupDebugViewDropdown()
    {
        if (debugViewDropdown != null)
        {
            debugViewDropdown.ClearOptions();
            debugViewDropdown.AddOptions(new System.Collections.Generic.List<string>
            {
                // "Final (Normal Output)",
                "Raw Sobel (Unfiltered Edges)",
                // "After Threshold",
                // "After Blur",
                // "After Power Curve",
                "Normal Edges Only",
                "Fresnel Edges Only"
                // "Combined Edges (Before Shading)"
            });
            debugViewDropdown.onValueChanged.AddListener(SetDebugView);
        }
    }

    public void SetLightFiltering(bool value)
    {
        if (value)
        {
            if (moderateFilteringToggle != null) moderateFilteringToggle.SetIsOnWithoutNotify(false);
            if (aggressiveFilteringToggle != null) aggressiveFilteringToggle.SetIsOnWithoutNotify(false);
            SetToggle("_UseModerateFiltering", false);
            SetToggle("_UseAggressiveFiltering", false);
            ApplyPreset(0.8f, 0.25f, 0.125f, 0.0625f, 0.2f, 2.0f, 2f, 0.2f, 1.5f);
        }
        SetToggle("_UseLightFiltering", value);
    }

    public void SetModerateFiltering(bool value)
    {
        if (value)
        {
            if (lightFilteringToggle != null) lightFilteringToggle.SetIsOnWithoutNotify(false);
            if (aggressiveFilteringToggle != null) aggressiveFilteringToggle.SetIsOnWithoutNotify(false);
            SetToggle("_UseLightFiltering", false);
            SetToggle("_UseAggressiveFiltering", false);
            ApplyPreset(1.0f, 0.3f, 0.12f, 0.05f, 0.4f, 1.6f, 3f, 0.3f, 2.0f);
        }
        SetToggle("_UseModerateFiltering", value);
    }

    public void SetAggressiveFiltering(bool value)
    {
        if (value)
        {
            if (lightFilteringToggle != null) lightFilteringToggle.SetIsOnWithoutNotify(false);
            if (moderateFilteringToggle != null) moderateFilteringToggle.SetIsOnWithoutNotify(false);
            SetToggle("_UseLightFiltering", false);
            SetToggle("_UseModerateFiltering", false);
            ApplyPreset(1.2f, 0.25f, 0.125f, 0.0625f, 0.85f, 1.15f, 4f, 1.0f, 3.0f);
        }
        SetToggle("_UseAggressiveFiltering", value);
    }

    public void SetDebugView(int value)
    {
        SetFloat("_DebugView", value);
    }

    void ApplyPreset(float blurRadius, float centerWeight, float cardinalWeight, float diagonalWeight,
        float threshMin, float threshMax, float smoothPasses, float smoothTightness, float powerCurve)
    {
        SetFloat("_BlurRadiusMultiplier", blurRadius);
        SetFloat("_GaussianCenterWeight", centerWeight);
        SetFloat("_GaussianCardinalWeight", cardinalWeight);
        SetFloat("_GaussianDiagonalWeight", diagonalWeight);
        SetFloat("_ThresholdMinMultiplier", threshMin);
        SetFloat("_ThresholdMaxMultiplier", threshMax);
        SetFloat("_SmoothstepPasses", smoothPasses);
        SetFloat("_SmoothstepTightness", smoothTightness);
        SetFloat("_PowerCurve", powerCurve);

        UpdateSlider(blurRadiusSlider, blurRadius);
        UpdateSlider(centerWeightSlider, centerWeight);
        UpdateSlider(cardinalWeightSlider, cardinalWeight);
        UpdateSlider(diagonalWeightSlider, diagonalWeight);
        UpdateSlider(thresholdMinSlider, threshMin);
        UpdateSlider(thresholdMaxSlider, threshMax);
        UpdateSlider(smoothstepPassesSlider, smoothPasses);
        UpdateSlider(smoothstepTightnessSlider, smoothTightness);
        UpdateSlider(powerCurveSlider, powerCurve);
    }

    void UpdateSlider(Slider slider, float value)
    {
        if (slider != null) slider.SetValueWithoutNotify(value);
    }

    void SetToggle(string property, bool value)
    {
        foreach (Material mat in GetTargetMaterials())
        {
            mat.SetFloat(property, value ? 1f : 0f);
        }
    }

    void SetFloat(string property, float value)
    {
        foreach (Material mat in GetTargetMaterials())
        {
            mat.SetFloat(property, value);
        }
    }

    private void SetSliderRanges()
    {
        if (outerOutlineSlider != null) { outerOutlineSlider.minValue = 0f; outerOutlineSlider.maxValue = 0.5f; }
        if (alphaCutoffSlider != null) { alphaCutoffSlider.minValue = 0f; alphaCutoffSlider.maxValue = 1f; }
        if (innerLineThresholdSlider != null) { innerLineThresholdSlider.minValue = 0.001f; innerLineThresholdSlider.maxValue = 0.5f; }
        if (innerLineBlurSlider != null) { innerLineBlurSlider.minValue = 0f; innerLineBlurSlider.maxValue = 10f; }
        if (innerLineStrengthSlider != null) { innerLineStrengthSlider.minValue = 0f; innerLineStrengthSlider.maxValue = 1f; }
        if (blurRadiusSlider != null) { blurRadiusSlider.minValue = 0.1f; blurRadiusSlider.maxValue = 10.0f; }
        if (centerWeightSlider != null) { centerWeightSlider.minValue = 0f; centerWeightSlider.maxValue = 1f; }
        if (cardinalWeightSlider != null) { cardinalWeightSlider.minValue = 0f; cardinalWeightSlider.maxValue = 0.5f; }
        if (diagonalWeightSlider != null) { diagonalWeightSlider.minValue = 0f; diagonalWeightSlider.maxValue = 0.25f; }
        if (thresholdMinSlider != null) { thresholdMinSlider.minValue = 0f; thresholdMinSlider.maxValue = 1f; }
        if (thresholdMaxSlider != null) { thresholdMaxSlider.minValue = 1f; thresholdMaxSlider.maxValue = 5f; }
        if (smoothstepPassesSlider != null) { smoothstepPassesSlider.minValue = 1f; smoothstepPassesSlider.maxValue = 4f; }
        if (smoothstepTightnessSlider != null) { smoothstepTightnessSlider.minValue = 0f; smoothstepTightnessSlider.maxValue = 1f; }
        if (powerCurveSlider != null) { powerCurveSlider.minValue = 0.5f; powerCurveSlider.maxValue = 5f; }
        if (normalEdgeThresholdSlider != null) { normalEdgeThresholdSlider.minValue = 0f; normalEdgeThresholdSlider.maxValue = 1f; }
        if (normalEdgeStrengthSlider != null) { normalEdgeStrengthSlider.minValue = 0f; normalEdgeStrengthSlider.maxValue = 1f; }
        if (normalEdgeSmoothnessSlider != null) { normalEdgeSmoothnessSlider.minValue = 0.01f; normalEdgeSmoothnessSlider.maxValue = 0.5f; }
        if (fresnelEdgeThresholdSlider != null) { fresnelEdgeThresholdSlider.minValue = 0f; fresnelEdgeThresholdSlider.maxValue = 1f; }
        if (fresnelEdgeStrengthSlider != null) { fresnelEdgeStrengthSlider.minValue = 0f; fresnelEdgeStrengthSlider.maxValue = 1f; }
    }

    // Public methods for direct material access
    public Material GetBodyMaterial() => runtimeBodyMat;
    public Material GetClothingMaterial() => runtimeClothingMat;
    public Material GetEyelashMaterial() => runtimeEyelashMat;
    public Material GetHairMaterial() => runtimeHairMat;
}
