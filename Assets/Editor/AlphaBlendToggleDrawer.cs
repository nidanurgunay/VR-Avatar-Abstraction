using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class AlphaBlendToggleDrawer : MaterialPropertyDrawer
{
    public override void OnGUI(Rect position, MaterialProperty prop, string label, MaterialEditor editor)
    {
        bool current = prop.floatValue > 0.5f;

        foreach (Material mat in prop.targets)
        {
            // Force _LightingStrength to 1 if Unity failed to apply the shader default
            if (mat.HasProperty("_LightingStrength") && mat.GetFloat("_LightingStrength") == 0f)
                mat.SetFloat("_LightingStrength", 1f);
        }

        EditorGUI.BeginChangeCheck();
        bool next = EditorGUI.Toggle(position, label, current);
        if (EditorGUI.EndChangeCheck())
        {
            prop.floatValue = next ? 1f : 0f;
            foreach (Material mat in prop.targets)
                Apply(mat, next);
        }
    }

    public override float GetPropertyHeight(MaterialProperty prop, string label, MaterialEditor editor)
        => EditorGUIUtility.singleLineHeight;

    static void Apply(Material mat, bool alphaBlend)
    {
        if (alphaBlend)
        {
            mat.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
            mat.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
            mat.SetFloat("_ZWrite", 0f);
            mat.renderQueue = (int)RenderQueue.Transparent;
            mat.SetOverrideTag("RenderType", "Transparent");
            mat.EnableKeyword("_ALPHA_BLEND");
        }
        else
        {
            mat.SetFloat("_SrcBlend", (float)BlendMode.One);
            mat.SetFloat("_DstBlend", (float)BlendMode.Zero);
            mat.SetFloat("_ZWrite", 1f);
            mat.renderQueue = (int)RenderQueue.Geometry;
            mat.SetOverrideTag("RenderType", "Opaque");
            mat.DisableKeyword("_ALPHA_BLEND");
        }
    }
}
