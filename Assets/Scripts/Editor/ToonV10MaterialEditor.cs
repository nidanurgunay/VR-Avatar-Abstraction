using UnityEngine;
using UnityEditor;

public class ToonV10MaterialEditor : ShaderGUI
{
    private bool showSobelSettings = true;
    private bool showGaussianSettings = true;
    private bool showNormalEdgeSettings = true;
    private bool showFresnelSettings = true;

    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material material = materialEditor.target as Material;

        // ==================== DEBUG MODE ====================
        EditorGUILayout.Space(5);
        EditorGUILayout.LabelField("Debug & Visualization", EditorStyles.boldLabel);

        // Debug View Dropdown - This is how you see each pass stage!
        MaterialProperty debugView = FindProperty("_DebugView", properties, false);
        if (debugView != null)
        {
            string[] debugViewOptions = new string[] {
                "Final (Normal Output)",
                "Raw Sobel (Unfiltered Edges)",
                "After Threshold",
                "After Blur",
                "Normal Edges Only",
                "Fresnel Edges Only"
            };

            int currentMode = (int)debugView.floatValue;
            EditorGUI.BeginChangeCheck();
            int newMode = EditorGUILayout.Popup("Debug View", currentMode, debugViewOptions);
            if (EditorGUI.EndChangeCheck())
            {
                debugView.floatValue = newMode;
            }

            if (newMode != 0)
            {
                EditorGUILayout.HelpBox("Debug mode active! Output shows grayscale visualization of the selected processing stage.", MessageType.Warning);
            }
        }

        EditorGUILayout.Space(5);
        DrawToggleProperty(materialEditor, properties, "_UseDebugDefaults", "Use Debug Defaults");

        // ==================== BASE ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Base", EditorStyles.boldLabel);
        DrawProperty(materialEditor, properties, "_Color");
        DrawProperty(materialEditor, properties, "_MainTex");
        DrawProperty(materialEditor, properties, "_TextureIntensity");

        // ==================== TOON SHADING ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Toon Shading", EditorStyles.boldLabel);
        DrawProperty(materialEditor, properties, "_ToonSteps");
        DrawProperty(materialEditor, properties, "_ToonThreshold");
        DrawProperty(materialEditor, properties, "_ToonSmoothness");
        DrawProperty(materialEditor, properties, "_ShadowStrength");

        // ==================== OUTER OUTLINE ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Outer Outline", EditorStyles.boldLabel);
        DrawProperty(materialEditor, properties, "_OuterOutlineWidth");
        DrawProperty(materialEditor, properties, "_OuterOutlineColor");
        DrawToggleProperty(materialEditor, properties, "_UseOutlineDepthOffset", "Use Depth Offset");
        DrawProperty(materialEditor, properties, "_OutlineDepthBias");

        // ==================== EDGE DETECTION MODES ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Edge Detection Modes", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Enable one or more edge detection methods. They will be combined based on the blend mode.", MessageType.Info);
        DrawToggleProperty(materialEditor, properties, "_EnableTextureSobel", "Enable Texture Sobel");
        DrawToggleProperty(materialEditor, properties, "_EnableNormalEdges", "Enable Normal Edges");
        DrawToggleProperty(materialEditor, properties, "_EnableFresnelEdge", "Enable Fresnel Silhouette");

        // ==================== FILTERING PRESETS ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Filtering Presets (for Sobel)", EditorStyles.boldLabel);

        MaterialProperty lightFilter = FindProperty("_UseLightFiltering", properties);
        MaterialProperty moderateFilter = FindProperty("_UseModerateFiltering", properties);
        MaterialProperty aggressiveFilter = FindProperty("_UseAggressiveFiltering", properties);

        bool lightOn = lightFilter.floatValue > 0.5f;
        bool moderateOn = moderateFilter.floatValue > 0.5f;
        bool aggressiveOn = aggressiveFilter.floatValue > 0.5f;

