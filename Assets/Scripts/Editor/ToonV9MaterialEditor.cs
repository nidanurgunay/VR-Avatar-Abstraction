using UnityEngine;
using UnityEditor;

public class ToonV9MaterialEditor : MaterialEditor
{
    private bool showGaussianSettings = true;
    private bool showEdgeThresholdSettings = true;
    private bool showSmoothstepSettings = true;

    public override void OnInspectorGUI()
    {
        Material material = target as Material;

        if (material.shader.name != "Custom/ToonShader_V9_ConfigurableGaussian")
        {
            base.OnInspectorGUI();
            return;
        }

        serializedObject.Update();

        // ==================== DEBUG MODE ====================
        EditorGUILayout.Space(5);
        EditorGUILayout.LabelField("Debug Mode", EditorStyles.boldLabel);
        DrawToggle(material, "_UseDebugDefaults", "Use Debug Defaults");

        // ==================== FILTERING PRESETS ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Filtering Presets (select one)", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Selecting a preset will update all Gaussian blur settings below.", MessageType.Info);

        bool light = material.GetFloat("_UseLightFiltering") > 0.5f;
        bool moderate = material.GetFloat("_UseModerateFiltering") > 0.5f;
        bool aggressive = material.GetFloat("_UseAggressiveFiltering") > 0.5f;

        EditorGUI.BeginChangeCheck();
        bool newLight = EditorGUILayout.Toggle("Light Filtering (V3 style)", light);
        if (EditorGUI.EndChangeCheck() && newLight != light)
        {
            if (newLight)
            {
                material.SetFloat("_UseLightFiltering", 1);
                material.SetFloat("_UseModerateFiltering", 0);
                material.SetFloat("_UseAggressiveFiltering", 0);
                ApplyPreset(material, PresetType.Light);
            }
            else
            {
                material.SetFloat("_UseLightFiltering", 0);
            }
        }

        EditorGUI.BeginChangeCheck();
        bool newModerate = EditorGUILayout.Toggle("Moderate Filtering (V4 style)", moderate);
        if (EditorGUI.EndChangeCheck() && newModerate != moderate)
        {
            if (newModerate)
            {
                material.SetFloat("_UseLightFiltering", 0);
                material.SetFloat("_UseModerateFiltering", 1);
                material.SetFloat("_UseAggressiveFiltering", 0);
                ApplyPreset(material, PresetType.Moderate);
            }
            else
            {
                material.SetFloat("_UseModerateFiltering", 0);
            }
        }

        EditorGUI.BeginChangeCheck();
        bool newAggressive = EditorGUILayout.Toggle("Aggressive Filtering (V5 style)", aggressive);
        if (EditorGUI.EndChangeCheck() && newAggressive != aggressive)
        {
            if (newAggressive)
            {
                material.SetFloat("_UseLightFiltering", 0);
                material.SetFloat("_UseModerateFiltering", 0);
                material.SetFloat("_UseAggressiveFiltering", 1);
                ApplyPreset(material, PresetType.Aggressive);
            }
            else
            {
                material.SetFloat("_UseAggressiveFiltering", 0);
            }
        }

        // Show warning if ANY preset is active
        bool anyPresetActive = light || moderate || aggressive;
        if (anyPresetActive)
        {
            EditorGUILayout.HelpBox("PRESET ACTIVE: Gaussian, Threshold, and Smoothstep parameters below are IGNORED. Turn OFF all presets to use manual controls.", MessageType.Warning);
        }
        else
        {
            EditorGUILayout.HelpBox("No preset active. Manual parameters are in effect.", MessageType.Info);
        }

        // ==================== INNER LINE SETTINGS ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Inner Line Settings", EditorStyles.boldLabel);
        DrawToggle(material, "_EnableInnerLines", "Enable Inner Lines");
        DrawSlider(material, "_InnerLineThreshold", "Inner Line Threshold", 0.001f, 0.5f);
        DrawSlider(material, "_InnerLineBlur", "Inner Line Sample Distance", 0.0f, 10.0f);
        DrawSlider(material, "_InnerLineStrength", "Inner Line Strength", 0f, 1f);

        // ==================== GAUSSIAN BLUR SETTINGS ====================
        EditorGUILayout.Space(10);
        showGaussianSettings = EditorGUILayout.Foldout(showGaussianSettings, "Gaussian Blur Settings", true, EditorStyles.foldoutHeader);
        if (showGaussianSettings)
        {
            EditorGUI.indentLevel++;
            DrawSlider(material, "_BlurRadiusMultiplier", "Blur Radius Multiplier", 0.1f, 3.0f);
            DrawSlider(material, "_GaussianCenterWeight", "Center Weight", 0.0f, 1.0f);
            DrawSlider(material, "_GaussianCardinalWeight", "Cardinal Weight (per sample)", 0.0f, 0.5f);
            DrawSlider(material, "_GaussianDiagonalWeight", "Diagonal Weight (per sample)", 0.0f, 0.25f);
            EditorGUI.indentLevel--;
        }

        // ==================== EDGE THRESHOLD SETTINGS ====================
        EditorGUILayout.Space(5);
        showEdgeThresholdSettings = EditorGUILayout.Foldout(showEdgeThresholdSettings, "Edge Threshold Settings", true, EditorStyles.foldoutHeader);
        if (showEdgeThresholdSettings)
        {
            EditorGUI.indentLevel++;
            DrawSlider(material, "_ThresholdMinMultiplier", "Threshold Min Multiplier", 0.0f, 1.0f);
            DrawSlider(material, "_ThresholdMaxMultiplier", "Threshold Max Multiplier", 1.0f, 5.0f);
            EditorGUI.indentLevel--;
        }

        // ==================== SMOOTHSTEP SETTINGS ====================
        EditorGUILayout.Space(5);
        showSmoothstepSettings = EditorGUILayout.Foldout(showSmoothstepSettings, "Smoothstep Filtering", true, EditorStyles.foldoutHeader);
        if (showSmoothstepSettings)
        {
            EditorGUI.indentLevel++;
            DrawSlider(material, "_SmoothstepPasses", "Smoothstep Passes (1-4)", 1f, 4f);
            DrawSlider(material, "_SmoothstepTightness", "Smoothstep Tightness", 0.0f, 1.0f);
            DrawSlider(material, "_PowerCurve", "Power Curve (noise suppression)", 0.5f, 5.0f);
            EditorGUI.indentLevel--;
        }

        // ==================== ALPHA TEST ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Alpha Test", EditorStyles.boldLabel);
        DrawToggle(material, "_EnableAlphaTest", "Enable Alpha Test (for eyelashes)");
        DrawSlider(material, "_AlphaCutoff", "Alpha Cutoff", 0f, 1f);

        // Apply changes
        if (GUI.changed)
        {
            EditorUtility.SetDirty(material);
        }
    }

