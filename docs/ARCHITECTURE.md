# Architecture

How the plugin is put together, and the reasoning behind the parts that aren't
obvious from the code.

## Overview

A house is **data**, not a scene graph. `HouseData` and its `FloorData` children
hold everything: which grid cells are occupied per floor, which wall edges carry
details, and every tunable geometry constant. The mesh is derived from that data
on demand and is never the source of truth.

```
EditorPlugin (house_builder.gd)
  └─ HouseEditor dock (ui/house_editor/)
       ├─ HouseProperties   material slots + geometry constants, editing HouseData
       ├─ Floors → LevelEditor (per-floor toolbar) → GridEditor (cell painting,
       │           detail placement, orphan highlighting)
       └─ Toolbar           new / open / save / export
             └─ HouseSceneBuilder.build(house) → packed as a .tscn
```

## Build pipeline

`HouseMeshBuilder.build(house)` runs the builders in a fixed order and returns a
single `ArrayMesh`:

1. `TrimBuilder.build_all` — corner posts for every floor, ground-up
2. Per floor:
   - `WallOpenings.collect` — resolve valid wall details into opening records
   - `WallBuilder.build` — siding ring (`PerforatedRing` when openings exist)
   - `WallDetailBuilder.build` — window / door / garage dressing per opening,
     plus the interior casing that frames it from the room side. Animated door
     leaves are collected here as rigs instead of being baked in
3. `FoundationBuilder.build` — foundation ring and post pads, ground floor only
4. `InteriorBuilder.build` — floor decks at every level boundary, and baseboards
5. `PorchBuilder.roof_cells(...)` — porch cells join the lowest floor's roof
   footprint, *before* the roof is built (minus any the storey above covers)
6. `RoofBuilder.build` — roofs for every floor, plus gutters and downspouts
7. `PorchBuilder.build` — deck, posts, railings, stairs, ceiling, perimeter band
8. `DormerBuilder` / `ChimneyBuilder` — roof details, querying the returned roof
   models through `RoofSurface.height_at`

`SurfaceAccumulator.commit()` then bakes one named `ArrayMesh` surface per
material slot. It is the only place meshes are baked.

Sidewalk and driveway slabs are deliberately **not** part of this mesh.
`SidewalkBuilder.build(house)` produces its own `ArrayMesh`, which
`HouseSceneBuilder` exports as a separate `SidewalkMesh` node. This keeps the
house prefab reusable when the surrounding lot changes.

## The roof subsystem

The roof is decoupled from the house data model. Everything under `mesh/roof/`
knows only about polygons and metadata — no `HouseData`, no grid cells.

```
mesh/builders/roof_builder.gd   ← the only HouseData-aware file (addon glue)
mesh/roof/
  roof_constants.gd    every numeric tolerance the subsystem uses
  roof_input.gd        RoofInput: polygon + metadata contract
  roof_model.gd        RoofModel: planes, typed edges, planned downspouts
  straight_skeleton.gd the core solver
  roof_generator.gd    orchestrates skeleton → model
  roof_gutters.gd      gutter trough + downspout layout
```

### Generation pipeline

`RoofGenerator.generate(input) -> RoofModel`:

1. **Sanitize** — weld duplicate points, normalize winding, reject slivers
2. **Offset** — miter-offset the wall outline outward by the overhang to get the
   eave polygon
3. **Skeleton** — `StraightSkeleton.compute()` over the eave polygon. Walls marked
   as gables enter as zero-weight edges: their front stays put, so the neighbouring
   roof planes extend out to the gable line
4. **Area audit** — the faces' plan areas must sum back to the eave polygon's area.
   If they don't, or the solver hit its iteration cap, the result isn't trusted and
   a flat cap is emitted instead (`RoofModel.used_fallback`). A flat cap is always
   geometrically safe; a mis-solved skeleton can self-intersect
5. **Gables** — each gable's apex and adjoining planes are read off the skeleton and
   the end is closed with a vertical siding gable, sloped rake boards, and a rake
   soffit. A wall the skeleton can't close is demoted back to a hip and the skeleton
   recomputed, one failure at a time
6. **Clip** — for multi-storey houses, remove the roof wherever an upper storey's
   walls stand
7. **Lift** — plan `(point, offset)` pairs become 3D points with meter-true UVs
8. **Classify** — shared face borders become RIDGE / HIP / VALLEY / RAKE edges; the
   clipped eave outline becomes EAVE edges
9. **Close** — fascia band at the eave line, horizontal soffit beneath it

### Why multi-storey roofs are one system

For a floor with another floor above it, `RoofBuilder` traces the floor's **entire**
footprint, not just the exposed part, and passes the upper floor's wall loops in as
`clip_regions`. The lower roof is generated as if the whole floor were roofed, then
the upper footprint is subtracted out.

