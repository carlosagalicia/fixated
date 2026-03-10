# Engine Assembly Simulator – Mechanical Visualization in Godot

This project is a 3D mechanical simulation built with Godot that allows users to assemble and disassemble a V6 engine interactively.
The project focuses on visualizing the mechanical structure and dependencies between engine components.

Users can inspect parts, understand assembly order, and mount or remove components while the system enforces mechanical constraints.

The simulation demonstrates how complex mechanical systems can be represented through modular software architecture and interactive 3D visualization.

## Overview

- **Simulation:** Engine parts are represented as modular objects with dependency rules that control when a component can be mounted or dismounted.
- **Visualization:** Godot renders the engine in 3D and allows users to interact with individual parts using raycasting and camera controls.
- **Objective:** Create an interactive environment to explore engine structure, assembly order, and component relationships.

## Key Learning Areas

### 1. Modular System Architecture
The project uses a component-based architecture to separate responsibilities across multiple systems.
- **Controller Systems:**
  - Separation of interaction logic into specialized controllers such as PartRaycaster, HoverController, InteractionController, and CameraOrbitController.
  - Each controller manages a single responsibility, such as camera movement, interaction logic, or part detection.
- **Component-Based Part System:**
  - Engine components are represented as Part objects composed of modular subcomponents.
  - Behavior is delegated to specialized modules, including PartNodes, PartVisuals, PartGhost, PartHighlight, and PartMover.
- **Separation of Responsibilities:**
  - Part.gd acts as a coordinator that manages assembly state and rules.
  - Visual behavior, highlighting, and animation logic are delegated to dedicated modules.
- **Extensibility:**
  - New visual or interaction behaviors can be added without modifying the core Part logic.
  - The architecture allows additional engine components or mechanical systems to be integrated easily.

### 2. Mechanical Dependency Simulation
- **Assembly Constraints:**
  - Each engine component defines which parts must be mounted or removed before it can be assembled or disassembled.
  - These constraints simulate real mechanical assembly dependencies.
- **Dependency Graph Modeling:**
  - Parts store references to other components using NodePath relationships.
  - The system dynamically checks the mounted or dismounted state of dependent components.
- **Blocking Detection:**
  - When attempting to remove a part, the system identifies components that prevent disassembly.
  - Blocking components are visually highlighted to help users understand mechanical relationships.
- **State Management:**
  - Each part maintains a mounted or dismounted state that determines valid interactions.

### 3. Interactive 3D Visualization with Godot
- **Raycasting Interaction:**
  - Mouse-based raycasting detects which engine component the user is pointing at.
  - Supports interaction with both real components and ghost previews.
- **Visual Feedback Systems:**
  - Hover outlines highlight the currently selected component.
  - Temporary color highlighting shows blocking dependencies during disassembly.
  - Ghost previews indicate which parts can be mounted.
- **Camera Control System:**
  - An orbit camera allows the user to rotate around the engine and inspect parts from different angles.
  - The camera can focus on specific components to inspect them closely.
- **Animated Assembly and Disassembly:**
  - Tween animations move parts smoothly between mounted and dismounted positions.
  - This provides a clear visual representation of the assembly process.

## Languages and Tools Used

### Godot Engine
Primary engine used for simulation and visualization.

#### Key systems used:
- **GDScript** – main scripting language
- **Physics Raycasting** – detecting selected parts
- **Tween animations** – smooth mount/dismount movement

### 3D Assets
The engine model used in this simulation was created by Blendoriano

Asset link: [https://sketchfab.com/3d-models/v6-car-engine-with-engine-morethem-7309cf5e6b07435c962f954513ca170e ](https://sketchfab.com/3d-models/v6-car-engine-with-engine-morethem-7309cf5e6b07435c962f954513ca170e)

The model was adapted for interactive assembly inside the Godot scene.

## Project Structure
```bash
project/
│
├── main/
│   ├── Main.tscn
│   └── Main.gd
│
├── controllers/
│   ├── CameraOrbitController.gd
│   ├── HoverController.gd
│   ├── InteractionController.gd
│   └── PartRaycaster.gd
│
├── parts/
│   ├── Part.gd
│   ├── PartNodes.gd
│   ├── PartVisuals.gd
│   ├── PartGhost.gd
│   ├── PartHighlight.gd
│   └── PartMover.gd
│
├── scenes/
│   └── EngineModel.tscn
│
└── assets/
    └── engine_models
```

## Installation and Usage

### Requirements
- Godot 4.x
- A computer capable of running 3D scenes in Godot.

### Instructions

1. **Clone the repository:**
```bash
    git clone https://github.com/user/engine-assembly-simulator.git
   ```
2. **Open the project in Godot.**
3. **Run the main scene:**
  ```bash
  Main.tscn
  ```
### Interaction Controls
Mouse movement:
Hover over parts to highlight them.

Left click:
Focus the camera on a component.

Hold click:
Mount or dismount the selected part depending on the current mode.

Mode selector:
Switch between Mount and Dismount modes.

<img width="1274" height="715" alt="fixated4" src="https://github.com/user-attachments/assets/8dbab581-f3fb-42ad-9f3e-6b3d4d3c5d6a" />
