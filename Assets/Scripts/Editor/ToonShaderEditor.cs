using UnityEngine;
using UnityEditor;

/// <summary>
/// Custom Material Editor for Toon Shaders with Debug Defaults functionality.
/// When "Use Debug Defaults" is enabled, all parameters are reset to optimal values.
/// </summary>
public class ToonShaderEditor : ShaderGUI
{
    // Optimal default values for VR avatar visualization
    private static class Defaults
    {
        // Base
        public static readonly Color Color = Color.white;
        public static readonly float TextureIntensity = 1.0f;
        
        // Toon shading
        public static readonly float ToonSteps = 4.0f;
        public static readonly float ToonThreshold = 0.4f;
        public static readonly float ToonSmoothness = 0.03f;
        public static readonly float ShadowStrength = 0.6f;
        
        // Outline
        public static readonly float OuterOutlineWidth = 0.005f;
        public static readonly Color OuterOutlineColor = Color.black;
        public static readonly float UseOutlineDepthOffset = 1.0f;
        public static readonly float OutlineDepthBias = 4.0f;
        
        // Inner lines
        public static readonly float EnableInnerLines = 1.0f;
        public static readonly Color InnerLineColor = Color.black;
        public static readonly float InnerLineThreshold = 0.2f;
        public static readonly float InnerLineBlur = 0.5f;
        public static readonly float InnerLineStrength = 1.0f;
        
        // Rim
        public static readonly Color RimColor = new Color(0.408f, 0.408f, 0.408f, 1.0f);
        public static readonly float RimPower = 4.0f;
        
        // Ambient
        public static readonly Color AmbientColor = new Color(0.3f, 0.3f, 0.3f, 1.0f);
        
        // Alpha
        public static readonly float EnableAlphaTest = 0.0f;
        public static readonly float AlphaCutoff = 0.07f;
        
        // Debug
        public static readonly float ShowTextureOnly = 0.0f;
    }
    
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material material = materialEditor.target as Material;

        // Find the debug toggle property
        MaterialProperty useDebugDefaults = FindProperty("_UseDebugDefaults", properties, false);

        // Draw the debug toggle prominently at the top with immediate action
        if (useDebugDefaults != null)
        {
            EditorGUILayout.Space(5);
            EditorGUI.BeginChangeCheck();
            bool currentValue = useDebugDefaults.floatValue > 0.5f;
            bool newDebugValue = EditorGUILayout.Toggle("Use Debug Defaults", currentValue);
            if (EditorGUI.EndChangeCheck())
            {
                useDebugDefaults.floatValue = newDebugValue ? 1.0f : 0.0f;
                if (newDebugValue && !currentValue)
                {
                    ApplyDefaultValues(material, properties);
                    Debug.Log("[ToonShader] Applied debug default values to material: " + material.name);
                }
            }
            EditorGUILayout.Space(5);
        }

        // Check for V9 filtering presets and handle mutual exclusivity
        MaterialProperty lightFilter = FindProperty("_UseLightFiltering", properties, false);
        MaterialProperty moderateFilter = FindProperty("_UseModerateFiltering", properties, false);
        MaterialProperty aggressiveFilter = FindProperty("_UseAggressiveFiltering", properties, false);

        if (lightFilter != null && moderateFilter != null && aggressiveFilter != null)
        {
            // Draw V9 shader with custom handling for mutually exclusive presets
            DrawV9ShaderGUI(materialEditor, properties, lightFilter, moderateFilter, aggressiveFilter);
        }
        else
        {
            // Draw default inspector for non-V9 shaders
            base.OnGUI(materialEditor, properties);
        }

        // Add a button to manually apply defaults
        EditorGUILayout.Space(10);
        if (GUILayout.Button("Apply Optimal Defaults", GUILayout.Height(30)))
        {
            ApplyDefaultValues(material, properties);
            Debug.Log("[ToonShader] Manually applied default values to material: " + material.name);
        }

