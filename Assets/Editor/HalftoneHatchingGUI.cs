using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class HalftoneHatchingGUI : ShaderGUI
{
    // =========================================================================
    // NORMAL DEFAULTS  (shown as hints, applied by Reset button)
    // =========================================================================
    static readonly Color DefaultBaseColor    = Color.white;
    static readonly Color DefaultInkColor     = new Color(0.05f, 0.05f, 0.10f, 1f);
    static readonly Color DefaultPaperColor   = new Color(0.95f, 0.93f, 0.88f, 1f);
    static readonly Color DefaultOutlineColor = Color.black;

    const float DefaultPatternMode    = 0f;   // Halftone
    const float DefaultHalftoneSpace  = 2f;   // WorldSpace
    const float DefaultHatchStyle     = 0f;   // Line

    static readonly (string name, float value)[] DefaultFloats =
    {
        ("_TextureInfluence",  0.5f),
        ("_HalftoneScale",     30f),
        ("_HalftoneSharpness", 10f),
        ("_HalftoneAngle",     45f),
        ("_HatchScale",        20f),
        ("_HatchAngle",        45f),
        ("_HatchThickness",    0.15f),
        ("_CrossHatchAngle",   135f),
        ("_DotSize",           0.12f),
        ("_StippleScale",      50f),
        ("_StippleDensity",    1f),
        ("_ToneLevels",        5f),
        ("_ToneBias",          0f),
        ("_OutlineWidth",      0.002f),
        ("_Alpha",             1f),
        ("_AlphaCutoff",       0.5f),
    };

    // =========================================================================
    // DEBUG DEFAULTS  ← fill these in when you're ready
    // =========================================================================
    static readonly Color DebugBaseColor    = Color.white;          // TODO
    static readonly Color DebugInkColor     = Color.black;          // TODO
    static readonly Color DebugPaperColor   = Color.white;          // TODO
    static readonly Color DebugOutlineColor = Color.black;          // TODO

    const float DebugPatternMode   = 0f;   // TODO
    const float DebugHalftoneSpace = 2f;   // TODO
    const float DebugHatchStyle    = 0f;   // TODO

    static readonly (string name, float value)[] DebugFloats =
    {
        ("_TextureInfluence",  1f),     // TODO
        ("_HalftoneScale",     30f),    // TODO
        ("_HalftoneSharpness", 10f),    // TODO
        ("_HalftoneAngle",     45f),    // TODO
        ("_HatchScale",        20f),    // TODO
        ("_HatchAngle",        45f),    // TODO
        ("_HatchThickness",    0.15f),  // TODO
        ("_CrossHatchAngle",   135f),   // TODO
        ("_DotSize",           0.12f),  // TODO
        ("_StippleScale",      50f),    // TODO
        ("_StippleDensity",    1f),     // TODO
        ("_ToneLevels",        5f),     // TODO
        ("_ToneBias",          0f),     // TODO
        ("_OutlineWidth",      0.002f), // TODO
        ("_Alpha",             1f),     // TODO
        ("_AlphaCutoff",       0.5f),   // TODO
    };

    // =========================================================================
    // Keyword tables
    // =========================================================================
    static readonly string[] PatternKeywords    = { "_PATTERNMODE_HALFTONE", "_PATTERNMODE_HATCHING", "_PATTERNMODE_STIPPLE", "_PATTERNMODE_COMBINED" };
    static readonly string[] SpaceKeywords      = { "_HALFTONESPACE_SCREENSPACE", "_HALFTONESPACE_OBJECTSPACE", "_HALFTONESPACE_WORLDSPACE" };
    static readonly string[] HatchStyleKeywords = { "_HATCHSTYLE_LINE", "_HATCHSTYLE_DOTS", "_HATCHSTYLE_COMPOSITION" };

    static readonly string[] PatternModeLabels  = { "Halftone (0)", "Hatching (1)", "Stipple (2)", "Combined (3)" };
    static readonly string[] HalftoneSpcLabels  = { "ScreenSpace (0)", "ObjectSpace (1)", "WorldSpace (2)" };
    static readonly string[] HatchStyleLabels   = { "Line (0)", "Dots (1)", "Composition (2)" };

    enum SurfaceType { Opaque, Cutout, Transparent }

    // =========================================================================
    // Styles
    // =========================================================================
    static GUIStyle _hintStyle;
    static GUIStyle HintStyle
    {
        get
        {
            if (_hintStyle != null) return _hintStyle;
            _hintStyle = new GUIStyle(EditorStyles.miniLabel)
            {
                normal    = { textColor = new Color(0.5f, 0.5f, 0.5f) },
                alignment = TextAnchor.MiddleRight,
                fontSize  = 9,
            };
            return _hintStyle;
        }
    }

    static GUIStyle _debugBoxStyle;
    static GUIStyle DebugBoxStyle
    {
        get
        {
            if (_debugBoxStyle != null) return _debugBoxStyle;
            _debugBoxStyle = new GUIStyle(EditorStyles.helpBox);
            return _debugBoxStyle;
        }
    }

    // =========================================================================
    // Inspector
    // =========================================================================
    public override void OnGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        Header("Base");
        DrawWithHint(editor, FindProp("_BaseColor",        props), "default: white");
        DrawWithHint(editor, FindProp("_BaseMap",          props), "default: none");
        DrawNormalMap(editor, props);
        DrawWithHint(editor, FindProp("_InkColor",         props), "default: (0.05, 0.05, 0.1)");
        DrawWithHint(editor, FindProp("_PaperColor",       props), "default: (0.95, 0.93, 0.88)  used at Influence=0");
        DrawWithHint(editor, FindProp("_TextureInfluence", props), "default: 0.5  (0=flat paper+ink, 1=full texture)");

        EditorGUILayout.Space(4);
        Header("Pattern Mode");
        DrawWithHint(editor, FindProp("_PatternMode", props), $"default: {PatternModeLabels[(int)DefaultPatternMode]}");

        EditorGUILayout.Space(4);
        Header("Halftone");
        DrawWithHint(editor, FindProp("_HalftoneScale",     props), "default: 30");
        DrawWithHint(editor, FindProp("_HalftoneSharpness", props), "default: 10");
        DrawWithHint(editor, FindProp("_HalftoneSpace",     props), $"default: {HalftoneSpcLabels[(int)DefaultHalftoneSpace]}");
        DrawWithHint(editor, FindProp("_HalftoneAngle",     props), "default: 45°");

        EditorGUILayout.Space(4);
        Header("Hatching");
        DrawWithHint(editor, FindProp("_HatchStyle",      props), $"default: {HatchStyleLabels[(int)DefaultHatchStyle]}");
        DrawWithHint(editor, FindProp("_HatchScale",      props), "default: 20");
        DrawWithHint(editor, FindProp("_HatchAngle",      props), "default: 45°");
        DrawWithHint(editor, FindProp("_HatchThickness",  props), "default: 0.15  (Line only)");
        DrawWithHint(editor, FindProp("_CrossHatchAngle", props), "default: 135°");
        DrawWithHint(editor, FindProp("_DotSize",         props), "default: 0.12  (Dots / Composition)");

        EditorGUILayout.Space(4);
        Header("Stipple");
        DrawWithHint(editor, FindProp("_StippleScale",   props), "default: 50");
        DrawWithHint(editor, FindProp("_StippleDensity", props), "default: 1");

        EditorGUILayout.Space(4);
        Header("Lighting Response");
        DrawWithHint(editor, FindProp("_ToneLevels", props), "default: 5");
        DrawWithHint(editor, FindProp("_ToneBias",   props), "default: 0");

        EditorGUILayout.Space(4);
        Header("Outline");
        DrawWithHint(editor, FindProp("_OutlineColor", props), "default: black");
        DrawWithHint(editor, FindProp("_OutlineWidth", props), "default: 0.002");

        EditorGUILayout.Space(4);
        Header("Surface");
        DrawSurfaceTypeGUI(editor, props);

        EditorGUILayout.Space(8);
        editor.RenderQueueField();

        EditorGUILayout.Space(4);
        EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);

        if (GUILayout.Button("Reset to Defaults", GUILayout.Height(28)))
            ApplyPreset(editor, isDebug: false);
    }

    // =========================================================================
    // Debug GUI
    // =========================================================================
    static void DrawDebugGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        Material mat = (Material)editor.target;
        bool debugOn = mat.IsKeywordEnabled("_DEBUG_ON");

        EditorGUI.BeginChangeCheck();
        bool newDebugOn = EditorGUILayout.Toggle("Enable Debug Values", debugOn);
        if (EditorGUI.EndChangeCheck() && newDebugOn != debugOn)
        {
            Undo.RecordObjects(editor.targets, "Toggle Debug Values");
            foreach (Object t in editor.targets)
            {
                Material m = (Material)t;
                if (newDebugOn)
                {
                    m.EnableKeyword("_DEBUG_ON");
                    ApplyPreset(editor, isDebug: true, singleTarget: m);
                }
                else
                {
                    m.DisableKeyword("_DEBUG_ON");
                    ApplyPreset(editor, isDebug: false, singleTarget: m);
                }
            }
        }

        if (newDebugOn)
        {
            EditorGUILayout.HelpBox(
                "Debug values are active. Uncheck to restore normal defaults.",
                MessageType.Warning);
        }
    }

    // =========================================================================
    // Surface type
    // =========================================================================
    static void DrawSurfaceTypeGUI(MaterialEditor editor, MaterialProperty[] props)
    {
        Material mat = (Material)editor.target;
        SurfaceType current = DetectSurfaceType(mat);

        EditorGUI.BeginChangeCheck();
        SurfaceType selected = (SurfaceType)EditorGUILayout.EnumPopup("Surface Type", current);
        Rect hintRect = EditorGUILayout.GetControlRect(false, 11f);
        hintRect.x    += EditorGUIUtility.labelWidth;
        hintRect.width -= EditorGUIUtility.labelWidth;
        GUI.Label(hintRect, "default: Opaque", HintStyle);

        if (EditorGUI.EndChangeCheck())
        {
            Undo.RecordObjects(editor.targets, "Surface Type Change");
            foreach (Object t in editor.targets)
                ApplySurfaceType((Material)t, selected);
        }

        if (current == SurfaceType.Transparent || current == SurfaceType.Cutout)
            DrawWithHint(editor, FindProp("_Alpha", props), "default: 1");

        if (current == SurfaceType.Cutout)
            DrawWithHint(editor, FindProp("_AlphaCutoff", props), "default: 0.5");
    }

    static SurfaceType DetectSurfaceType(Material mat)
    {
        if (mat.IsKeywordEnabled("_ALPHATEST_ON")) return SurfaceType.Cutout;
        if (mat.GetFloat("_DstBlend") > 0)         return SurfaceType.Transparent;
        return SurfaceType.Opaque;
    }

    static void ApplySurfaceType(Material mat, SurfaceType type)
    {
        switch (type)
        {
            case SurfaceType.Opaque:
                mat.SetFloat("_SrcBlend", (float)BlendMode.One);
                mat.SetFloat("_DstBlend", (float)BlendMode.Zero);
                mat.SetFloat("_ZWrite",   1f);
                mat.DisableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.Geometry;
                mat.SetOverrideTag("RenderType", "Opaque");
                break;
            case SurfaceType.Cutout:
                mat.SetFloat("_SrcBlend", (float)BlendMode.One);
                mat.SetFloat("_DstBlend", (float)BlendMode.Zero);
                mat.SetFloat("_ZWrite",   1f);
                mat.EnableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.AlphaTest;
                mat.SetOverrideTag("RenderType", "TransparentCutout");
                break;
            case SurfaceType.Transparent:
                mat.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
                mat.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                mat.SetFloat("_ZWrite",   0f);
                mat.DisableKeyword("_ALPHATEST_ON");
                mat.renderQueue = (int)RenderQueue.Transparent;
                mat.SetOverrideTag("RenderType", "Transparent");
                break;
        }
        EditorUtility.SetDirty(mat);
    }

    // =========================================================================
    // Apply preset (normal or debug) — optionally to a single material
    // =========================================================================
    static void ApplyPreset(MaterialEditor editor, bool isDebug, Material singleTarget = null)
    {
        var targets = singleTarget != null
            ? new Object[] { singleTarget }
            : editor.targets;

        if (singleTarget == null)
            Undo.RecordObjects(targets, isDebug ? "Apply Debug Values" : "Reset to Defaults");

        var floats  = isDebug ? DebugFloats  : DefaultFloats;
        var inkCol  = isDebug ? DebugInkColor     : DefaultInkColor;
        var paperCol= isDebug ? DebugPaperColor   : DefaultPaperColor;
        var baseCol = isDebug ? DebugBaseColor     : DefaultBaseColor;
        var outCol  = isDebug ? DebugOutlineColor  : DefaultOutlineColor;
        var patMode = isDebug ? DebugPatternMode   : DefaultPatternMode;
        var hSpace  = isDebug ? DebugHalftoneSpace : DefaultHalftoneSpace;
        var hStyle  = isDebug ? DebugHatchStyle    : DefaultHatchStyle;

        foreach (Object t in targets)
        {
            Material mat = (Material)t;

            SetColor(mat, "_BaseColor",    baseCol);
            SetColor(mat, "_InkColor",     inkCol);
            SetColor(mat, "_PaperColor",   paperCol);
            SetColor(mat, "_OutlineColor", outCol);

            foreach (var (name, value) in floats)
                SetFloat(mat, name, value);

            SetKeywordEnum(mat, "_PatternMode",   patMode, PatternKeywords);
            SetKeywordEnum(mat, "_HalftoneSpace", hSpace,  SpaceKeywords);
            SetKeywordEnum(mat, "_HatchStyle",    hStyle,  HatchStyleKeywords);

            if (!isDebug)
            {
                if (mat.HasProperty("_BaseMap"))
                    mat.SetTexture("_BaseMap", null);
                ApplySurfaceType(mat, SurfaceType.Opaque);
            }

            EditorUtility.SetDirty(mat);
        }
    }

    // =========================================================================
    // Draw helpers
    // =========================================================================
    static void DrawNormalMap(MaterialEditor editor, MaterialProperty[] props)
    {
        var bumpMap   = FindProp("_BumpMap",   props);
        var bumpScale = FindProp("_BumpScale", props);
        if (bumpMap == null || bumpScale == null) return;

        EditorGUI.BeginChangeCheck();
        DrawWithHint(editor, bumpMap,   "default: none  (assigns normal map texture)");
        DrawWithHint(editor, bumpScale, "default: 1.0  (only active when map is assigned)");

        if (EditorGUI.EndChangeCheck())
        {
            foreach (Object t in editor.targets)
            {
                Material mat = (Material)t;
                if (mat.GetTexture("_BumpMap") != null)
                    mat.EnableKeyword("_NORMALMAP");
                else
                    mat.DisableKeyword("_NORMALMAP");
                EditorUtility.SetDirty(mat);
            }
        }
    }

    static void DrawWithHint(MaterialEditor editor, MaterialProperty prop, string hint)
    {
        if (prop == null) return;
        editor.ShaderProperty(prop, prop.displayName);
        Rect hintRect = EditorGUILayout.GetControlRect(false, 11f);
        hintRect.x    += EditorGUIUtility.labelWidth;
        hintRect.width -= EditorGUIUtility.labelWidth;
        GUI.Label(hintRect, hint, HintStyle);
    }

    static void Header(string title) =>
        EditorGUILayout.LabelField(title, EditorStyles.boldLabel);

    static MaterialProperty FindProp(string name, MaterialProperty[] props) =>
        FindProperty(name, props, false);

    // =========================================================================
    // Low-level setters
    // =========================================================================
    static void SetFloat(Material mat, string name, float value)
    {
        if (mat.HasProperty(name)) mat.SetFloat(name, value);
    }

    static void SetColor(Material mat, string name, Color value)
    {
        if (mat.HasProperty(name)) mat.SetColor(name, value);
    }

    static void SetKeywordEnum(Material mat, string floatName, float index, string[] keywords)
    {
        if (!mat.HasProperty(floatName)) return;
        mat.SetFloat(floatName, index);
        for (int i = 0; i < keywords.Length; i++)
        {
            if (i == (int)index) mat.EnableKeyword(keywords[i]);
            else                 mat.DisableKeyword(keywords[i]);
        }
    }
}
