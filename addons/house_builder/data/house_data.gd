@tool
class_name HouseData
extends Resource


@export var floors: Array[FloorData] = []

## Siding material used for exterior wall meshes.
## Assign a shared Material resource (e.g. a preloaded .tres/.material)
## so it isn't duplicated per-instance when applied programmatically.
@export var siding_material: Material

## Material used for exterior trim (fascia, corner boards, window/door trim).
@export var trim_material: Material

## Material used for the foundation/footer meshes.
@export var foundation_material: Material

## Material used for the sidewalk/driveway slabs. The slabs are their own
## exported mesh (SidewalkMesh, surface slot "sidewalk"), separate from the
## house mesh.
@export var sidewalk_material: Material

## Material used for the porch floor/decking.
@export var porch_floor_material: Material

## Material used for the porch railing's top and bottom handrails.
@export var porch_railing_material: Material

## Material used for the porch's structural posts.
@export var porch_post_material: Material

## Material used for the railing infill between the handrails (balusters,
## intermediate rails, or cross slats, depending on the railing style).
@export var porch_baluster_material: Material

## Material used for the roof's outer shingles/covering.
@export var roofing_shingles_material: Material

## Material used for the layer beneath the roofing shingles
## (typically synthetic felt or plastic sheeting), where visible.
@export var roof_underlayment_material: Material

## Material used for the gutter troughs and their downspouts. Left unset,
## the trim material is used.
@export var gutter_material: Material

## Material used for window frames, sills, muntins, and door/garage casings.
@export var window_frame_material: Material

## Material used for window glass panes.
@export var glass_material: Material

## Material swapped onto the exported house's "glass" surface while its
## windows are lit (typically an emissive variant of glass_material).
## Optional - when unset, exports derive one from glass_material and the
## WINDOW GLOW fallbacks below.
@export var lit_glass_material: Material

## Material used for entry door slabs.
@export var door_material: Material

## Material used for garage door panels.
@export var garage_door_material: Material

## Material used for chimney shafts and crowns.
@export var chimney_material: Material

## Material lining the interior faces of the exterior walls - the wallpaper,
## paint, or plaster the rooms are finished with. Also used for the reveals
## of window and door openings.
@export var interior_wall_material: Material

## Material used for the walking surface of every level's floor deck.
@export var interior_floor_material: Material

## Material used for the ceiling hung under each level's floor deck.
@export var ceiling_material: Material

## Material used for interior trim - baseboards, the casings framing windows
## and doors from inside, and window stools.
@export var interior_trim_material: Material

## Size of one floor/level cell, in meters.
@export_range(1.0, 4.0, 0.01, "suffix:m") var level_cell_size: float = 2.0


## Thickness of exterior wall slabs.
@export_range(0.05, 1.0, 0.01, "suffix:m") var wall_thickness: float = 0.2

## Width (along the wall) of the corner boards placed at exterior corners.
@export_range(0.02, 0.5, 0.01, "suffix:m") var corner_trim_width: float = 0.075

## Depth (outward projection from the wall face) of the corner boards.
@export_range(0.01, 0.2, 0.005, "suffix:m") var corner_trim_depth: float = 0.03

## Height of the trim strip that runs along the bottom of each exterior wall.
@export_range(0.02, 0.6, 0.01, "suffix:m") var base_trim_height: float = 0.2

## Depth (outward projection from the wall face) of the base trim strip.
@export_range(0.01, 0.2, 0.005, "suffix:m") var base_trim_depth: float = 0.02

## Height of the foundation wall below the lowest floor.
@export_range(0.1, 2.0, 0.01, "suffix:m") var foundation_height: float = 0.4

## Distance the foundation projects outward beyond the exterior wall face.
@export_range(0.0, 0.5, 0.01, "suffix:m") var foundation_overhang: float = 0.05

## Thickness of the floor deck laid at every level boundary. Its top face is
## the level above's floor; its underside is the level below's ceiling.
@export_range(0.05, 1.0, 0.01, "suffix:m") var interior_floor_thickness: float = 0.2

