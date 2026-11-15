# GAME ARCHITECTURE BLUEPRINT v1.0

**Project:** 2D Top-Down Medieval Sandbox / Strategy RPG  
**Engine:** Godot 4.x  
**Status:** Architecture Specification & AI Agent Development Guidelines  
**Primary Priority:** Performance → Correctness → Maintainability → Extensibility

---

# 1. PROJECT VISION

Develop a scalable, modular, performance-oriented 2D medieval sandbox game.

The initial gameplay foundation is inspired by Mount & Blade:

- Large-scale tactical battles.
- Individual soldiers and commanders.
- Army formations and tactical orders.
- Melee and ranged combat.
- Character progression and equipment.
- Campaign map with armies, factions and settlements.

Future expansions may introduce mechanics inspired by RimWorld and Crusader Kings:

- Settlement management.
- Autonomous inhabitants.
- Needs, jobs and production.
- Complex character relationships.
- Dynasties and inheritance.
- Politics and diplomacy.
- Strategic economy.
- World simulation.

The architecture must support these features without requiring fundamental rewrites.

**Do not implement speculative future features prematurely. Design boundaries that allow their future implementation.**

## 1.1 Core technical goals

1. Support battles with at least 1,000 vs 1,000 soldiers.
2. Target 60 FPS on a defined reference hardware configuration.
3. Keep gameplay simulation independent from rendering, audio and UI.
4. Keep different game modes independently manageable.
5. Avoid unnecessary Godot Node overhead for large-scale simulation.
6. Maintain clean module boundaries and explicit dependencies.
7. Support automated headless simulation tests.
8. Make performance regressions measurable.
9. Allow the visual art style to change without modifying gameplay systems.
10. Keep implementation understandable to human developers and AI coding agents.

The 60 FPS target is a performance goal, not an assumed guarantee. Establish reference hardware and measurable benchmarks before claiming success.

---

# 2. MANDATORY DEVELOPMENT PRINCIPLES

## 2.1 Architecture philosophy

Use a pragmatic combination of:

- Modular Monolith.
- Feature-First organization.
- Ports and Adapters.
- Data-Oriented Design for performance-critical simulation.
- ECS-like storage where justified.
- Event-driven integration between major modules.
- Explicit dependency injection.
- Fixed-timestep simulation.
- Data-driven content definitions.

Do not blindly implement enterprise patterns or unnecessary abstractions.

Prefer simple, explicit solutions.

## 2.2 Separation of responsibilities

The project has four major architectural areas:

**Game Domain**

Defines gameplay rules, entities, invariants and outcomes.

**Simulation Runtime**

Executes movement, physics, AI, combat, navigation and time-based systems.

**Presentation**

Displays the simulation through rendering, animation, effects, sound, camera and UI.

**Infrastructure**

Provides Godot integration, persistence, asset loading, platform services and diagnostics.

Dependencies should point toward stable gameplay contracts. Domain rules must not depend on presentation or infrastructure implementations.

## 2.3 Strict rules

- Gameplay logic must not depend on Sprite2D, AnimationPlayer, AudioStreamPlayer or camera objects.
- Rendering must not directly mutate simulation state.
- Audio must not determine gameplay outcomes.
- Major modules must communicate through defined public contracts.
- Avoid global mutable state and unnecessary singleton dependencies.
- Avoid creating separate Node trees for every simulation subsystem of every soldier.
- Avoid per-unit allocations in performance-critical loops.
- Avoid unnecessary virtual dispatch, signals and GDScript/C++ boundary crossings in hot paths.
- Avoid excessive abstraction layers inside tight simulation loops.
- Do not optimize based only on assumptions.
- Do not sacrifice correctness for performance without documenting the tradeoff.

---

# 3. GAME MODES

The game uses separate modes, not a single seamless world.

## 3.1 Campaign Mode

Responsibilities:

- Global world state.
- Factions and kingdoms.
- Armies and parties.
- Strategic movement.
- Diplomacy.
- Economy.
- Character relationships.
- Strategic AI.
- Settlement ownership.
- World events.

