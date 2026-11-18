extends Resource
## Source rectangles in Illustration order, followed by the index of the second sheet.
@export var landmarks: Texture2D
@export var landforms: Texture2D
@export var massifs: Texture2D
@export var meadow: Texture2D
@export var foothills: Texture2D
@export var regions: Array[Rect2] = []
@export var second_sheet_start := 6
@export_range(.7,1.4) var macro_feature_scale := 1.0
@export_range(.6,1.4) var terrain_relief_strength := 1.0
@export_range(.7,1.4) var forest_region_cohesion := 1.0
