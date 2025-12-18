using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;
using TMPro;

public class XRDebugLogger : MonoBehaviour
{
    [Header("References (Auto-find if empty)")]
    public Transform xrOrigin;
    public Transform cameraOffset;
    public Transform mainCamera;

    [Header("Debug Settings")]
    public bool logEveryFrame = false;
    public float logInterval = 1.0f; // Log every second if not logging every frame
    public bool showOnScreenDebug = true;
    public bool showBackground = false; // Toggle background on/off
    public float debugDisplayDistance = 2.0f; // Distance in front of camera

    private float lastLogTime = 0f;
    private string debugText = "";
    private GameObject debugCanvas;
    private TextMeshProUGUI debugTextUI;

    void Start()
    {
        // Auto-find XR components if not assigned
        if (xrOrigin == null)
        {
            var xrOriginComponent = FindObjectOfType<Unity.XR.CoreUtils.XROrigin>();
            if (xrOriginComponent != null)
            {
                xrOrigin = xrOriginComponent.transform;
                Debug.Log($"[XR Debug] Found XR Origin: {xrOrigin.name}");
            }
            else
            {
                Debug.LogWarning("[XR Debug] XR Origin not found! Looking for GameObject named 'XR Origin'");
                var found = GameObject.Find("XR Origin (XR Rig)");
                if (found == null) found = GameObject.Find("XR Origin");
                if (found != null) xrOrigin = found.transform;
            }
        }

        if (mainCamera == null)
        {
            mainCamera = Camera.main?.transform;
            if (mainCamera != null)
            {
                Debug.Log($"[XR Debug] Found Main Camera: {mainCamera.name}");
                
                // Try to find Camera Offset (parent of Main Camera)
                if (cameraOffset == null && mainCamera.parent != null)
                {
                    cameraOffset = mainCamera.parent;
                    Debug.Log($"[XR Debug] Found Camera Offset: {cameraOffset.name}");
                }
            }
        }

        // Check XR device
        CheckXRDevice();
        
        // Create VR-compatible debug display
        if (showOnScreenDebug)
        {
            CreateDebugCanvas();
        }
        
        // Initial log
        LogPositions(true);
    }

    void Update()
    {
        bool shouldLog = logEveryFrame || (Time.time - lastLogTime >= logInterval);
        
        if (shouldLog)
        {
            LogPositions(false);
            lastLogTime = Time.time;
        }

        // Update on-screen debug text
        if (showOnScreenDebug)
        {
            UpdateDebugText();
            UpdateDebugCanvasPosition();
        }
    }

    void CreateDebugCanvas()
    {
        // Create a Canvas in World Space that follows the camera
        debugCanvas = new GameObject("XR Debug Canvas");
        debugCanvas.transform.SetParent(transform);
        
        Canvas canvas = debugCanvas.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.WorldSpace;
        
        // Make it small and close to camera
        RectTransform canvasRect = debugCanvas.GetComponent<RectTransform>();
        canvasRect.sizeDelta = new Vector2(600, 400);
        canvasRect.localScale = Vector3.one * 0.002f; // Small scale for VR
        
        // Create background panel
        GameObject panel = new GameObject("Background");
        panel.transform.SetParent(debugCanvas.transform, false);
        
        UnityEngine.UI.Image bgImage = panel.AddComponent<UnityEngine.UI.Image>();
        bgImage.color = showBackground ? new Color(0, 0, 0, 0.8f) : new Color(0, 0, 0, 0f); // Transparent if disabled
        
        RectTransform panelRect = panel.GetComponent<RectTransform>();
        panelRect.anchorMin = Vector2.zero;
        panelRect.anchorMax = Vector2.one;
        panelRect.sizeDelta = Vector2.zero;
        
        // Create text
        GameObject textObj = new GameObject("Debug Text");
        textObj.transform.SetParent(panel.transform, false);
        
        debugTextUI = textObj.AddComponent<TextMeshProUGUI>();
        debugTextUI.fontSize = 18;
        debugTextUI.color = Color.green;
        debugTextUI.alignment = TextAlignmentOptions.TopLeft;
        debugTextUI.enableWordWrapping = false;
        
        RectTransform textRect = textObj.GetComponent<RectTransform>();
        textRect.anchorMin = Vector2.zero;
        textRect.anchorMax = Vector2.one;
        textRect.sizeDelta = new Vector2(-20, -20);
        textRect.anchoredPosition = Vector2.zero;
        
        Debug.Log("[XR Debug] Created VR debug canvas - you should see green text in headset!");
    }

    void UpdateDebugCanvasPosition()
    {
        if (debugCanvas == null || mainCamera == null) return;
        
        // Position canvas in front of and slightly to the left of camera
        Vector3 offset = mainCamera.forward * debugDisplayDistance + mainCamera.right * -0.5f + mainCamera.up * 0.3f;
        debugCanvas.transform.position = mainCamera.position + offset;
        
        // Face the camera
        debugCanvas.transform.LookAt(mainCamera.position);
        debugCanvas.transform.Rotate(0, 180, 0);
    }

