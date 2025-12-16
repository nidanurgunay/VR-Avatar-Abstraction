# Avatar Animation Setup Guide

This guide explains how to add and use animations with the Jade avatar character in this Unity project.

## Overview

The Jade character is a humanoid model with a Mixamo rig, which means it's compatible with a wide variety of animations from Mixamo and other sources.

## Current Setup

- **Character Model**: `Assets/Characters/Jade.fbx`
- **Animation Folder**: `Assets/Animations/`
- **Animator Controller**: `Assets/Animations/JadeAnimatorController.controller`
- **Sample Animation**: `Assets/Animations/Idle.anim` (empty placeholder)

## How to Add Animations from Mixamo

Since the Jade character uses the Mixamo rig, you can easily add animations from Mixamo:

### Step 1: Download Animations from Mixamo

1. Go to [Mixamo](https://www.mixamo.com/)
2. Log in with your Adobe account
3. Search for the animation you want (e.g., "Walking", "Running", "Jumping")
4. Select the animation and click "Download"
5. In the download settings:
   - Format: **FBX for Unity**
   - Skin: **Without Skin** (since we already have the character)
   - Frame Rate: **30 fps** (or your preference)
   - Keyframe Reduction: **None** (for better quality)

### Step 2: Import Animations into Unity

1. Create a folder for your animations if you haven't already (e.g., `Assets/Animations/MixamoAnimations/`)
2. Drag and drop the downloaded FBX files into this folder
3. Select each FBX file in the Unity Project window
4. In the Inspector, go to the **Rig** tab:
   - Animation Type: **Humanoid**
   - Avatar Definition: **Copy From Other Avatar**
   - Source: Select the Jade.fbx avatar
5. Go to the **Animation** tab:
   - Check that "Import Animation" is enabled
   - You can rename the animation clip here
6. Click **Apply**

### Step 3: Add Animations to the Animator Controller

1. Open the `JadeAnimatorController` by double-clicking it
2. In the Animator window, you can:
   - Right-click in the grid and select "Create State" → "Empty"
   - Name the new state (e.g., "Walk")
   - Select the state and in the Inspector, set the Motion field to your imported animation clip
3. Create transitions between states by right-clicking a state and selecting "Make Transition"
4. Set up parameters and conditions for transitions as needed

### Step 4: Apply the Animator to the Character

1. Select the Jade character in your scene
2. Add an **Animator** component if it doesn't have one
3. Set the **Controller** field to `JadeAnimatorController`
4. Set the **Avatar** field to the Jade avatar (should auto-populate)
5. Make sure **Apply Root Motion** is set according to your needs

## Alternative: Creating Custom Animations

You can also create custom animations in Unity:

1. Select the Jade character in the scene
2. Open the Animation window (Window → Animation → Animation)
3. Click "Create" and save a new animation clip in the Animations folder
4. Use the Animation window to keyframe properties and create your animation
5. Add the new clip to your Animator Controller

## Animation Controller Structure

The default Animator Controller includes:
- **Base Layer**: Contains the main animation states
- **Idle State**: Default state (currently empty - replace with actual idle animation)

You can expand this by adding:
- Blend trees for smooth transitions
- Layers for additive animations
- Sub-state machines for complex behavior
- Parameters for controlling animations via scripts

## Controlling Animations via Script

To control animations from C# scripts, you can use:

```csharp
// Get the Animator component
Animator animator = GetComponent<Animator>();

// Trigger an animation state
animator.Play("Walk");

// Set a parameter
animator.SetFloat("Speed", 5.0f);
animator.SetBool("IsGrounded", true);
animator.SetTrigger("Jump");

// Cross-fade to another animation
animator.CrossFade("Idle", 0.2f);
```

## Tips

1. **Performance**: Optimize animations by using animation compression in the FBX import settings
2. **Root Motion**: If your character moves in place, enable "Apply Root Motion" on the Animator
3. **Animation Events**: Add events to animations for triggering sounds, effects, or game logic
4. **Animation Layers**: Use layers for upper body animations (like waving) while keeping lower body animations (like walking)
5. **Blend Trees**: Use blend trees for smooth transitions between similar animations (like walk-to-run)

## Common Animation States to Add

Consider adding these common animations:
- Idle
- Walk
- Run
- Jump
- Fall
- Land
- Attack
- Hit/Damage
- Death
- Emotes (wave, dance, etc.)

## Troubleshooting

**Animation doesn't play:**
- Make sure the Animator component is attached to the character
- Check that the Controller is assigned
- Verify the Avatar is correctly assigned
- Ensure the animation state is set as the default or has a valid transition path

**Character is in T-pose:**
- Check that the Avatar is properly configured
- Make sure "Animation Type" is set to "Humanoid" in the FBX import settings
- Verify the rig is correctly mapped

**Animation looks wrong:**
- Ensure the source Avatar matches between the character and animation FBX files
- Check the animation import settings (especially the Avatar Definition)
- Try re-importing with different settings

## Resources

- [Unity Animation Documentation](https://docs.unity3d.com/Manual/AnimationSection.html)
- [Mixamo](https://www.mixamo.com/) - Free character animations
- [Unity Animator Controller](https://docs.unity3d.com/Manual/class-AnimatorController.html)
