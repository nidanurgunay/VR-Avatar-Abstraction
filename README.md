# Avatar Shader Experimental Project

This Unity project features the Jade character avatar with custom shaders and animation support.

## Project Overview

This project demonstrates:
- Custom toon/cel shading effects
- Character animation system
- XR/VR integration capabilities
- Humanoid character rigging with Mixamo

## Character Setup

### Avatar: Jade
- **Location**: `Assets/Characters/Jade.fbx`
- **Rig Type**: Humanoid (Mixamo rig)
- **Features**: Fully rigged character with support for standard humanoid animations

## Animation System

The project now includes a complete animation setup for the Jade avatar:

### Quick Start with Animations

1. **Animator Controller**: `Assets/Animations/JadeAnimatorController.controller`
   - Pre-configured animator controller ready for animation clips
   
2. **Animation Folder**: `Assets/Animations/`
   - Organized location for all animation clips
   - Includes sample idle animation structure

3. **Animation Controller Script**: `Assets/Scripts/SimpleAnimationController.cs`
   - Simple script for controlling animations via keyboard
   - Can be attached to the Jade character for testing

### Adding Animations from Mixamo

Since Jade uses a Mixamo rig, you can easily add animations from [Mixamo.com](https://www.mixamo.com/):

1. Download animations as **FBX for Unity** with **Without Skin** option
2. Import FBX files into `Assets/Animations/MixamoAnimations/` folder
3. Configure import settings:
   - Rig → Animation Type: **Humanoid**
   - Rig → Avatar Definition: **Copy From Other Avatar** → Source: Jade.fbx
4. Add animation clips to the JadeAnimatorController
5. Play in Unity!

For detailed instructions, see: `Assets/Animations/README_ANIMATIONS.md`

## Shaders

The project includes custom toon shaders for a cel-shaded visual style.

- **Shader Location**: `Assets/Shaders/`
- **Materials**: `Assets/Materials/`

## Project Structure

```
Assets/
├── Animations/          # Animation clips and animator controllers
│   ├── JadeAnimatorController.controller
│   ├── Idle.anim
│   └── README_ANIMATIONS.md
├── Characters/          # 3D character models
│   └── Jade.fbx
├── Materials/           # Material assets
├── Scenes/             # Unity scenes
│   └── SampleScene.unity
├── Scripts/            # C# scripts
│   └── SimpleAnimationController.cs
├── Shaders/            # Custom shader files
├── Textures/           # Texture assets
└── Settings/           # Project settings

```

## Getting Started

1. Open the project in Unity (2022.3 or later recommended)
2. Open the main scene: `Assets/Scenes/SampleScene.unity`
3. Add the Jade character to your scene (drag from `Assets/Characters/Jade.fbx`)
4. Add the `Animator` component to Jade
5. Assign `JadeAnimatorController` to the Animator's Controller field
6. (Optional) Add `SimpleAnimationController` script for keyboard controls
7. Import animations from Mixamo following the guide in `Assets/Animations/README_ANIMATIONS.md`

## Features

### Animation System
- ✅ Humanoid avatar rig (Mixamo compatible)
- ✅ Animator controller setup
- ✅ Sample animation structure
- ✅ Animation control script
- ✅ Full documentation

### Rendering
- Custom toon/cel shading
- VR-ready rendering pipeline

## Requirements

- Unity 2022.3 LTS or later
- XR Interaction Toolkit (included)
- Universal Render Pipeline (URP) compatible

## Tips

- For best results, download animations from Mixamo with the same character proportions
- Use "Without Skin" option when downloading Mixamo animations (we already have the character)
- Keep animations organized in subfolders within `Assets/Animations/`
- Test animations in Play mode using the SimpleAnimationController (keys 1, 2, 3)

## Resources

- [Mixamo - Free Character Animations](https://www.mixamo.com/)
- [Unity Animation Documentation](https://docs.unity3d.com/Manual/AnimationSection.html)
- [Animation System Documentation](Assets/Animations/README_ANIMATIONS.md)

## License

Please ensure you comply with any licensing requirements for assets used in this project, including Mixamo animations.