The alternative — generating an independent hip roof over each exposed region — puts
a seam wherever two regions meet and produces eaves that wrap around walls that are
flush between storeys. Subtracting instead means the remaining sections butt against
the upper walls as a single connected surface.

### Gutters

Only the **lowest roofed level** gets gutters. They read as the house's eaves, and
floors are walked bottom-up, so the first floor to actually produce a roof is that
level. Because nothing above is guttered, there is never a roof in the way, and
every downspout can run straight to `house.grade_y()`.

Downspout walls come from the **house's** cells rather than `roof_cells` — a roofed
porch widens the latter, and a porch's open eave has no wall to hang a pipe on.

## The details subsystem

Details live per floor on `FloorData` and are addressed by **grid cell + edge
direction**, one detail per edge.

| Resource | What it addresses |
| --- | --- |
| `WallDetail` | WINDOW / DOOR / GARAGE_DOOR / STAIRS at `(cell, direction)`, and for the two door types a `door_mode` |
| `DormerData` | A boundary edge of its floor; sits on top of the roof |
| `ChimneyData` | An occupied cell of its floor; sits on top of the roof |
| `GableData` | An exterior wall run, marked `(cell, direction)` |

`WallDetail.NORMALS` and `endpoints()` are the single source of truth tying an edge
direction to the exact unit edge `Footprint.trace_loops` produces. The same edge seen
from its other side is `(cell + NORMALS[direction], OPPOSITE[direction])`.

Dormers and chimneys bury their bases below the roof surface rather than cutting it —
the roof is never perforated.

### Rules live in one place

Every placement and validity rule is in `DetailRules`, shared verbatim by the grid
editor (hover legality, red orphan highlighting) and by the builders (skip and warn).
One rule set means the editor can never show a placement the builder would reject.

Details are **never auto-pruned** when cells change. An orphaned detail renders red
until the user removes it, and the mesh build skips it. Silently deleting a user's
work because they erased a cell is worse than showing them a broken state.

### Porches

A roofed porch has **no roof geometry of its own**. `PorchBuilder.roof_cells()`
returns the porch cells unioned with the floor's house cells, and `HouseMeshBuilder`
feeds that union to `RoofBuilder` *before* calling it. The straight-skeleton roof
then generates over the whole footprint in one pass — hips, ridges, and eaves wrap
the porch exactly as if its cells were house cells, with no seam and no second roof
system to tie in.

`PorchBuilder.build` runs *after* the roof and adds only what's needed underneath,
all hung from **one flat ceiling height** — deliberately not mirroring the roof's
pitch. The height is the lowest point the roof reaches anywhere over the porch,
minus a clearance.

A porch's cover can be a roof *or* the storey above it. `_build_cover_context`
splits the porch region against the upper floor's wall loops and returns one entry
per part: the parts under a roof take their ceiling from
`RoofSurface.min_height_over_region`, the parts under a storey take
`floor_top - PORCH_SOFFIT_DROP` and get a soffit plus a solid rim band closing the
gap up to the storey's base. Posts read the height of whichever region they stand
in, so one porch can be half roof-ceilinged and half soffited.

`RoofBuilder` never generates a roof over a porch bay that the storey above covers
— the bay is dropped from `roof_cells` *before* generation rather than generated
and clipped, which is what stopped the old eave-and-gutter slivers wrapping the
upper walls. Downspouts follow the same rule: `_grounded_cells` keeps them off any
wall standing over a porch, because there is no ground under it to run to.

Every deck-level post is placed by **one plan pass over the whole porch**, not per
run. A post's role (CORNER, END, INTERMEDIATE) must not depend on which run reached
it first. A corner post goes at the intersection of the two runs' post lines, so
both runs derive the same point and convex *and* reflex corners get exactly one post.
Nudging each end post back along its own run instead only coincides at convex corners
and splits reflex ones in two.

## Doors

A door's `door_mode` decides where its leaf ends up. The opening, its reveals,
and both casings are built the same way in every mode — only the leaf moves.

| Mode | Leaf | Collision |
| --- | --- | --- |
| `STATIC` | baked into the house mesh where it stands | the wall run stays solid |
| `ANIMATED` | its own mesh under a pivot node, with an animation | its own box, moving with the pivot |
| `NONE` | not built at all | the wall run is cut open |

An animated door exports as a pivot placed at its hinge, with the leaf mesh
carrying the **inverse** of that pivot transform:

```
Doors                        ← runtime/house_doors.gd
  Door_0                     ← Node3D at the hinge, house-space transform T
    Leaf                     ← MeshInstance3D, transform T⁻¹
    StaticBody3D/CollisionShape3D
    AnimationPlayer          ← one "open" animation, track ".:rotation"
```

