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
    
    void Awake()
    {
        // Try to find any XR interactable component
        interactable = GetComponent<XRBaseInteractable>();
        
        if (interactable == null)
        {
            Debug.LogWarning("[ANIMATORSCRIPT] No XR Interactable found, adding XRSimpleInteractable");
            interactable = gameObject.AddComponent<XRSimpleInteractable>();
        }
        
        if (animator == null)
        {
            animator = GetComponent<Animator>();
        }
        
        Debug.Log($"[ANIMATORSCRIPT] Using interactable type: {interactable.GetType().Name}");
    }
    void Start()
{
    // Force animator to reset to Idle state
    if (animator != null)
    {
        // Reset all triggers
        foreach (var trigger in animationTriggers)
        {
            animator.ResetTrigger(trigger);
        }
        
        // Force play the Idle state
        animator.Play("Idle", 0, 0f);
        
        Debug.Log("[ANIMATORSCRIPT] Animator forced to Idle state on start");
    }
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