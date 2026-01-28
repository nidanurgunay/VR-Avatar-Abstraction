using UnityEngine;
using TMPro;

public class ShaderValueDisplay : MonoBehaviour
{
    [Header("Material to Inspect")]
    public Material targetMaterial;

    [Header("Value Labels")]
    public TMP_Text innerLineThresholdLabel;
    public TMP_Text innerLineBlurLabel;
    public TMP_Text innerLineStrengthLabel;
    public TMP_Text blurRadiusLabel;
    public TMP_Text centerWeightLabel;
    public TMP_Text cardinalWeightLabel;
    public TMP_Text diagonalWeightLabel;
    public TMP_Text thresholdMinLabel;
    public TMP_Text thresholdMaxLabel;
    public TMP_Text smoothstepPassesLabel;
    public TMP_Text smoothstepTightnessLabel;
    public TMP_Text powerCurveLabel;
    public TMP_Text normalEdgeThresholdLabel;
    public TMP_Text normalEdgeStrengthLabel;
    public TMP_Text normalEdgeSmoothnessLabel;
    public TMP_Text fresnelEdgeThresholdLabel;
    public TMP_Text fresnelEdgeStrengthLabel;
    public TMP_Text debugViewLabel;

    void Update()
    {
        if (targetMaterial == null) return;
        if (innerLineThresholdLabel != null)
            innerLineThresholdLabel.text = targetMaterial.GetFloat("_InnerLineThreshold").ToString("F3");
        if (innerLineBlurLabel != null)
            innerLineBlurLabel.text = targetMaterial.GetFloat("_InnerLineBlur").ToString("F3");
        if (innerLineStrengthLabel != null)
            innerLineStrengthLabel.text = targetMaterial.GetFloat("_InnerLineStrength").ToString("F3");
        if (blurRadiusLabel != null)
            blurRadiusLabel.text = targetMaterial.GetFloat("_BlurRadiusMultiplier").ToString("F3");
        if (centerWeightLabel != null)
            centerWeightLabel.text = targetMaterial.GetFloat("_GaussianCenterWeight").ToString("F3");
        if (cardinalWeightLabel != null)
            cardinalWeightLabel.text = targetMaterial.GetFloat("_GaussianCardinalWeight").ToString("F3");
        if (diagonalWeightLabel != null)
            diagonalWeightLabel.text = targetMaterial.GetFloat("_GaussianDiagonalWeight").ToString("F3");
        if (thresholdMinLabel != null)
            thresholdMinLabel.text = targetMaterial.GetFloat("_ThresholdMinMultiplier").ToString("F3");
        if (thresholdMaxLabel != null)
            thresholdMaxLabel.text = targetMaterial.GetFloat("_ThresholdMaxMultiplier").ToString("F3");
        if (smoothstepPassesLabel != null)
            smoothstepPassesLabel.text = targetMaterial.GetFloat("_SmoothstepPasses").ToString("F3");
        if (smoothstepTightnessLabel != null)
            smoothstepTightnessLabel.text = targetMaterial.GetFloat("_SmoothstepTightness").ToString("F3");
        if (powerCurveLabel != null)
            powerCurveLabel.text = targetMaterial.GetFloat("_PowerCurve").ToString("F3");
        if (normalEdgeThresholdLabel != null)
            normalEdgeThresholdLabel.text = targetMaterial.GetFloat("_NormalEdgeThreshold").ToString("F3");
        if (normalEdgeStrengthLabel != null)
            normalEdgeStrengthLabel.text = targetMaterial.GetFloat("_NormalEdgeStrength").ToString("F3");
        if (normalEdgeSmoothnessLabel != null)
            normalEdgeSmoothnessLabel.text = targetMaterial.GetFloat("_NormalEdgeSmoothness").ToString("F3");
        if (fresnelEdgeThresholdLabel != null)
            fresnelEdgeThresholdLabel.text = targetMaterial.GetFloat("_FresnelEdgeThreshold").ToString("F3");
        if (fresnelEdgeStrengthLabel != null)
            fresnelEdgeStrengthLabel.text = targetMaterial.GetFloat("_FresnelEdgeStrength").ToString("F3");
        if (debugViewLabel != null)
            debugViewLabel.text = targetMaterial.GetFloat("_DebugView").ToString("F0");
    }
}
