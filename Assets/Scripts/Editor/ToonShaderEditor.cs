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
                // Apply defaults immediately when toggled ON
                if (newDebugValue && !currentValue)
                {
                    ApplyDefaultValues(material, properties);
                    Debug.Log("[ToonShader] Applied debug default values to material: " + material.name);
                }
            }
            EditorGUILayout.Space(5);
        }
        
        // Draw the default inspector
        base.OnGUI(materialEditor, properties);
        
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