        // Show current values summary
        EditorGUILayout.Space(5);
        EditorGUILayout.HelpBox(
            "Optimal VR Defaults:\n" +
            "• Toon Steps: 4, Threshold: 0.4, Shadow: 0.6\n" +
            "• Outline Width: 0.005, Depth Bias: 4.0\n" +
            "• Inner Line: Threshold 0.2, Sample Distance 0.5\n" +
            "• Rim Power: 4.0",
            MessageType.Info
        );
    }

    private void DrawV9ShaderGUI(MaterialEditor materialEditor, MaterialProperty[] properties,
        MaterialProperty lightFilter, MaterialProperty moderateFilter, MaterialProperty aggressiveFilter)
    {
        // Draw all properties except filtering presets first
        foreach (var prop in properties)
        {
            if (prop.name == "_UseLightFiltering" ||
                prop.name == "_UseModerateFiltering" ||
                prop.name == "_UseAggressiveFiltering")
                continue;

            if ((prop.flags & MaterialProperty.PropFlags.HideInInspector) == 0)
            {
                materialEditor.ShaderProperty(prop, prop.displayName);
            }
        }

        // Draw filtering presets with mutual exclusivity
        EditorGUILayout.Space(10);
        EditorGUILayout.LabelField("Filtering Presets (select one)", EditorStyles.boldLabel);

        bool lightOn = lightFilter.floatValue > 0.5f;
        bool moderateOn = moderateFilter.floatValue > 0.5f;
        bool aggressiveOn = aggressiveFilter.floatValue > 0.5f;

        // Light Filtering toggle
        EditorGUI.BeginChangeCheck();
        bool newLightOn = EditorGUILayout.Toggle("Light Filtering (V3 style)", lightOn);
        if (EditorGUI.EndChangeCheck() && newLightOn && !lightOn)
        {
            lightFilter.floatValue = 1.0f;
            moderateFilter.floatValue = 0.0f;
            aggressiveFilter.floatValue = 0.0f;
            ApplyFilteringPreset(properties, 0.8f, 0.25f, 0.125f, 0.0625f, 0.2f, 2.0f, 2f, 0.2f, 1.5f);
        }
        else if (EditorGUI.EndChangeCheck() && !newLightOn && lightOn)
        {
            lightFilter.floatValue = 0.0f;
        }

        // Moderate Filtering toggle
        EditorGUI.BeginChangeCheck();
        bool newModerateOn = EditorGUILayout.Toggle("Moderate Filtering (V4 style)", moderateOn);
        if (EditorGUI.EndChangeCheck() && newModerateOn && !moderateOn)
        {
            lightFilter.floatValue = 0.0f;
            moderateFilter.floatValue = 1.0f;
            aggressiveFilter.floatValue = 0.0f;
            ApplyFilteringPreset(properties, 1.0f, 0.3f, 0.12f, 0.05f, 0.4f, 1.6f, 3f, 0.3f, 2.0f);
        }
        else if (EditorGUI.EndChangeCheck() && !newModerateOn && moderateOn)
        {
            moderateFilter.floatValue = 0.0f;
        }

        // Aggressive Filtering toggle
        EditorGUI.BeginChangeCheck();
        bool newAggressiveOn = EditorGUILayout.Toggle("Aggressive Filtering (V5 style)", aggressiveOn);
        if (EditorGUI.EndChangeCheck() && newAggressiveOn && !aggressiveOn)
        {
            lightFilter.floatValue = 0.0f;
            moderateFilter.floatValue = 0.0f;
            aggressiveFilter.floatValue = 1.0f;
            ApplyFilteringPreset(properties, 1.2f, 0.25f, 0.125f, 0.0625f, 0.85f, 1.15f, 4f, 1.0f, 3.0f);
        }
        else if (EditorGUI.EndChangeCheck() && !newAggressiveOn && aggressiveOn)
        {
            aggressiveFilter.floatValue = 0.0f;
        }
    }

    private void ApplyFilteringPreset(MaterialProperty[] properties, float blurRadius, float centerWeight,
        float cardinalWeight, float diagonalWeight, float threshMin, float threshMax,
        float smoothPasses, float smoothTightness, float powerCurve)
    {
        SetPropertyIfExists(properties, "_BlurRadiusMultiplier", blurRadius);
        SetPropertyIfExists(properties, "_GaussianCenterWeight", centerWeight);
        SetPropertyIfExists(properties, "_GaussianCardinalWeight", cardinalWeight);
        SetPropertyIfExists(properties, "_GaussianDiagonalWeight", diagonalWeight);
        SetPropertyIfExists(properties, "_ThresholdMinMultiplier", threshMin);
        SetPropertyIfExists(properties, "_ThresholdMaxMultiplier", threshMax);
        SetPropertyIfExists(properties, "_SmoothstepPasses", smoothPasses);
        SetPropertyIfExists(properties, "_SmoothstepTightness", smoothTightness);
        SetPropertyIfExists(properties, "_PowerCurve", powerCurve);
    }
    
    private void ApplyDefaultValues(Material material, MaterialProperty[] properties)
    {
        // Apply all default values to the material
        SetPropertyIfExists(properties, "_Color", Defaults.Color);
        SetPropertyIfExists(properties, "_TextureIntensity", Defaults.TextureIntensity);
        
        SetPropertyIfExists(properties, "_ToonSteps", Defaults.ToonSteps);
        SetPropertyIfExists(properties, "_ToonThreshold", Defaults.ToonThreshold);
        SetPropertyIfExists(properties, "_ToonSmoothness", Defaults.ToonSmoothness);
        SetPropertyIfExists(properties, "_ShadowStrength", Defaults.ShadowStrength);
        
        SetPropertyIfExists(properties, "_OuterOutlineWidth", Defaults.OuterOutlineWidth);
        SetPropertyIfExists(properties, "_OuterOutlineColor", Defaults.OuterOutlineColor);
        SetPropertyIfExists(properties, "_UseOutlineDepthOffset", Defaults.UseOutlineDepthOffset);
        SetPropertyIfExists(properties, "_OutlineDepthBias", Defaults.OutlineDepthBias);
        
        SetPropertyIfExists(properties, "_EnableInnerLines", Defaults.EnableInnerLines);
        SetPropertyIfExists(properties, "_InnerLineColor", Defaults.InnerLineColor);
        SetPropertyIfExists(properties, "_InnerLineThreshold", Defaults.InnerLineThreshold);
        SetPropertyIfExists(properties, "_InnerLineBlur", Defaults.InnerLineBlur);
        SetPropertyIfExists(properties, "_InnerLineStrength", Defaults.InnerLineStrength);
        
        SetPropertyIfExists(properties, "_RimColor", Defaults.RimColor);
        SetPropertyIfExists(properties, "_RimPower", Defaults.RimPower);
        
        SetPropertyIfExists(properties, "_AmbientColor", Defaults.AmbientColor);
        
        SetPropertyIfExists(properties, "_EnableAlphaTest", Defaults.EnableAlphaTest);
        SetPropertyIfExists(properties, "_AlphaCutoff", Defaults.AlphaCutoff);
        
        SetPropertyIfExists(properties, "_ShowTextureOnly", Defaults.ShowTextureOnly);
        
        // Turn off the debug toggle after applying (so you can adjust from defaults)
        SetPropertyIfExists(properties, "_UseDebugDefaults", 0.0f);
    }
    
    private void SetPropertyIfExists(MaterialProperty[] properties, string name, float value)
    {
        MaterialProperty prop = FindProperty(name, properties, false);
        if (prop != null && prop.type == MaterialProperty.PropType.Float || prop?.type == MaterialProperty.PropType.Range)
        {
            prop.floatValue = value;
        }
    }
    
    private void SetPropertyIfExists(MaterialProperty[] properties, string name, Color value)
    {
        MaterialProperty prop = FindProperty(name, properties, false);
        if (prop != null && prop.type == MaterialProperty.PropType.Color)
        {
            prop.colorValue = value;
        }
    }
}