## Height of the baseboard running along the inside of every exterior wall.
## 0 builds no baseboards.
@export_range(0.0, 0.6, 0.01, "suffix:m") var interior_base_trim_height: float = 0.11

## Depth the baseboard projects inward from the interior wall face.
@export_range(0.005, 0.2, 0.005, "suffix:m") var interior_base_trim_depth: float = 0.02

## Width of the flat casing band framing windows and doors from inside.
## 0 builds no interior casings.
@export_range(0.0, 0.4, 0.005, "suffix:m") var interior_casing_width: float = 0.07

## Depth the interior casing and window stool project inward from the
## interior wall face.
@export_range(0.005, 0.2, 0.005, "suffix:m") var interior_casing_depth: float = 0.02


enum RailingStyle { PICKET, HORIZONTAL, CROSS }

enum PostBaseMode { NONE, ENDS_AND_CORNERS, ALL }

## Infill style used between porch railing posts.
@export var porch_railing_style: RailingStyle = RailingStyle.PICKET

## Whether porch cells join the roof footprint - the main roof then covers
## the porch exactly as if its cells were part of the house, and the porch
## gets posts up to it plus a ceiling underneath.
@export var porch_has_roof: bool = true

## Top of the porch railing above the porch deck.
@export_range(0.6, 2.0, 0.01, "suffix:m") var porch_railing_height: float = 0.95

## Plan width of the square porch posts.
@export_range(0.06, 0.3, 0.01, "suffix:m") var porch_post_width: float = 0.12

## Center-to-center spacing of PICKET-style balusters, and their plan width.
## The count per railing run follows from its length and this spacing, so
## every run keeps the same density regardless of how long it is.
@export_range(0.05, 0.5, 0.01, "suffix:m") var porch_baluster_spacing: float = 0.14
@export_range(0.01, 0.15, 0.005, "suffix:m") var porch_baluster_width: float = 0.04

## Number of intermediate rails the HORIZONTAL style spreads between the
## bottom and top rails, and their vertical thickness.
@export_range(1, 8, 1) var porch_horizontal_rail_count: int = 2
@export_range(0.01, 0.2, 0.005, "suffix:m") var porch_horizontal_rail_height: float = 0.04

## Which porch posts get a thick foundation pier under them (see PostBaseMode).
@export var porch_post_base_mode: PostBaseMode = PostBaseMode.NONE

## Plan width of the pier, centered on the post it carries. Values below
## porch_post_width are clamped up to it - a pier narrower than its post is
## not a pier.
@export_range(0.1, 0.8, 0.01, "suffix:m") var porch_post_base_width: float = 0.28

## Height of the pier shaft above the porch deck. The pier itself continues
## down from the deck to the bottom of the foundation, so it never reads as
## standing on the deck slab.
@export_range(0.1, 2.0, 0.01, "suffix:m") var porch_post_base_height: float = 0.5

## The trim band capping the pier: its vertical thickness, and how far it
## projects past the pier on all four sides.
@export_range(0.01, 0.3, 0.005, "suffix:m") var porch_post_base_trim_height: float = 0.06
@export_range(0.0, 0.15, 0.005, "suffix:m") var porch_post_base_trim_overhang: float = 0.03

## Thickness of the porch deck slab, visible as the band between the deck
## surface and the foundation skirt below it.
@export_range(0.05, 0.4, 0.01, "suffix:m") var porch_floor_thickness: float = 0.15

## Distance the deck surface (and its edge skirt) projects outward beyond
## the structural line on the porch's open sides. House-adjacent sides never
## overhang - the deck butts into the wall there regardless of this value.
@export_range(0.0, 0.5, 0.01, "suffix:m") var porch_floor_overhang: float = 0.05


enum FoundationMode { KEEP, LOWER }

## Vertical distance from floor 0's base (y = 0) down to the sidewalk/
## driveway surface - the house's grade level. Porch stairs descend to it
## and garage door openings extend down to it; see grade_y().
@export_range(-2.0, 2.0, 0.01, "suffix:m") var sidewalk_drop: float = 1.0