Simulation should primarily use discrete strategic ticks and event-driven updates.

Individual battlefield physics must not run in Campaign Mode.

## 3.2 Battle Mode

Responsibilities:

- Individual units.
- Combat and damage.
- Movement and collisions.
- Formations.
- Tactical AI.
- Navigation.
- Morale.
- Projectiles.
- Battlefield presentation.

Battle Mode is the highest-performance-priority context.

Use a fixed simulation timestep.

## 3.3 Settlement Mode

Future responsibilities:

- Residents.
- Needs and moods.
- Jobs and schedules.
- Production.
- Buildings.
- Local economy.
- Local navigation.
- Autonomous behavior.

Settlement simulation must be independent of battle-specific systems.

## 3.4 GameModeCoordinator

Implement a coordinator responsible for:

- Mode transitions.
- Context creation and disposal.
- Asset preparation.
- State handoff.
- Save/load integration.
- Pause and time policies.

The coordinator must not contain combat, economy or AI rules.

### Battle transition

1. Campaign requests a battle.
2. Coordinator creates a BattleSetup snapshot.
3. Battle Context initializes.
4. Battle simulation runs.
5. Battle produces a BattleResult.
6. Coordinator applies the result to Campaign through its public API.
7. Battle Context and temporary resources are released.

Permanent characters retain stable CharacterIds.

Temporary battlefield entities use separate UnitIds.

A mapping between permanent and temporary identities must be maintained where needed.

---

# 4. PROJECT STRUCTURE

Recommended logical structure:

```text
game/
├── apps/
│   └── godot/
│       ├── scenes/
│       │   ├── campaign/
│       │   ├── battle/
│       │   └── settlement/
│       ├── presentation/
│       │   ├── rendering/
│       │   ├── animation/
│       │   ├── effects/
│       │   ├── audio/
│       │   ├── camera/
│       │   └── ui/
│       ├── input/
│       └── assets/
│
├── core/
│   ├── battle/
│   ├── campaign/
│   ├── settlement/
│   ├── characters/
│   ├── factions/
│   ├── economy/
│   └── shared/
│
├── runtime/
│   ├── simulation/
│   ├── spatial/
│   ├── navigation/
│   └── scheduling/
│
├── adapters/
│   ├── godot/
│   └── persistence/
│
├── content/
│   ├── units/
│   ├── weapons/
│   ├── animations/
│   ├── appearances/
│   ├── audio/
│   ├── factions/
│   └── buildings/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── scenarios/
│   └── performance/
│
└── docs/
    ├── architecture/
    ├── decisions/
    └── benchmarks/
```

This is a target logical structure.

Do not reorganize the entire repository without first auditing the existing codebase.

Prefer incremental migration.

---

# 5. MODULE DESIGN

Use Feature-First modules.

Example:

```text
core/battle/
├── api/
│   ├── commands/
│   ├── queries/
│   └── events/
├── domain/
│   ├── rules/
│   └── models/
├── application/
├── simulation/
│   ├── storage/
│   ├── systems/
│   └── ai/
└── presentation_contract/
```

Each major module must have a clearly defined public API.

Internal implementations must not be accessed directly by unrelated modules.

## 5.1 Communication patterns

Use three primary mechanisms:

**Commands**

Express an intention to change game state.

Examples:

- MoveFormation
- AttackTarget
- StartBattle
- EquipWeapon

**Queries / Snapshots**

Expose state without allowing uncontrolled mutation.

Examples:

- GetArmyComposition
- GetCharacterDetails
- BattleRenderSnapshot

**Events**

Describe facts that already occurred.

Examples:

- UnitDied
- BattleFinished
- SettlementCaptured
- CharacterInjured

Use synchronous direct calls inside performance-critical systems where appropriate.

Do not route every movement or collision through a global event bus.

## 5.2 Dependency rules

- Battle does not directly manipulate Campaign internals.
- Campaign does not access Battle physics internals.
- Settlement does not depend on Battle.
- Presentation depends on public simulation contracts.
- Simulation does not depend on Presentation.
- Infrastructure implements contracts required by the application.