    void CheckXRDevice()
    {
        Debug.Log("=== XR DEVICE STATUS ===");
        
        var xrDisplaySubsystems = new List<XRDisplaySubsystem>();
        SubsystemManager.GetSubsystems(xrDisplaySubsystems);
        
        if (xrDisplaySubsystems.Count > 0)
        {
            Debug.Log($"[XR Debug] XR Display active: {xrDisplaySubsystems[0].running}");
        }
        else
        {
            Debug.LogWarning("[XR Debug] No XR Display subsystem found! VR tracking may not work.");
        }

        var xrInputSubsystems = new List<XRInputSubsystem>();
        SubsystemManager.GetSubsystems(xrInputSubsystems);
        
        if (xrInputSubsystems.Count > 0)
        {
            Debug.Log($"[XR Debug] XR Input active: {xrInputSubsystems[0].running}");
        }
        else
        {
            Debug.LogWarning("[XR Debug] No XR Input subsystem found!");
        }
    }

    void LogPositions(bool isInitial)
    {
        string prefix = isInitial ? "=== INITIAL STATE ===" : "=== XR UPDATE ===";
        Debug.Log(prefix);
        Debug.Log($"[XR Debug] Time: {Time.time:F2}s | FPS: {1f / Time.deltaTime:F1}");
        
        if (xrOrigin != null)
        {
            Debug.Log($"[XR Origin] Pos: {xrOrigin.position} | Rot: {xrOrigin.eulerAngles}");
        }
        else
        {
            Debug.LogWarning("[XR Debug] XR Origin reference is NULL!");
        }

        if (cameraOffset != null)
        {
            Debug.Log($"[Camera Offset] Pos: {cameraOffset.position} | Local: {cameraOffset.localPosition} | Rot: {cameraOffset.eulerAngles}");
        }
        else
        {
            Debug.LogWarning("[XR Debug] Camera Offset reference is NULL!");
        }

        if (mainCamera != null)
        {
            Debug.Log($"[Main Camera] Pos: {mainCamera.position} | Local: {mainCamera.localPosition} | Rot: {mainCamera.eulerAngles}");
            
            // Check for both old and new TrackedPoseDriver
            var trackedPoseOld = mainCamera.GetComponent<UnityEngine.SpatialTracking.TrackedPoseDriver>();
            var trackedPoseNew = mainCamera.GetComponent<Unity.XR.CoreUtils.TrackedPoseDriver>();
            
            if (trackedPoseNew != null)
            {
                Debug.Log($"[TrackedPoseDriver] NEW Input System version found (enabled: {trackedPoseNew.enabled}) ✓");
            }
            else if (trackedPoseOld != null)
            {
                Debug.Log($"[TrackedPoseDriver] OLD Legacy version found (enabled: {trackedPoseOld.enabled}) - consider upgrading");
            }
            else
            {
                Debug.LogWarning("[XR Debug] Main Camera has NO TrackedPoseDriver!");
            }
        }
        else
        {
            Debug.LogWarning("[XR Debug] Main Camera reference is NULL!");
        }

        Debug.Log("=====================");
    }

    void UpdateDebugText()
    {
        debugText = $"=== XR DEBUG INFO ===\n";
        debugText += $"FPS: {1f / Time.deltaTime:F1}\n\n";

        if (xrOrigin != null)
        {
            debugText += $"XR Origin:\n";
            debugText += $"  Pos: {xrOrigin.position.ToString("F2")}\n";
            debugText += $"  Rot: {xrOrigin.eulerAngles.ToString("F1")}\n\n";
        }

        if (cameraOffset != null)
        {
            debugText += $"Camera Offset:\n";
            debugText += $"  World Pos: {cameraOffset.position.ToString("F2")}\n";
            debugText += $"  Local Pos: {cameraOffset.localPosition.ToString("F2")}\n";
            debugText += $"  Rot: {cameraOffset.eulerAngles.ToString("F1")}\n\n";
        }

        if (mainCamera != null)
        {
            debugText += $"Main Camera:\n";
            debugText += $"  World Pos: {mainCamera.position.ToString("F2")}\n";
            debugText += $"  Local Pos: {mainCamera.localPosition.ToString("F2")}\n";
            debugText += $"  Rot: {mainCamera.eulerAngles.ToString("F1")}\n";
        }
        
        // Update UI text if canvas exists
        if (debugTextUI != null)
        {
            debugTextUI.text = debugText;
        }
    }

    void OnDestroy()
    {
        if (debugCanvas != null)
        {
            Destroy(debugCanvas);
        }
    }
}