## How the foundation meets the grade level. KEEP leaves the foundation
## band at [-foundation_height, 0] and notches garage door openings down
## through it to grade; LOWER shifts the whole band down to end at grade
## and extends the ground floor's siding down to meet it (regular doors
## then sit above a strip of siding; garage doors cut flush to the ring
## bottom).
@export var foundation_mode: FoundationMode = FoundationMode.KEEP

## Thickness of the sidewalk/driveway slab below its top surface.
@export_range(0.05, 0.5, 0.01, "suffix:m") var sidewalk_thickness: float = 0.2

## Uniform outward (+) or inward (-) offset applied to the sidewalk slab's
## outline, growing or shrinking it from the painted grid-cell shape.
@export_range(-1.0, 1.0, 0.01, "suffix:m") var sidewalk_expand: float = 0.0


## Roof slope, measured from horizontal. 0 is flat.
@export_range(0.0, 80.0, 0.5, "suffix:°") var roof_pitch_degrees: float = 30.0

## Distance the roof projects outward beyond the exterior wall face.
@export_range(0.0, 1.5, 0.01, "suffix:m") var roof_overhang: float = 0.4

## Height of the vertical fascia board that hangs below the roof's eave
## line, all the way around the overhang. 0 disables the fascia.
@export_range(0.0, 0.6, 0.01, "suffix:m") var roof_fascia_height: float = 0.18

## Scale multiplier applied to the roof shingle UVs (which are true-to-scale
## meters: u along the eave, v up the slope).
@export_range(0.05, 10.0, 0.05) var roof_uv_scale: float = 1.0

## Thickness of the roof deck. Each roof plane gets an underside this far
## below it, so the roof reads as a solid from inside the attic instead of
## as a one-sided shell.
@export_range(0.02, 0.5, 0.01, "suffix:m") var roof_deck_thickness: float = 0.15


## Trough profile. NONE builds no gutters at all.
@export var gutter_style: RoofGutters.Style = RoofGutters.Style.K_STYLE

## Plan width of the trough, measured outward from the fascia.
@export_range(0.06, 0.3, 0.005, "suffix:m") var gutter_width: float = 0.13

## Depth of the trough, from its top rim to the inside of its bottom.
@export_range(0.04, 0.25, 0.005, "suffix:m") var gutter_height: float = 0.10

## Whether the gutters get downspouts running to the ground (or onto the
## roof below, on a multi-storey house).
@export var gutter_downspouts_enabled: bool = true

## Plan cross-section of a downspout: width along the wall, depth out from it.
@export_range(0.04, 0.2, 0.005, "suffix:m") var downspout_width: float = 0.08
@export_range(0.03, 0.2, 0.005, "suffix:m") var downspout_depth: float = 0.06

## No stretch of gutter runs farther than this without a downspout.
@export_range(2.0, 20.0, 0.5, "suffix:m") var downspout_max_span: float = 10.0


@export_range(0.3, 50.0, 0.01, "suffix:m") var window_single_default_width: float = 1.2
@export_range(0.3, 20.0, 0.01, "suffix:m") var window_single_default_height: float = 1.4
@export_range(0.0, 20.0, 0.01, "suffix:m") var window_single_default_sill: float = 0.9

@export_range(0.3, 50.0, 0.01, "suffix:m") var window_wide_default_width: float = 1.5
@export_range(0.3, 20.0, 0.01, "suffix:m") var window_wide_default_height: float = 1.4
@export_range(0.0, 20.0, 0.01, "suffix:m") var window_wide_default_sill: float = 0.9

@export_range(0.3, 50.0, 0.01, "suffix:m") var window_small_default_width: float = 0.6
@export_range(0.3, 20.0, 0.01, "suffix:m") var window_small_default_height: float = 0.6
@export_range(0.0, 20.0, 0.01, "suffix:m") var window_small_default_sill: float = 1.5