    private void DrawToggle(Material material, string property, string label)
    {
        bool current = material.GetFloat(property) > 0.5f;
        EditorGUI.BeginChangeCheck();
        bool newValue = EditorGUILayout.Toggle(label, current);
        if (EditorGUI.EndChangeCheck())
        {
            material.SetFloat(property, newValue ? 1f : 0f);
        }
    }

    private void DrawSlider(Material material, string property, string label, float min, float max)
    {
        float current = material.GetFloat(property);
        EditorGUI.BeginChangeCheck();
        float newValue = EditorGUILayout.Slider(label, current, min, max);
        if (EditorGUI.EndChangeCheck())
        {
            material.SetFloat(property, newValue);
        }
    }

    private enum PresetType { Light, Moderate, Aggressive }

    private void ApplyPreset(Material material, PresetType preset)
    {
        switch (preset)
        {
            case PresetType.Light:
                material.SetFloat("_BlurRadiusMultiplier", 0.8f);
                material.SetFloat("_GaussianCenterWeight", 0.25f);
                material.SetFloat("_GaussianCardinalWeight", 0.125f);
                material.SetFloat("_GaussianDiagonalWeight", 0.0625f);
                material.SetFloat("_ThresholdMinMultiplier", 0.2f);
                material.SetFloat("_ThresholdMaxMultiplier", 2.0f);
                material.SetFloat("_SmoothstepPasses", 2.0f);
                material.SetFloat("_SmoothstepTightness", 0.2f);
                material.SetFloat("_PowerCurve", 1.5f);
                break;

            case PresetType.Moderate:
                material.SetFloat("_BlurRadiusMultiplier", 1.0f);
                material.SetFloat("_GaussianCenterWeight", 0.3f);
                material.SetFloat("_GaussianCardinalWeight", 0.12f);
                material.SetFloat("_GaussianDiagonalWeight", 0.05f);
                material.SetFloat("_ThresholdMinMultiplier", 0.4f);
                material.SetFloat("_ThresholdMaxMultiplier", 1.6f);
                material.SetFloat("_SmoothstepPasses", 3.0f);
                material.SetFloat("_SmoothstepTightness", 0.3f);
                material.SetFloat("_PowerCurve", 2.0f);
                break;

            case PresetType.Aggressive:
                material.SetFloat("_BlurRadiusMultiplier", 1.2f);
                material.SetFloat("_GaussianCenterWeight", 0.25f);
                material.SetFloat("_GaussianCardinalWeight", 0.125f);
                material.SetFloat("_GaussianDiagonalWeight", 0.0625f);
                material.SetFloat("_ThresholdMinMultiplier", 0.85f);
                material.SetFloat("_ThresholdMaxMultiplier", 1.15f);
                material.SetFloat("_SmoothstepPasses", 4.0f);
                material.SetFloat("_SmoothstepTightness", 1.0f);  // 1.0 = exact V5 match
                material.SetFloat("_PowerCurve", 3.0f);
                break;
        }
    }
}