        EditorGUI.BeginChangeCheck();
        bool newLightOn = EditorGUILayout.Toggle("Light Filtering (V3 style)", lightOn);
        if (EditorGUI.EndChangeCheck() && newLightOn != lightOn)
        {
            if (newLightOn)
            {
                lightFilter.floatValue = 1; moderateFilter.floatValue = 0; aggressiveFilter.floatValue = 0;
                ApplyPreset(properties, PresetType.Light);
            }
            else { lightFilter.floatValue = 0; }
        }

        EditorGUI.BeginChangeCheck();
        bool newModerateOn = EditorGUILayout.Toggle("Moderate Filtering (V4 style)", moderateOn);
        if (EditorGUI.EndChangeCheck() && newModerateOn != moderateOn)
        {
            if (newModerateOn)
            {
                lightFilter.floatValue = 0; moderateFilter.floatValue = 1; aggressiveFilter.floatValue = 0;
                ApplyPreset(properties, PresetType.Moderate);
            }
            else { moderateFilter.floatValue = 0; }
        }

        EditorGUI.BeginChangeCheck();
        bool newAggressiveOn = EditorGUILayout.Toggle("Aggressive Filtering (V5 style)", aggressiveOn);
        if (EditorGUI.EndChangeCheck() && newAggressiveOn != aggressiveOn)
        {
            if (newAggressiveOn)
            {
                lightFilter.floatValue = 0; moderateFilter.floatValue = 0; aggressiveFilter.floatValue = 1;
                ApplyPreset(properties, PresetType.Aggressive);
            }
            else { aggressiveFilter.floatValue = 0; }
        }

        // Show warning if ANY preset is active
        bool anyPresetActive = lightOn || moderateOn || aggressiveOn;
        if (anyPresetActive)
        {
            EditorGUILayout.HelpBox("PRESET ACTIVE: Gaussian Blur & Smoothstep parameters below are IGNORED. Turn OFF all presets to use manual controls.", MessageType.Warning);
        }
        else
        {
            EditorGUILayout.HelpBox("No preset active. Manual Gaussian/Smoothstep parameters are in effect.", MessageType.Info);
        }

        // ==================== TEXTURE SOBEL SETTINGS ====================
        EditorGUILayout.Space(10);
        showSobelSettings = EditorGUILayout.Foldout(showSobelSettings, "Texture Sobel Settings", true, EditorStyles.foldoutHeader);
        if (showSobelSettings)
        {
            EditorGUI.indentLevel++;
            DrawProperty(materialEditor, properties, "_InnerLineColor");
            DrawProperty(materialEditor, properties, "_InnerLineThreshold");
            DrawProperty(materialEditor, properties, "_InnerLineBlur");
            DrawProperty(materialEditor, properties, "_InnerLineStrength");
            EditorGUI.indentLevel--;
        }

        // ==================== MODULAR PASS TOGGLES ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Modular Processing Toggles", EditorStyles.boldLabel);
        EditorGUILayout.HelpBox("Toggle individual processing steps ON/OFF to analyze their effect. Use Debug View above to visualize each stage.", MessageType.Info);

        EditorGUILayout.BeginHorizontal();
        DrawToggleProperty(materialEditor, properties, "_EnableToonShading", "Toon Shading");
        DrawToggleProperty(materialEditor, properties, "_EnableOuterOutline", "Outer Outline");
        DrawToggleProperty(materialEditor, properties, "_EnableRim", "Rim Lighting");
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.Space(5);
        EditorGUILayout.LabelField("Sobel Processing Chain:", EditorStyles.miniLabel);

        EditorGUILayout.BeginHorizontal();
        DrawToggleProperty(materialEditor, properties, "_EnableGaussianBlur", "Gaussian Blur");
        DrawToggleProperty(materialEditor, properties, "_EnableThreshold", "Threshold");
        EditorGUILayout.EndHorizontal();

