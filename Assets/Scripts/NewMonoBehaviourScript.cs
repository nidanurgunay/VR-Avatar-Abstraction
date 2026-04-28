using UnityEngine;
using UnityEngine.XR.Interaction. Toolkit;
using UnityEngine.XR. Interaction.Toolkit.Interactables;

public class VRAvatarAnimationTrigger : MonoBehaviour
{
    [Header("Animation Settings")]
    public Animator animator;
    
    [Header("Trigger Settings")]
    [Tooltip("Trigger animation on Select (point and click)")]
    public bool triggerOnSelect = true;
    
    [Tooltip("Trigger animation on Activate (button press while hovering)")]
    public bool triggerOnActivate = true;
    
    [Header("Animation Triggers")]
    public string[] animationTriggers = new string[] { 
        "Arm",
        // "Capoeira", 
         
        // "Rumba", 
        // "HipHop", 
        // "Samba"
         };
    public bool randomAnimation = true;
    
    private XRBaseInteractable interactable;
    private int currentAnimationIndex = 0;

    XRBaseInteractable EnsureInteractableOnProxy()
    {
        // Create/find a child object on Default layer so controller rays (usually Default) can hit it,
        // while the skinned mesh stays on an Avatar* layer for post-process masking.
        const string proxyName = "InteractionProxy";

        Transform proxyTransform = transform.Find(proxyName);
        if (proxyTransform == null)
        {
            var proxyGo = new GameObject(proxyName);
            proxyTransform = proxyGo.transform;
            proxyTransform.SetParent(transform, false);
            proxyGo.layer = 0; // Default
        }

        var proxy = proxyTransform.gameObject;
        if (proxy.layer != 0)
            proxy.layer = 0;

        // Ensure a collider exists on the proxy.
        var existingCollider = proxy.GetComponent<Collider>();
        if (existingCollider == null)
        {
            var box = proxy.AddComponent<BoxCollider>();
            box.isTrigger = true;

            // Size the collider to roughly the visible renderer bounds (local space approximation).
            var renderers = GetComponentsInChildren<Renderer>(true);
            var hasBounds = false;
            Bounds bounds = default;
            foreach (var r in renderers)
            {
                if (r == null) continue;
                if (!hasBounds) { bounds = r.bounds; hasBounds = true; }
                else bounds.Encapsulate(r.bounds);
            }

            if (hasBounds)
            {
                // Convert world bounds into proxy local space.
                Vector3 centerLocal = proxyTransform.InverseTransformPoint(bounds.center);
                Vector3 sizeLocal = bounds.size;
                box.center = centerLocal;
                box.size = sizeLocal;
            }
        }

        // Ensure an interactable exists on the proxy.
        var proxyInteractable = proxy.GetComponent<XRBaseInteractable>();
        if (proxyInteractable == null)
            proxyInteractable = proxy.AddComponent<XRSimpleInteractable>();

        return proxyInteractable;
    }

    void Awake()
    {
        // Prefer a proxy interactable on Default layer so XR rays can hit it even if this avatar is on an Avatar* layer.
        interactable = GetComponentInChildren<XRBaseInteractable>(true);
        
        if (interactable == null)
        {
            Debug.LogWarning("[ANIMATORSCRIPT] No XR Interactable found, creating InteractionProxy + XRSimpleInteractable");
            interactable = EnsureInteractableOnProxy();
        }
        
        if (animator == null)
        {
            animator = GetComponent<Animator>();
        }
        
        Debug.Log($"[ANIMATORSCRIPT] Using interactable type: {interactable.GetType().Name}");
    }
    void Start()
    {
        if (animator == null)
            return;

        // On device, animators can appear "stuck" due to culling or disabled state.
        animator.enabled = true;
        animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        animator.updateMode = AnimatorUpdateMode.Normal;

        if (animator.runtimeAnimatorController == null)
        {
            Debug.LogError("[ANIMATORSCRIPT] Animator has no controller assigned.");
            return;
        }

        // Reset all triggers
        foreach (var trigger in animationTriggers)
            animator.ResetTrigger(trigger);

        // Ensure a clean initial state, then enter Idle.
        animator.Rebind();
        animator.Update(0f);
        animator.Play("Idle", 0, 0f);

        Debug.Log("[ANIMATORSCRIPT] Animator initialized and forced to Idle state on start");
    }
    void OnEnable()
    {
        if (interactable == null) return;
        
        if (triggerOnSelect)
        {
            interactable.selectEntered.AddListener(OnVRSelect);
            Debug.Log("[ANIMATORSCRIPT] Listening for SELECT events");
        }
        
        if (triggerOnActivate)
        {
            interactable.activated.AddListener(OnVRActivate);
            Debug.Log("[ANIMATORSCRIPT] Listening for ACTIVATE events");
        }
        
        // Also listen for hover for debugging
        interactable.hoverEntered.AddListener(OnHoverEnter);
        interactable.hoverExited.AddListener(OnHoverExit);
    }
    
    void OnDisable()
    {
        if (interactable != null)
        {
            interactable.selectEntered.RemoveListener(OnVRSelect);
            interactable.activated. RemoveListener(OnVRActivate);
            interactable. hoverEntered.RemoveListener(OnHoverEnter);
            interactable.hoverExited.RemoveListener(OnHoverExit);
        }
    }
    
    void OnHoverEnter(HoverEnterEventArgs args)
    {
        Debug.Log("[ANIMATORSCRIPT] Avatar is being HOVERED!");
    }
    
    void OnHoverExit(HoverExitEventArgs args)
    {
        Debug.Log("[ANIMATORSCRIPT] Avatar hover ended");
    }
    
    void OnVRSelect(SelectEnterEventArgs args)
    {
        Debug.Log("[ANIMATORSCRIPT] AVATAR SELECTED! Triggering animation...");
        TriggerRandomAnimation();
    }
    
    void OnVRActivate(ActivateEventArgs args)
    {
        Debug.Log("[ANIMATORSCRIPT] AVATAR ACTIVATED! Triggering animation...");
        TriggerRandomAnimation();
    }
    
    void TriggerRandomAnimation()
    {
        if (animator == null)
        {
            Debug.LogError("[ANIMATORSCRIPT] Animator is null!");
            return;
        }
        
        if (animationTriggers.Length == 0)
        {
            Debug.LogError("[ANIMATORSCRIPT] No animation triggers defined!");
            return;
        }
        
        string triggerName;
        
        if (randomAnimation)
        {
            int randomIndex = Random.Range(0, animationTriggers.Length);
            triggerName = animationTriggers[randomIndex];
        }
        else
        {
            triggerName = animationTriggers[currentAnimationIndex];
            currentAnimationIndex = (currentAnimationIndex + 1) % animationTriggers.Length;
        }
        
        Debug.Log($"[ANIMATORSCRIPT] Setting animator trigger: {triggerName}");
        animator.SetTrigger(triggerName);
    }
    
    // For mouse click testing in editor
    void OnMouseDown()
    {
        Debug.Log("[ANIMATORSCRIPT] Mouse clicked on avatar");
        TriggerRandomAnimation();
    }
}