Use a composition root to assemble dependencies.

Avoid introducing a general-purpose dependency injection framework unless genuinely necessary.

---

# 6. SIMULATION CORE

The simulation must be independently executable without the Godot scene tree.

## 6.1 Data-Oriented Design

Use compact data storage for large populations of battlefield units.

Prefer Structure of Arrays for hot data where benchmarks justify it.

Example:

```cpp
struct UnitStorage {
    std::vector<Vector2> positions;
    std::vector<Vector2> velocities;

    std::vector<float> health;
    std::vector<float> movement_speed;

    std::vector<UnitId> targets;
    std::vector<FormationId> formations;

    std::vector<uint8_t> states;
};
```

This is conceptual. The actual implementation must define:

- Stable entity handles.
- Generation counters or equivalent stale-ID protection.
- Entity creation and destruction.
- Dense index mapping.
- Component ownership.
- Storage growth policies.
- State invariants.

Avoid forcing every gameplay entity into one universal ECS.

Use domain models for complex strategic entities where appropriate.

## 6.2 System responsibilities

Create focused simulation systems:

- MovementSystem
- CollisionSystem
- SpatialGridSystem
- NavigationSystem
- CombatSystem
- ProjectileSystem
- MoraleSystem
- FormationSystem
- AIScheduler
- TargetSelectionSystem

Each system must explicitly document:

- Input data.
- Output data.
- Data it mutates.
- Execution frequency.
- Dependencies.
- Thread-safety assumptions.

---

# 7. PHYSICS AND MOVEMENT

Do not assume that thousands of CharacterBody2D instances are the correct solution.

Evaluate a custom lightweight crowd simulation for ordinary battlefield soldiers.

## 7.1 Spatial partitioning

Implement a spatial hash grid or uniform grid.

Use it for:

- Nearby-unit queries.
- Target acquisition.
- Local avoidance.
- Collision candidates.
- Area-of-effect queries.

Avoid global all-to-all unit searches.

The grid must support:

- Efficient updates.
- Reusable memory.
- Configurable cell size.
- Deterministic query ordering where required.
- Efficient handling of dense crowds.

Measure worst-case performance when many units occupy a small area.

## 7.2 Movement pipeline

Recommended stages:

1. Read movement intent.
2. Determine desired velocity.
3. Apply formation constraints.
4. Compute local avoidance.
5. Apply acceleration and speed limits.
6. Integrate movement.
7. Resolve static obstacles and unit contacts.
8. Publish final positions.

The exact ordering must be validated for stability and gameplay behavior.

## 7.3 Collision strategy

Separate:

- Unit-to-unit collisions.
- Unit-to-terrain collisions.
- Projectile collisions.
- Melee attack hit detection.

Do not use one expensive general-purpose collision mechanism for everything.

For crowded formations, investigate:

- Circle-based collision primitives.
- Separation steering.
- Position correction.
- Iterative contact resolution.
- Formation-aware movement.
- Density-based movement constraints.

Avoid excessive jitter, overlapping and deadlocks.

Preserve gameplay requirements such as blocking, encirclement, cavalry charges and formation pressure.

Do not allow units to pass through one another merely to improve benchmarks unless explicitly approved.

---

# 8. NAVIGATION

Use hierarchical navigation.

## 8.1 Global navigation

Calculate paths for:

- Formations.
- Squads.
- Commanders.
- Important individual agents where necessary.

Possible technologies:

- A*
- Navigation meshes.
- Flow fields.

Choose based on map geometry and measured performance.

## 8.2 Local navigation

Individual soldiers follow formation goals and use local steering.

Avoid frequent full-path recalculations for every soldier.

Path recalculation should generally be triggered by relevant changes, not performed unconditionally every frame.

---

# 9. ARTIFICIAL INTELLIGENCE

Use Hierarchical AI.

## 9.1 Commander AI

Responsibilities:

- Strategic battle decisions.
- Attack and retreat orders.
- Flanking.
- Reserve management.
- Formation assignments.
- Tactical positioning.

Utility AI is a preferred initial approach.

## 9.2 Formation AI

Responsibilities:

- Formation shape.
- Formation positioning.
- Group movement.
- Maintaining cohesion.
- Tactical engagement.
- Reorganization.

Avoid giving every soldier independent strategic planning.

## 9.3 Individual AI

Responsibilities:

- Local target selection.
- Attack decisions.
- Blocking.
- Dodging where applicable.
- Short-range repositioning.
- Reaction to morale and injuries.

Preferred approach:

- Finite State Machines for execution states.
- Utility scoring for decisions.
- Data-driven parameters.

Avoid expensive full behavior-tree evaluations every frame for every unit.

## 9.4 AI scheduling

Different systems should update at different frequencies.

Initial tuning candidates:

| System | Frequency |
|---|---|
| Movement | 30–60 Hz |
| Combat | 30–60 Hz |
| Local avoidance | 15–30 Hz |
| Individual AI | 5–10 Hz |
| Target acquisition | 2–5 Hz |
| Formation AI | 2–5 Hz |
| Commander AI | 1–2 Hz |

These are starting values, not mandatory final settings.

Use staggered updates to distribute expensive AI work across ticks.

Time-critical combat reactions may require more frequent processing.

---

# 10. FIXED TIMESTEP AND SCHEDULING

Use a fixed simulation timestep independent of rendering FPS.

The simulation scheduler must have an explicit execution order.

Example:

```text
Apply Commands
      ↓
Update AI Decisions (when scheduled)
      ↓
Update Formation Goals
      ↓
Update Movement Intent
      ↓
Build / Update Spatial Data
      ↓
Movement and Collision
      ↓
Combat and Projectiles
      ↓
Health, Morale and Death
      ↓
Commit State Changes
      ↓
Publish Events and Snapshot
```

The final ordering must account for spatial-grid freshness, projectile timing, attack windows and collision dependencies.

Rendering must not control simulation timing.

Use interpolation between simulation states when needed.

Avoid unbounded simulation catch-up loops that can cause a spiral of death.

---

# 11. MULTITHREADING

Do not introduce multithreading before establishing an efficient and measurable single-threaded baseline.

When profiling demonstrates a need, use job-based parallelism.

Suitable candidates:

- Independent AI scoring.
- Spatial queries.
- Desired-velocity calculation.
- Batch animation calculations.
- Read-only simulation analysis.

Requirements:

- Explicit read/write ownership.
- No unsynchronized shared-state mutation.
- No unsafe access to the Godot scene tree from worker threads.
- Controlled result-commit phases.
- Repeatable tests.
- Profiling of scheduling overhead.

Prefer coarse-grained batches over thousands of tiny jobs.

---

# 12. RENDERING ARCHITECTURE

Rendering must be independent from gameplay simulation.

## 12.1 Rendering data flow

```text
Simulation Core
      ↓
Render Snapshot
      ↓
Visual Resolver
      ↓
Visibility / Culling
      ↓
Animation Sampling
      ↓
Render Grouping / Sorting
      ↓
Godot Rendering
      ↓
GPU
```

## 12.2 Render snapshots

Expose compact visual data:

```cpp
struct UnitRenderState {
    UnitId id;
    Vector2 position;
    float rotation;

    AppearanceId appearance;
    AnimationId animation;
    float animation_progress;
};
```

Do not copy complete character objects into rendering snapshots.

Static appearance information should be resolved or cached separately.

Snapshots must have clear ownership and lifetime rules.

If simulation and rendering run on separate threads, use safely published immutable snapshots or an equivalent synchronization strategy.

## 12.3 Rendering strategies

Support replaceable rendering implementations:

- Node-based rendering for prototypes and special characters.
- Batched rendering for mass units.
- MultiMeshInstance2D where appropriate.
- Custom CanvasItem drawing where benchmarks justify it.

Do not assume MultiMesh is always faster.

Benchmark:

- CPU rendering preparation.
- GPU frame time.
- Draw calls.
- CanvasItem count.
- Texture switches.
- Sorting cost.
- Memory consumption.

## 12.4 Top-down camera

The game uses a top-down 2D camera.

World simulation uses continuous XY coordinates and angles.

The visual system may quantize directions into 8 or 16 animation directions.

Do not quantize simulation physics to sprite directions.

Use explicit rendering layers for terrain, objects, units, projectiles, effects and overlays.

Do not create unnecessary CanvasLayer instances.

Y-sorting should be enabled only where visually required.

---

# 13. ART STYLE INDEPENDENCE

The current art style is Pixel Art, but the project may later use illustrated 2D graphics.

Therefore:

- Gameplay code must not reference specific textures.
- Gameplay entities must use stable appearance identifiers.
- Animation intentions must be independent of animation files.
- Asset resolution must be data-driven.
- Pixel-specific scaling and filtering must remain in presentation configuration.

Do not build two complete rendering pipelines prematurely.

Implement one working visual style while preserving replaceable boundaries.

---

# 14. ANIMATION ARCHITECTURE

Separate gameplay actions from visual animations.

Example:

```text
Combat Action
      ↓
Animation Intent
      ↓
Animation Resolver
      ↓
Animation Definition
      ↓
Animation Sampler
      ↓
Renderer
```

## 14.1 Animation intent

Represent:

- Action.
- Weapon class.
- Facing direction.
- Stance.
- Action progress.
- Optional visual variant.

## 14.2 Gameplay authority

Combat timing and hit detection belong to the simulation.

Animation playback must not independently determine damage.

Visual events such as sword trails and dust may be triggered by animation metadata.

## 14.3 Equipment rendering

Support layered appearance definitions:

- Body.
- Armor.
- Helmet.
- Weapon.
- Shield.
- Faction colors.

For mass units, evaluate:

- Cached appearance combinations.
- Sprite atlases.
- Batched equipment layers.
- Palette shaders.
- Reduced visual detail at distance.

Avoid requiring numerous Sprite2D nodes per ordinary soldier.

---

# 15. VISUAL EFFECTS

Create a VFXDirector responsible for:

- Effect spawning.
- Effect lifetime.
- Pooling.
- Priority.
- Visibility.
- Quality settings.
- Maximum concurrent effects.

Examples:

- Blood.
- Sparks.
- Dust.
- Fire.
- Smoke.
- Projectile trails.
- Impact effects.

VFX must never be authoritative for gameplay outcomes.

Support configurable effect budgets.

Prefer reusing existing Godot particle and rendering capabilities rather than implementing a custom particle engine without justification.

---

# 16. AUDIO ARCHITECTURE

Create an AudioDirector independent from simulation logic.

## 16.1 Audio flow

```text
Gameplay Events
      ↓
Audio Requests
      ↓
Audio Director
      ↓
Priority / Distance / Voice Limits
      ↓
Sound Selection
      ↓
Godot AudioServer
```

## 16.2 Responsibilities

- Positional audio.
- Distance attenuation.
- Sound prioritization.
- Voice limiting.
- Audio pooling.
- Sound variation.
- Aggregation of repetitive mass-battle sounds.
- Mixing.
- Quality settings.

Do not play a separate audible sound for every soldier action when thousands of similar events occur simultaneously.

## 16.3 Audio buses

Recommended layout:

```text
Master
├── Music
├── SFX
│   ├── Combat
│   ├── Movement
│   ├── Environment
│   └── UI
├── Ambience
└── Voice
```

## 16.4 MusicDirector

Handle music states independently:

- Exploration.
- Battle preparation.
- Combat.
- Victory.
- Defeat.
- Settlement ambience.

Transitions should be controlled by presentation state derived from gameplay, not by individual combat systems directly.

---

# 17. ASSET AND CONTENT PIPELINE

Use a Content Registry with stable IDs.

Separate:

**Gameplay Definitions**

- Unit statistics.
- Weapons.
- Armor.
- Abilities.
- Traits.
- Combat rules.

