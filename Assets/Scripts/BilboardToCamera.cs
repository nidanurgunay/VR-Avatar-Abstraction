using UnityEngine;

public class BillboardToCamera : MonoBehaviour
{
    void LateUpdate()
    {
        Camera cam = Camera.main;
        if (!cam) return;

        transform.forward = cam.transform.forward;
    }
}
