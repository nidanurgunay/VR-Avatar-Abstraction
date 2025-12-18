using UnityEngine;

/// <summary>
/// Simple XR setup validator - shows warnings if XR Origin is misconfigured
/// Add this to XR Origin to verify it's set up correctly
/// </summary>
public class SimpleXRCheck : MonoBehaviour
{
    void Start()
    {
        Debug.Log("====== XR SETUP CHECK ======");
        
        // Check if this is on XR Origin
        if (!gameObject.name.Contains("XR Origin") && !gameObject.name.Contains("XR Rig"))
        {
            Debug.LogWarning($"[XR Check] This script should be on XR Origin, but it's on '{gameObject.name}'");
        }

        // XR Origin should be at root level (no parent)
        if (transform.parent != null)
        {
            Debug.LogError($"[XR Check] ❌ PROBLEM FOUND: XR Origin has a parent '{transform.parent.name}'!");
            Debug.LogError("[XR Check] XR Origin MUST be at root level (no parent) or the world will rotate with your head!");
            Debug.LogError("[XR Check] FIX: Drag XR Origin to root level in Hierarchy");
        }
        else
        {
            Debug.Log("[XR Check] ✓ XR Origin is at root level (correct)");
        }

        // Check for Camera
        Camera cam = GetComponentInChildren<Camera>();
        if (cam == null)
        {
            Debug.LogError("[XR Check] ❌ No Camera found in XR Origin children!");
        }
        else
        {
            Debug.Log($"[XR Check] ✓ Found camera: {cam.name}");
            
            // Check for TrackedPoseDriver
            var trackedPose = cam.GetComponent<UnityEngine.SpatialTracking.TrackedPoseDriver>();
            if (trackedPose == null)
            {
                Debug.LogError($"[XR Check] ❌ Camera '{cam.name}' has NO TrackedPoseDriver!");
                Debug.LogError("[XR Check] FIX: Add TrackedPoseDriver component to Main Camera");
            }
            else
            {
                Debug.Log($"[XR Check] ✓ TrackedPoseDriver found (enabled: {trackedPose.enabled})");
            }
        }

        Debug.Log($"[XR Check] XR Origin Position: {transform.position}");
        Debug.Log($"[XR Check] XR Origin Rotation: {transform.eulerAngles}");
        Debug.Log("=============================");
    }

    void Update()
    {
        // Check if XR Origin is accidentally rotating
        if (transform.eulerAngles.magnitude > 1f)
        {
            Debug.LogWarning($"[XR Check] ⚠️ XR Origin is rotating! Angles: {transform.eulerAngles}");
            Debug.LogWarning("[XR Check] XR Origin should NEVER rotate - check for scripts moving it");
        }
    }
}
