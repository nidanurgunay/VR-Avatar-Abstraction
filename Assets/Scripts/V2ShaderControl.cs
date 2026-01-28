using UnityEngine;
using UnityEngine.UI;

public class AvatarShaderController : MonoBehaviour
{
    [Header("Target")]
    public Renderer[] avatarRenderers; // Changed to array to handle multiple renderers

    [Header("Sliders")]
    public Slider outerOutlineSlider;
    public Slider innerLineThresholdSlider;
    public Slider innerLineBlurSlider;
    public Slider innerLineStrengthSlider;
    public Slider alphaCutoffSlider;

    Material[] runtimeMats; // Array to hold instanced materials

    void Start()
    {
        // Get all renderers if not assigned
        if (avatarRenderers == null || avatarRenderers.Length == 0)
        {
            avatarRenderers = GetComponentsInChildren<Renderer>();
        }

        // Collect all materials from all renderers
        System.Collections.Generic.List<Material> allMats = new System.Collections.Generic.List<Material>();
        foreach (Renderer rend in avatarRenderers)
        {
            foreach (Material mat in rend.materials)
            {
                allMats.Add(mat);
            }
        }

        // Instance all materials
        runtimeMats = new Material[allMats.Count];
        for (int i = 0; i < allMats.Count; i++)
        {
            runtimeMats[i] = Instantiate(allMats[i]);
        }

        // Assign back to renderers (assuming order matches)
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

        outerOutlineSlider.onValueChanged.AddListener(SetOutlineWidth);
        innerLineThresholdSlider.onValueChanged.AddListener(SetEdgeThreshold);
        innerLineBlurSlider.onValueChanged.AddListener(SetInnerLineBlur);
        innerLineStrengthSlider.onValueChanged.AddListener(SetInnerLineStrength);
        alphaCutoffSlider.onValueChanged.AddListener(SetAlphaCutoff);

        // Set slider ranges based on shader properties
        SetSliderRanges();
    }

    public void SetEdgeThreshold(float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_InnerLineThreshold", value);
        }
    }

    public void SetOutlineWidth(float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_OuterOutlineWidth", value);
        }
    }

    public void SetAlphaCutoff(float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_AlphaCutoff", value);
        }
    }

    public void SetInnerLineBlur(float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_InnerLineBlur", value);
        }
    }

    public void SetInnerLineStrength(float value)
    {
        foreach (Material mat in runtimeMats)
        {
            mat.SetFloat("_InnerLineStrength", value);
        }
    }

    private void SetSliderRanges()
    {
        if (outerOutlineSlider != null)
        {
            outerOutlineSlider.minValue = 0f;
            outerOutlineSlider.maxValue = 0.5f;
        }
        if (innerLineThresholdSlider != null)
        {
            innerLineThresholdSlider.minValue = 0.001f;
            innerLineThresholdSlider.maxValue = 0.5f;
        }
        if (innerLineBlurSlider != null)
        {
            innerLineBlurSlider.minValue = 0f;
            innerLineBlurSlider.maxValue = 10f;
        }
        if (innerLineStrengthSlider != null)
        {
            innerLineStrengthSlider.minValue = 0f;
            innerLineStrengthSlider.maxValue = 1f;
        }
        if (alphaCutoffSlider != null)
        {
            alphaCutoffSlider.minValue = 0f;
            alphaCutoffSlider.maxValue = 1f;
        }
    }
}