The leaf mesh is built in ordinary house coordinates, exactly as the static one
would be; `T⁻¹` cancels the pivot out again. Rotating the pivot therefore turns
the leaf about its hinge with no vertex ever being transformed. The pivot's
basis is `(along, up, inward)` — **inward**, not the outward wall normal, or the
basis is left-handed and the leaf mirrors the moment it swings.

Each door owns its own `AnimationPlayer` rather than sharing one under `Doors`.
A single player can only run one animation at a time, so a shared one would
abandon door 0 halfway through whenever door 1 was asked to move.

An entry door swings inward through `door_swing_degrees`. A garage door is a
one-piece tilt-up: a quarter turn about its head takes it from hanging in the
opening to lying flat inside the bay. Sectional panels riding a curved rail
would look better and need per-panel articulation; the rigid leaf needs none.

Animated leaves are emitted with **no** visibility masks. A leaf that can swing
open has no face that is reliably hidden, and its mesh is its own — the house's
`mesh_optimization` never touches it.

## The interior

The inside is a shell, not a room system. There are no partitions and no stairs
between levels — every interior surface comes from geometry the exterior shell
already implied.

`InteriorBuilder` owns two of them:

- **Floor decks.** One horizontal deck per *level boundary*, not per floor: at
  `y = 0`, at the base of every floor above the first, and at the top of the
  last floor. A deck spans the union of the cells below and above it, so a
  cantilevered storey still gets a floor and the storey under it still gets a
  ceiling. Its top face is `interior_floor`, its underside `ceiling`.
  Cells are emitted one quad at a time rather than as one merged polygon —
  that handles donut footprints and reflex corners without ever needing
  polygon-with-holes triangulation, and adjacent cells still weld at the bake
  because the UVs are world-plan coordinates.
- **Baseboards.** A run along every inner wall face, split around any opening
  that reaches the floor and held back by the casing width, so the baseboard
  and the door casing never fight for the same plane.

The rest is emitted alongside the exterior counterpart it belongs to:

| Surface | Where it comes from |
| --- | --- |
| `interior_wall` | the wall ring's inner runs and every opening reveal — `RingGeometry` and `PerforatedRing` take an inner slot and material |
| `interior_trim` | baseboards, plus `InteriorCasing` per opening: legs, head, and a stool on windows |
| `ceiling` | deck undersides, the roof's underside, and the inward face of every gable |

A deck stops at the cell boundary, which is the wall's **centreline** — the wall
straddles it, so a deck covering its own cells already reaches half a wall
thickness past the inner face and its edge is buried in the siding. Expanding
it outward would push the edge through to the outside.

### Garage bays

`FloorData.garage_cells` marks house cells whose floor is laid at grade instead
of at the storey's own base. Without them a garage door — which already cuts
down to `grade_y()` — opens onto the cut edge of the ground deck a metre up.

The bay's top is clamped to `max(grade_y, foundation_base_y)`: a floor below the
bottom of the foundation would hang under the sealed shell. Getting a bay that
really sits at grade means giving the house a foundation deep enough to reach it.

Deck sides are emitted per cell edge against the neighbour's **own** top, not
just where a neighbour is missing. A cell beside a lower one gets a side face
spanning the drop, which is what turns the bay boundary into a riser instead of
a hole. Baseboards are cut over bay cells for the same reason the door openings
cut them — the floor they would sit on is somewhere else.

## Collision

Exported collision is a **shell**, not a solid. Per floor, `HouseCollisionBuilder`
emits one box per traced wall run (extended half a thickness past each end so
corners close) and one box per floor deck rect, leaving the rooms hollow so a
body can walk in. Wall runs are cut open over `ANIMATED` and `NONE` doorways and
keep a header box above them; a `STATIC` door leaves its run solid, which is
exactly what a shut door does.

Deck heights come from `InteriorBuilder.cell_tops` / `deck_bottom` rather than
being re-derived, so collision and geometry cannot drift — a garage bay's floor
is at grade in both or neither.

The roof stays a `ConcavePolygonShape3D` with `backface_collision = true`, which
now matters twice: it always kept rays from escaping the far side, and it also
stops a body inside the attic falling out through the roof.

### Why the roof needed an underside

Roof planes used to be one-sided: from inside, the attic was open sky. Every
shingle plane now gets a parallel plane `roof_deck_thickness` below it, clipped
to the wall polygon, and every gable gets an inward face. The soffit already
closes the overhang from below and the fascia already hides the deck edge at the
eave, so nothing else had to move.

Those undersides go on the `ceiling` slot, **not** `roof_underlayment`. That slot
is the soffit and the porch ceiling; `RoofSurface.min_height_over_region` reads it
to hang the porch ceiling, so overloading it silently dropped the porch's ceiling
onto the roof underside instead.

### Glass reads from both sides

