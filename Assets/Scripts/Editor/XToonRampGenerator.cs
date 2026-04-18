using UnityEngine;
using UnityEditor;
using System.IO;

public class XToonRampGenerator : EditorWindow
{
    [MenuItem("Tools/XToon/Generate 2D Ramp Texture")]
    static void Open()
    {
        GetWindow<XToonRampGenerator>("XToon Ramp Generator");
    }

    int width = 256;
    int height = 8;

    // Grayscale by default — the diffuse texture provides color,
    // the ramp only controls shading intensity.
    Color shadowColor    = new Color(0.35f, 0.35f, 0.35f);
    Color midColor       = new Color(0.72f, 0.72f, 0.72f);
    Color highlightColor = new Color(1.00f, 1.00f, 1.00f);

    void OnGUI()
    {
        GUILayout.Label("2D Toon Ramp Settings", EditorStyles.boldLabel);
        EditorGUILayout.Space();

        width  = EditorGUILayout.IntField("Width (U = NdotL)", width);
        height = EditorGUILayout.IntField("Height (V = Detail)", height);
        EditorGUILayout.Space();

        shadowColor    = EditorGUILayout.ColorField("Shadow Color",    shadowColor);
        midColor       = EditorGUILayout.ColorField("Mid Tone Color",  midColor);
        highlightColor = EditorGUILayout.ColorField("Highlight Color", highlightColor);
        EditorGUILayout.Space();

        EditorGUILayout.HelpBox(
            "Keep colors GRAYSCALE if your materials have a diffuse texture.\n" +
            "The ramp only controls shading brightness — the texture provides the color.\n\n" +
            "U axis (left→right): shadow → highlight (NdotL)\n" +
            "V axis (bottom→top): abstract/flat → fully detailed",
            MessageType.Info);

        EditorGUILayout.Space();

        if (GUILayout.Button("Generate & Save to Assets/Textures/XToonRamp.png"))
            Generate();
    }

    void Generate()
    {
        Texture2D tex = new Texture2D(width, height, TextureFormat.RGBA32, false);

        for (int v = 0; v < height; v++)
        {
            // detailT: 0 = bottom (abstract) → 1 = top (detailed)
            float detailT = (float)v / Mathf.Max(height - 1, 1);

            for (int u = 0; u < width; u++)
            {
                // lightT: 0 = full shadow (left) → 1 = full highlight (right)
                float lightT = (float)u / Mathf.Max(width - 1, 1);

                // Posterize more at low detailT (abstract), smooth at high detailT (detailed)
                int steps = Mathf.RoundToInt(Mathf.Lerp(2f, 6f, detailT));
                float posterized = Mathf.Floor(lightT * steps) / steps;
                float blendedU = Mathf.Lerp(posterized, lightT, detailT);

                Color col;
                if (blendedU < 0.5f)
                    col = Color.Lerp(shadowColor, midColor, blendedU * 2f);
                else
                    col = Color.Lerp(midColor, highlightColor, (blendedU - 0.5f) * 2f);

                tex.SetPixel(u, v, col);
            }
        }

        tex.Apply();

        string dir  = Application.dataPath + "/Textures";
        string path = dir + "/XToonRamp.png";
        if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

        File.WriteAllBytes(path, tex.EncodeToPNG());
        AssetDatabase.Refresh();

        // Set import settings: no mipmaps, clamp, linear
        string assetPath = "Assets/Textures/XToonRamp.png";
        TextureImporter importer = AssetImporter.GetAtPath(assetPath) as TextureImporter;
        if (importer != null)
        {
            importer.mipmapEnabled   = false;
            importer.wrapMode        = TextureWrapMode.Clamp;
            importer.filterMode      = FilterMode.Bilinear;
            importer.sRGBTexture     = true;
            importer.SaveAndReimport();
        }

        Debug.Log("[XToon] Ramp saved to " + assetPath);
        EditorUtility.DisplayDialog("Done", "Ramp saved to Assets/Textures/XToonRamp.png\n\nAssign it to the _ToonRamp slot on all XToon materials.", "OK");
    }
}