**Visual Definitions**

- Appearance.
- Animation sets.
- Sprite atlases.
- Materials.
- Effects.

**Audio Definitions**

- Sound events.
- Variations.
- Audio categories.
- Music states.

Avoid hardcoded resource paths in gameplay systems.

## 17.1 Loading strategy

- Shared assets: loaded when required by the application.
- Mode-specific assets: loaded during mode preparation.
- Dynamic assets: loaded on demand where useful.

Release mode-specific resources when no longer referenced.

Avoid runtime resource loading in performance-critical loops.

## 17.2 Data validation

Validate content definitions for:

- Missing references.
- Duplicate identifiers.
- Invalid values.
- Missing animations.
- Invalid equipment combinations.
- Unsupported asset formats.

Provide clear error messages.

---

# 18. PERSISTENCE

Do not use the Godot scene tree as the primary authoritative save format.

Use versioned domain-state serialization.

Save data should include:

- Schema version.
- Campaign state.
- Characters.
- Factions.
- Settlements.
- Economy.
- Active mode state when supported.
- Random generator state where required.

Support migrations between save schema versions.

Do not serialize rendering caches, temporary audio players or other rebuildable presentation state as authoritative gameplay data.

---

# 19. TESTING

The simulation core must support headless execution.

## 19.1 Unit tests

Test:

- Damage formulas.
- Morale rules.
- Movement integration.
- Collision handling.
- Entity lifecycle.
- Equipment modifiers.
- AI scoring.

## 19.2 Integration tests

Test:

- Commands and state changes.
- Combat and health.
- Formation and navigation.
- Battle-to-Campaign handoff.
- Save/load correctness.

## 19.3 Scenario tests

Create reproducible scenarios:

- 100 vs 100.
- 500 vs 500.
- 1,000 vs 1,000.
- Dense infantry collision.
- Cavalry charge.
- Ranged combat.
- Obstacle navigation.
- Large formation movement.

Use fixed random seeds where possible.

## 19.4 Performance benchmarks

Record:

- Average simulation tick time.
- p50, p95 and p99 tick time.
- Rendering frame time.
- CPU and GPU utilization.
- Memory usage.
- Spatial query counts.
- Collision candidate counts.
- AI update counts.
- Draw calls.
- Active audio voices.

Track performance changes against previous baselines.

Never claim an optimization succeeded solely because an internal operation count decreased.

---

# 20. PERFORMANCE REQUIREMENTS

Current known issue:

A battle with approximately 1,000 vs 1,000 soldiers has previously produced approximately 3–5 FPS.

This must be investigated with profiling.

## 20.1 Mandatory baseline audit

Before major optimization:

1. Inspect existing unit implementation.
2. Identify physics node usage.
3. Identify navigation agent usage.
4. Count active Nodes and CanvasItems.
5. Profile AI and combat loops.
6. Profile rendering.
7. Profile collision processing.
8. Profile pathfinding.
9. Record actual frame-time distributions.
10. Identify the largest measured bottlenecks.

## 20.2 Isolation tests

Run comparable scenarios while selectively disabling:

- AI decisions.
- Unit-to-unit collisions.
- Navigation.
- Combat.
- Animation updates.
- VFX.
- Audio.

Keep the unit population and relevant rendering workload consistent wherever possible.

Document changes in simulation behavior that affect comparability.

## 20.3 Optimization priority

Optimize measured bottlenecks first.

Typical candidates:

- O(N²) neighbor searches.
- Excessive collision pairs.
- Per-unit pathfinding.
- Per-unit Node callbacks.
- Unnecessary allocations.
- Excessive scene-tree updates.
- Frequent resource loading.
- Redundant render-state conversion.

Do not rewrite the entire engine or move everything to C++ without evidence.

---

# 21. LANGUAGE AND ENGINE STRATEGY

Use Godot and GDScript for:

- UI.
- Camera.
- Input.
- Scene orchestration.
- Presentation integration.
- Rapid gameplay prototyping.