A window's glass is a two-pane slab `DetailConstants.GLASS_THICKNESS` apart
rather than two coincident quads. Coincident transparent panes have no stable
draw order within a surface; separated ones do. The outer pane is `EXTERIOR` and
the inner `INTERIOR`, so `EXTERIOR_ONLY` still bakes exactly one pane per window.

## Mesh optimization

Every face is emitted with a **visibility class**, and the bake keeps a chosen
subset. `HouseData.mesh_optimization` picks it:

| Mode | Keeps | Drops |
| --- | --- | --- |
| `NONE` | everything | — |
| `DROP_BURIED` | `EXTERIOR`, `INTERIOR` | faces sealed inside another solid |
| `EXTERIOR_ONLY` | `EXTERIOR` | the above, plus faces only an interior camera sees |

`BURIED` means *geometrically enclosed by other geometry* — a baluster's ends
inside the rails, a window jamb's underside on its sill, a downspout's foot below
grade. `INTERIOR` means *bounds the space inside the house* — wall ring inner
runs, corner-post faces flush with them, back-side window panes.

Nothing is deleted from the builders. Classification happens at the emit call and
the accumulator filters, which is what let the interior land as new `INTERIOR`
faces rather than a rewrite. `BoxBuilder.build` takes two face masks for this, and
`BoxBuilder.face_toward` maps a plan direction onto the right one so callers can
work in their own `(along, normal)` frame.

`EXTERIOR_ONLY` now empties whole surfaces — `interior_wall`, `interior_floor`,
`ceiling` and `interior_trim` have no exterior faces at all. That is correct, and
it is why the test no longer asserts every mode keeps every surface.

Only tag what is *structurally* enclosed. What remains after `EXTERIOR_ONLY` is
mostly **occlusion** — one solid hiding another at most viewing angles, like the
gutter trough under the roof edge — which is view-dependent and deliberately not
tagged.

`tests/mesh_optimization_test.gd` is the safety net: it ray-casts each example
house from a dome of exterior eye points above grade and asserts **no `BURIED`
face is reachable**, and that no surface holding ray-reachable geometry is
dropped by `EXTERIOR_ONLY`. `tests/interior_subsystem_test.gd` casts the mirror
of that: rays *from inside* a sealed house, asserting none escape. It has already caught two wrong tags (window frames stand
`FRAME_DEPTH` proud of the siding, so their tops are under open sky, not under the
wall). Build the trimesh with `backface_collision = true` — the default lets rays
escape through the far side of every solid and silently reports far too much as
visible.

## Conventions

- **Grid cell `(x, y)` maps to world `(x, ·, y)`**, consistently, everywhere. Plan
  space is always `Vector2`; there is no separate Y-up surprise.
- **Winding is enforced, not assumed.** It's normalized at the one point it's
  produced (`Footprint._normalize_winding`), and every consumer re-normalizes
  anything entering from outside that path.
- **Emitted triangle winding**: a triangle's geometric cross product points *against*
  its stored normal, consistently across every surface. `MeshChecks.check_windings`
  asserts this. Quads whose vertex order isn't statically known go through
  `PlanPolygon.oriented_quad`.
- **Faces are classed, not deleted.** A face nobody can see is still emitted; the
  accumulator decides whether it is baked. See *Mesh optimization*.
- **No inline magic numbers** in the roof or detail subsystems. Every tolerance lives
  in `RoofConstants` or `DetailConstants`.
- **Every user-tunable value is an `@export` on `HouseData`**, wired into
  `house_properties.gd`'s `MATERIAL_SLOTS` / `GEOMETRY_SECTIONS` tables. Adding a
  user-facing constant means: `@export` on `HouseData` → row in `GEOMETRY_SECTIONS`
  → read in `RoofBuilder.build` when constructing `RoofInput`.
- **Window glow is graphical only.** No light nodes are exported. `HouseWindowLights`
  swaps the `"glass"` surface's material override to a lit material baked at export.
  A game consuming exports must ship `addons/house_builder/runtime/` at the same
  `res://` path — `HouseDoors` lives there too.
- **ArrayMesh has no find-surface-by-name.** Look surfaces up by iterating
  `surface_get_name` — see `MeshChecks.find_surface`.

## Save format

A saved house is a single `.tscn`: the exported, instantiable scene with the editable
`HouseData` embedded as `house_data` metadata on the root node. Saving is exporting;
there is no separate step and no way for the two to drift apart.

Legacy standalone `HouseData` `.tres` files still load, so an old data-file/export
pair can be combined by opening the `.tres` and saving it.

When saving, `HouseFile._clear_data_paths` clears `resource_path` on the addon-owned
resource tree so it embeds as sub-resources. Data loaded from a `.tres` carries paths
into that file; left alone, the saver would write an external reference back to it
instead of embedding. Materials and other foreign resources keep their paths and stay
external references.
