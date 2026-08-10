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
   - `WallDetailBuilder.build` — window / door / garage dressing per opening
3. `FoundationBuilder.build` — foundation ring and post pads, ground floor only
4. `PorchBuilder.roof_cells(...)` — porch cells join the lowest floor's roof
   footprint, *before* the roof is built
5. `RoofBuilder.build` — roofs for every floor, plus gutters and downspouts
6. `PorchBuilder.build` — deck, posts, railings, stairs, ceiling, perimeter band
7. `DormerBuilder` / `ChimneyBuilder` — roof details, querying the returned roof
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
| `WallDetail` | WINDOW / DOOR / GARAGE_DOOR / STAIRS at `(cell, direction)` |
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

Every deck-level post is placed by **one plan pass over the whole porch**, not per
run. A post's role (CORNER, END, INTERMEDIATE) must not depend on which run reached
it first. A corner post goes at the intersection of the two runs' post lines, so
both runs derive the same point and convex *and* reflex corners get exactly one post.
Nudging each end post back along its own run instead only coincides at convex corners
and splits reflex ones in two.

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
- **No inline magic numbers** in the roof or detail subsystems. Every tolerance lives
  in `RoofConstants` or `DetailConstants`.
- **Every user-tunable value is an `@export` on `HouseData`**, wired into
  `house_properties.gd`'s `MATERIAL_SLOTS` / `GEOMETRY_SECTIONS` tables. Adding a
  user-facing constant means: `@export` on `HouseData` → row in `GEOMETRY_SECTIONS`
  → read in `RoofBuilder.build` when constructing `RoofInput`.
- **Window glow is graphical only.** No light nodes are exported. `HouseWindowLights`
  swaps the `"glass"` surface's material override to a lit material baked at export.
  A game consuming exports must ship `addons/house_builder/runtime/` at the same
  `res://` path.
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