Consider C++ GDExtension for:

- Large-scale unit storage.
- Spatial queries.
- Crowd physics.
- Combat processing.
- Performance-critical AI.
- Other benchmark-confirmed hot paths.

C# is an acceptable alternative if project constraints favor it.

Keep the native interface coarse-grained.

Prefer batch commands, batch snapshots and batch events over thousands of individual cross-language calls.

Avoid implementing a custom rendering or audio engine when Godot already provides suitable functionality.

---

# 22. CODE QUALITY RULES

## 22.1 Functions

Functions should have one clear responsibility.

Prefer short orchestration functions that delegate meaningful algorithmic stages.

Do not enforce arbitrary line limits.

Do not split straightforward code into unnecessary wrappers.

## 22.2 Classes and systems

Each class or system must have a clearly defined purpose.

Avoid:

- God objects.
- Circular dependencies.
- Excessive inheritance.
- Unnecessary interfaces.
- Global mutable managers.
- Hidden side effects.
- Duplicate business rules.

Prefer composition over deep inheritance.

## 22.3 Naming

Use consistent names that reflect domain meaning.

Examples:

- BattleSimulation
- FormationController
- SpatialGrid
- CombatResolver
- UnitStorage
- BattleRenderSnapshot
- AudioDirector

Avoid ambiguous names such as:

- Manager2
- Helper
- Utils
- DataProcessor

Generic utilities are acceptable only when their purpose is genuinely generic and clear.

## 22.4 Comments and documentation

Comments should explain:

- Why a decision exists.
- Non-obvious invariants.
- Performance tradeoffs.
- Thread-safety assumptions.
- Algorithmic constraints.

Avoid comments that merely repeat the code.

Document public contracts and significant architectural decisions.

---

# 23. IMPLEMENTATION ROADMAP

## Phase 0 — Existing Project Audit

- Inspect repository structure.
- Identify current architecture.
- Profile current performance.
- Identify technical debt.
- Identify reusable components.
- Document risks.
- Establish baseline benchmarks.

**Deliverable:** Architecture Audit + Performance Baseline.

Do not begin a major rewrite during this phase.

## Phase 1 — Simulation Boundary

- Introduce a BattleSimulation API.
- Separate gameplay state from presentation.
- Define commands, events and snapshots.
- Establish fixed timestep.
- Add headless tests.

**Deliverable:** Testable battle simulation boundary.

## Phase 2 — Unit Storage and Movement

- Introduce efficient unit storage where needed.
- Implement spatial partitioning.
- Improve movement.
- Implement scalable collision handling.
- Benchmark dense crowds.

**Deliverable:** Stable and measurable 2,000-unit movement simulation.

## Phase 3 — Combat and AI

- Separate combat resolution.
- Implement hierarchical AI.
- Introduce AI scheduling.
- Optimize target acquisition.
- Implement formation-level navigation.

**Deliverable:** Functional mass battle with measurable AI and combat costs.

## Phase 4 — Presentation Architecture

- Introduce render snapshots.
- Separate animation intentions.
- Implement a replaceable unit renderer.
- Introduce VFXDirector.
- Introduce AudioDirector.
- Implement presentation performance budgets.

**Deliverable:** Decoupled graphics and sound.

## Phase 5 — Campaign Integration

- Introduce minimal Campaign Context.
- Implement BattleSetup.
- Implement BattleResult.
- Implement mode transitions.
- Test persistent character identities.

**Deliverable:** Complete Campaign → Battle → Campaign gameplay loop.

## Phase 6 — Content and Persistence

- Introduce Content Registry.
- Separate gameplay and visual definitions.
- Implement versioned saves.
- Add content validation.
- Prepare mod-friendly data boundaries.

**Deliverable:** Data-driven and persistable game foundation.

## Phase 7 — Optimization and Hardening

- Profile complete battle scenarios.
- Optimize measured bottlenecks.
- Consider C++ migration of hot paths.
- Consider job-based parallelism.
- Add regression benchmarks.
- Improve diagnostics.

