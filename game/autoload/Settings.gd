extends Node
## Settings — immersion, photosensitive, content level, volumes (docs/07 §2).

var photosensitive: bool = false
var reduced_motion: bool = false

## docs/02 §8 content level: `calmer`, `full`, or empty until the player chooses
## (missing/invalid fails closed to the strictest content gates, Safety.gd).
## Read by Safety.gd's gates and Steering.gd's calmer-dose cap; the settings
## menu that writes it is P3.13.
var content_level: String = ""