        EditorGUILayout.BeginHorizontal();
        DrawToggleProperty(materialEditor, properties, "_EnablePass1", "Pass 1");
        DrawToggleProperty(materialEditor, properties, "_EnablePass2", "Pass 2");
        DrawToggleProperty(materialEditor, properties, "_EnablePass3", "Pass 3");
        DrawToggleProperty(materialEditor, properties, "_EnablePass4", "Pass 4");
        EditorGUILayout.EndHorizontal();

        DrawToggleProperty(materialEditor, properties, "_EnablePowerCurve", "Power Curve");

        // ==================== GAUSSIAN BLUR SETTINGS ====================
        EditorGUILayout.Space(5);
        string gaussianFoldoutLabel = anyPresetActive
            ? "Gaussian Blur & Smoothstep Parameters [OVERRIDDEN BY PRESET]"
            : "Gaussian Blur & Smoothstep Parameters";
        showGaussianSettings = EditorGUILayout.Foldout(showGaussianSettings, gaussianFoldoutLabel, true, EditorStyles.foldoutHeader);
        if (showGaussianSettings)
        {
            EditorGUI.indentLevel++;
            if (anyPresetActive)
            {
                EditorGUILayout.LabelField("These values are IGNORED while a preset is active", EditorStyles.miniLabel);
            }
            EditorGUILayout.LabelField("Blur Settings", EditorStyles.miniLabel);
            DrawProperty(materialEditor, properties, "_BlurRadiusMultiplier");
            DrawProperty(materialEditor, properties, "_GaussianCenterWeight");
            DrawProperty(materialEditor, properties, "_GaussianCardinalWeight");
            DrawProperty(materialEditor, properties, "_GaussianDiagonalWeight");

            EditorGUILayout.Space(5);
            EditorGUILayout.LabelField("Threshold Settings", EditorStyles.miniLabel);
            DrawProperty(materialEditor, properties, "_ThresholdMinMultiplier");
            DrawProperty(materialEditor, properties, "_ThresholdMaxMultiplier");

            EditorGUILayout.Space(5);
            EditorGUILayout.LabelField("Smoothstep Settings", EditorStyles.miniLabel);
            DrawProperty(materialEditor, properties, "_SmoothstepTightness");
            DrawProperty(materialEditor, properties, "_PowerCurve");
            EditorGUI.indentLevel--;
        }

        // ==================== NORMAL EDGE SETTINGS ====================
        EditorGUILayout.Space(5);
        showNormalEdgeSettings = EditorGUILayout.Foldout(showNormalEdgeSettings, "Normal Edge Settings", true, EditorStyles.foldoutHeader);
        if (showNormalEdgeSettings)
        {
            EditorGUI.indentLevel++;
            DrawProperty(materialEditor, properties, "_NormalEdgeThreshold");
            DrawProperty(materialEditor, properties, "_NormalEdgeStrength");
            DrawProperty(materialEditor, properties, "_NormalEdgeSmoothness");
            EditorGUI.indentLevel--;
        }

        // ==================== FRESNEL SETTINGS ====================
        EditorGUILayout.Space(5);
        showFresnelSettings = EditorGUILayout.Foldout(showFresnelSettings, "Fresnel Silhouette Settings", true, EditorStyles.foldoutHeader);
        if (showFresnelSettings)
        {
            EditorGUI.indentLevel++;
            DrawProperty(materialEditor, properties, "_FresnelEdgeThreshold");
            DrawProperty(materialEditor, properties, "_FresnelEdgeStrength");
            EditorGUI.indentLevel--;
        }

        // ==================== EDGE COMBINATION ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Edge Combination", EditorStyles.boldLabel);
        DrawProperty(materialEditor, properties, "_EdgeColor");
        DrawProperty(materialEditor, properties, "_EdgeBlendMode");