@export_range(0.3, 50.0, 0.01, "suffix:m") var door_default_width: float = 1.0
@export_range(0.3, 20.0, 0.01, "suffix:m") var door_default_height: float = 2.1

@export_range(0.3, 50.0, 0.01, "suffix:m") var garage_door_default_width: float = 1.5
@export_range(0.3, 20.0, 0.01, "suffix:m") var garage_door_default_height: float = 2.2

## Export mode newly placed doors and garage doors start on. See
## WallDetail.door_mode - STATIC bakes the leaf into the mesh, ANIMATED gives
## it its own node and animation, NONE leaves the opening empty.
@export var door_default_mode: WallDetail.DoorMode = WallDetail.DoorMode.STATIC
@export var garage_door_default_mode: WallDetail.DoorMode = WallDetail.DoorMode.STATIC

## How long an ANIMATED door takes to swing from shut to fully open.
@export_range(0.1, 10.0, 0.05, "suffix:s") var door_open_duration: float = 0.9

## How far an ANIMATED entry door swings inward when opened. Garage doors
## ignore this - they tilt up through a quarter turn onto their head.
@export_range(15.0, 175.0, 1.0, "suffix:\u00b0") var door_swing_degrees: float = 95.0


@export_range(0.05, 0.4, 0.005, "suffix:m") var stair_default_step_height: float = 0.18
@export_range(0.1, 1.0, 0.01, "suffix:m") var stair_default_step_depth: float = 0.3
@export var stair_default_has_railing: bool = false


@export_range(0.6, 4.0, 0.01, "suffix:m") var dormer_default_width: float = 1.6
@export_range(0.1, 4.0, 0.01, "suffix:m") var dormer_default_up_slope_offset: float = 0.8
@export_range(0.5, 3.0, 0.01, "suffix:m") var dormer_default_face_height: float = 1.4
@export var dormer_default_window_style: WallDetail.WindowStyle = WallDetail.WindowStyle.SMALL


## Attach the windows_lit toggle (and a lit glass material) to exported
## houses that have window glass.
@export var window_glow_enabled: bool = true

## Emission color of the derived lit glass material.
@export var window_glow_color: Color = Color(1.0, 0.85, 0.6)

## Emission energy of the derived lit glass material.
@export_range(0.0, 16.0, 0.05) var window_glow_energy: float = 2.0


enum MeshOptimization { NONE, DROP_BURIED, EXTERIOR_ONLY }

## Which faces the baked mesh keeps. NONE bakes every face the builders
## emit. DROP_BURIED removes only faces sealed inside another solid, which
## no camera can reach from anywhere - the interior shell survives intact.
## EXTERIOR_ONLY additionally removes the faces that only an interior camera
## could see (wall cavities, back-side window panes), for houses that are
## never entered. Nothing is deleted from the builders either way, so adding
## interiors later is a matter of changing this setting.
@export var mesh_optimization: MeshOptimization = MeshOptimization.NONE


func accumulator() -> SurfaceAccumulator:
	match mesh_optimization:
		MeshOptimization.EXTERIOR_ONLY:
			return SurfaceAccumulator.new(SurfaceAccumulator.KEEP_EXTERIOR)
		MeshOptimization.DROP_BURIED:
			return SurfaceAccumulator.new(SurfaceAccumulator.KEEP_REACHABLE)
		_:
			return SurfaceAccumulator.new(SurfaceAccumulator.KEEP_ALL)


func add_floor(data: FloorData):
	floors.append(data)
	floors.sort_custom(_sort_by_level)

func remove_floor(data: FloorData):
	floors.erase(data)

func get_floor(level: int) -> FloorData:
	for floor in floors:
		if floor.level == level:
			return floor

	return null

func grade_y() -> float:
	return -sidewalk_drop


func foundation_top_y() -> float:
	if foundation_mode == FoundationMode.LOWER:
		return minf(0.0, grade_y())
	return 0.0


func foundation_base_y() -> float:
	return foundation_top_y() - foundation_height


func _sort_by_level(a: FloorData, b: FloorData) -> bool:
	return a.level < b.level
