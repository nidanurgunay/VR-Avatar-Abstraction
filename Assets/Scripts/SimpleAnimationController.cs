using UnityEngine;

/// <summary>
/// Simple animation controller for the Jade avatar.
/// Attach this script to the Jade character to control animations via keyboard input.
/// This is a demo script to show how animations can be controlled programmatically.
/// </summary>
public class SimpleAnimationController : MonoBehaviour
{
    [Header("Animation Settings")]
    [Tooltip("Reference to the Animator component")]
    private Animator animator;

    [Header("Animation State Names")]
    [Tooltip("Name of the idle animation state")]
    public string idleStateName = "Idle";
    
    [Tooltip("Name of the walk animation state")]
    public string walkStateName = "Walk";
    
    [Tooltip("Name of the run animation state")]
    public string runStateName = "Run";

    [Header("Control Settings")]
    [Tooltip("Enable keyboard controls for testing")]
    public bool enableKeyboardControls = true;

    void Start()
    {
        // Get the Animator component attached to this GameObject
        animator = GetComponent<Animator>();
        
        if (animator == null)
        {
            Debug.LogError("No Animator component found on " + gameObject.name + 
                          ". Please add an Animator component and assign the JadeAnimatorController.");
        }
        else if (animator.runtimeAnimatorController == null)
        {
            Debug.LogWarning("No Animator Controller assigned to the Animator on " + gameObject.name + 
                           ". Please assign the JadeAnimatorController.");
        }
    }

    void Update()
    {
        if (!enableKeyboardControls || animator == null)
            return;

        // Demo keyboard controls
        // Press '1' for Idle
        if (Input.GetKeyDown(KeyCode.Alpha1))
        {
            PlayAnimation(idleStateName);
        }
        // Press '2' for Walk
        else if (Input.GetKeyDown(KeyCode.Alpha2))
        {
            PlayAnimation(walkStateName);
        }
        // Press '3' for Run
        else if (Input.GetKeyDown(KeyCode.Alpha3))
        {
            PlayAnimation(runStateName);
        }
    }

    /// <summary>
    /// Plays the specified animation state.
    /// </summary>
    /// <param name="stateName">Name of the animation state to play</param>
    public void PlayAnimation(string stateName)
    {
        if (animator != null && !string.IsNullOrEmpty(stateName))
        {
            // Check if the state exists before playing
            if (HasState(stateName))
            {
                animator.Play(stateName);
                Debug.Log("Playing animation: " + stateName);
            }
            else
            {
                Debug.LogWarning("Animation state '" + stateName + "' not found in Animator Controller. " +
                               "Please add this animation state to the JadeAnimatorController.");
            }
        }
    }

    /// <summary>
    /// Cross-fades to the specified animation state with a smooth transition.
    /// </summary>
    /// <param name="stateName">Name of the animation state to cross-fade to</param>
    /// <param name="transitionDuration">Duration of the cross-fade in seconds</param>
    public void CrossFadeToAnimation(string stateName, float transitionDuration = 0.2f)
    {
        if (animator != null && !string.IsNullOrEmpty(stateName))
        {
            if (HasState(stateName))
            {
                animator.CrossFade(stateName, transitionDuration);
                Debug.Log("Cross-fading to animation: " + stateName);
            }
            else
            {
                Debug.LogWarning("Animation state '" + stateName + "' not found in Animator Controller.");
            }
        }
    }

    /// <summary>
    /// Checks if the animator controller has the specified state.
    /// Note: This is a simplified check. Unity will automatically log warnings if the state doesn't exist.
    /// </summary>
    /// <param name="stateName">Name of the state to check</param>
    /// <returns>True (simplified - assumes state exists, Unity handles warnings)</returns>
    private bool HasState(string stateName)
    {
        // Simplified validation - just check that animator and controller are assigned
        // Unity's Animator.Play() will automatically log a warning if the state doesn't exist
        return animator != null && animator.runtimeAnimatorController != null;
    }

    /// <summary>
    /// Sets a float parameter in the animator.
    /// Useful for blend trees and complex animation setups.
    /// </summary>
    /// <param name="parameterName">Name of the parameter</param>
    /// <param name="value">Value to set</param>
    public void SetFloatParameter(string parameterName, float value)
    {
        if (animator != null)
        {
            animator.SetFloat(parameterName, value);
        }
    }

    /// <summary>
    /// Sets a bool parameter in the animator.
    /// </summary>
    /// <param name="parameterName">Name of the parameter</param>
    /// <param name="value">Value to set</param>
    public void SetBoolParameter(string parameterName, bool value)
    {
        if (animator != null)
        {
            animator.SetBool(parameterName, value);
        }
    }

    /// <summary>
    /// Triggers an animation trigger parameter.
    /// </summary>
    /// <param name="triggerName">Name of the trigger</param>
    public void TriggerAnimation(string triggerName)
    {
        if (animator != null)
        {
            animator.SetTrigger(triggerName);
        }
    }
}