        // ==================== RIM AND AMBIENT ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Rim and Ambient", EditorStyles.boldLabel);
        DrawProperty(materialEditor, properties, "_RimColor");
        DrawProperty(materialEditor, properties, "_RimPower");
        DrawProperty(materialEditor, properties, "_AmbientColor");

        // ==================== ALPHA TEST ====================
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Alpha Test", EditorStyles.boldLabel);
        DrawToggleProperty(materialEditor, properties, "_EnableAlphaTest", "Enable Alpha Test");
        DrawProperty(materialEditor, properties, "_AlphaCutoff");

        if (GUI.changed)
        {
            EditorUtility.SetDirty(material);
        }
    }

    private void DrawProperty(MaterialEditor editor, MaterialProperty[] props, string name)
    {
        MaterialProperty prop = FindProperty(name, props, false);
        if (prop != null)
        {
            editor.ShaderProperty(prop, prop.displayName);
        }
    }

    private void DrawToggleProperty(MaterialEditor editor, MaterialProperty[] props, string name, string label)
    {
        MaterialProperty prop = FindProperty(name, props, false);
        if (prop != null)
        {
            bool current = prop.floatValue > 0.5f;
            EditorGUI.BeginChangeCheck();
            bool newValue = EditorGUILayout.Toggle(label, current);
            if (EditorGUI.EndChangeCheck())
            {
                prop.floatValue = newValue ? 1f : 0f;
            }
        }
    }

    private enum PresetType { Light, Moderate, Aggressive }

    private void ApplyPreset(MaterialProperty[] properties, PresetType preset)
    {
        switch (preset)
        {
            case PresetType.Light:
                SetFloat(properties, "_BlurRadiusMultiplier", 0.8f);
                SetFloat(properties, "_GaussianCenterWeight", 0.25f);
                SetFloat(properties, "_GaussianCardinalWeight", 0.125f);
                SetFloat(properties, "_GaussianDiagonalWeight", 0.0625f);
                SetFloat(properties, "_ThresholdMinMultiplier", 0.2f);
                SetFloat(properties, "_ThresholdMaxMultiplier", 2.0f);
                SetFloat(properties, "_SmoothstepPasses", 2.0f);
                SetFloat(properties, "_SmoothstepTightness", 0.2f);
                SetFloat(properties, "_PowerCurve", 1.5f);
                break;

            case PresetType.Moderate:
                SetFloat(properties, "_BlurRadiusMultiplier", 1.0f);
                SetFloat(properties, "_GaussianCenterWeight", 0.3f);
                SetFloat(properties, "_GaussianCardinalWeight", 0.12f);
                SetFloat(properties, "_GaussianDiagonalWeight", 0.05f);
                SetFloat(properties, "_ThresholdMinMultiplier", 0.4f);
                SetFloat(properties, "_ThresholdMaxMultiplier", 1.6f);
                SetFloat(properties, "_SmoothstepPasses", 3.0f);
                SetFloat(properties, "_SmoothstepTightness", 0.3f);
                SetFloat(properties, "_PowerCurve", 2.0f);
                break;

            case PresetType.Aggressive:
                SetFloat(properties, "_BlurRadiusMultiplier", 1.2f);
                SetFloat(properties, "_GaussianCenterWeight", 0.25f);
                SetFloat(properties, "_GaussianCardinalWeight", 0.125f);
                SetFloat(properties, "_GaussianDiagonalWeight", 0.0625f);
                SetFloat(properties, "_ThresholdMinMultiplier", 0.85f);
                SetFloat(properties, "_ThresholdMaxMultiplier", 1.15f);
                SetFloat(properties, "_SmoothstepPasses", 4.0f);
                SetFloat(properties, "_SmoothstepTightness", 1.0f);
                SetFloat(properties, "_PowerCurve", 3.0f);
                break;
        }
    }

    private void SetFloat(MaterialProperty[] properties, string name, float value)
    {
        MaterialProperty prop = FindProperty(name, properties, false);
        if (prop != null)
        {
            prop.floatValue = value;
        }
    }
}
