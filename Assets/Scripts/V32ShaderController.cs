using UnityEngine;
using UnityEngine.UI;

public class V32ShaderController : MonoBehaviour
{
    [Header("Toggle Controls")]
    public Toggle debugDefaultsToggle;

    void Start()
    {
        if (debugDefaultsToggle != null)
            debugDefaultsToggle.onValueChanged.AddListener(SetDebugDefaults);
    }

    public void SetDebugDefaults(bool value)
    {
        // Implement debug defaults logic here
        Debug.Log("Debug Defaults: " + value);
    }
}