**Deliverable:** Verified performance improvements without gameplay regressions.

---

# 24. RULES FOR AI CODING AGENTS

These instructions apply to all future development tasks.

## Before implementing

1. Inspect relevant existing files.
2. Identify the responsible module.
3. Understand current dependencies.
4. Check existing interfaces and conventions.
5. Identify potential performance implications.
6. Prefer extending existing systems over duplicating functionality.
7. State assumptions when the codebase does not provide enough information.

## During implementation

1. Respect module boundaries.
2. Keep gameplay independent from presentation.
3. Keep changes scoped to the requested feature.
4. Avoid unrelated refactoring.
5. Preserve existing gameplay behavior unless changes are explicitly requested.
6. Add or update tests.
7. Avoid unnecessary allocations in hot paths.
8. Avoid adding Node-based overhead to mass-unit simulation.
9. Maintain stable public interfaces where possible.
10. Prefer readable code over clever abstractions.

## After implementation

1. Run relevant tests.
2. Check for regressions.
3. Measure performance if a hot path changed.
4. Explain important design decisions.
5. Document new public contracts.
6. Report any remaining limitations.
7. Identify follow-up work separately from completed work.

## Required task report

Every significant implementation task should conclude with:

**Changes:** What was implemented.

**Architecture:** Which modules and contracts were affected.

**Performance:** Measurements where applicable, or explicitly state that performance was not measured.

**Validation:** Tests executed and their results.

**Risks:** Known limitations or unresolved issues.

**Next Steps:** Optional future improvements.

Never claim tests passed if they were not executed.

Never claim FPS improvements without actual measurements.

---

# 25. ARCHITECTURE DECISION RECORDS

Significant decisions should be documented under:

```text
docs/decisions/
```

Examples:

```text
ADR-001-simulation-boundaries.md
ADR-002-unit-storage.md
ADR-003-spatial-grid.md
ADR-004-rendering-strategy.md
ADR-005-ai-scheduling.md
```

Each ADR should include:

- Context.
- Decision.
- Alternatives considered.
- Reasons.
- Consequences.
- Performance implications where relevant.

Avoid documenting trivial implementation choices as ADRs.

---

# 26. DEFINITION OF DONE

A task is complete when:

- The requested behavior works.
- Relevant tests pass.
- Module boundaries are respected.
- Existing behavior is preserved unless intentionally changed.
- No avoidable performance regression is introduced.
- Public contracts are documented where necessary.
- The implementation is understandable and maintainable.
- Any unverified assumptions are explicitly reported.

For performance-related tasks, completion additionally requires reproducible measurements.

---

# 27. FINAL ARCHITECTURAL DIRECTIVE

The long-term architecture must prioritize:

**Performance without sacrificing correctness.**

**Modularity without unnecessary abstraction.**

**Extensibility without premature implementation.**

**Clean code without fragmenting simple logic.**

**Godot integration without coupling gameplay to the scene tree.**

**Data-oriented simulation without forcing every domain into ECS.**

**AI-assisted development without uncontrolled rewrites.**

The immediate development priority is to stabilize and optimize the existing battle simulation before implementing advanced Campaign, Settlement, Dynasty or Political systems.

The desired result is a maintainable game architecture capable of growing from a focused 2D Mount & Blade-like prototype into a complex medieval sandbox simulation.

---

# 28. AGENT EXECUTION INSTRUCTION

When receiving this document, do not immediately refactor the entire project.

First:

1. Analyze the existing repository.
2. Compare the current implementation against this blueprint.
3. Identify which architectural components already exist.
4. Identify missing boundaries and performance bottlenecks.
5. Propose an incremental migration plan.
6. Divide the work into small, independently testable tasks.
7. Prioritize performance and correctness issues.
8. Preserve working functionality.
9. Ask for approval before destructive or large-scale architectural changes.

Treat this blueprint as a long-term architectural direction, not a requirement to implement every listed component immediately.

If an existing solution is simpler, faster and equally maintainable, preserve it and explain why.

**End of Architecture Blueprint v1.0.**