# DemoFirstScreen artwork provenance

These PNG files are crops of the allowed local Huluwa D2 icon, not invented drawings.

- Source: `Huluwa/icon-concepts-v1/D2-refined/fs-monitor-icon-D2-1024.png`
- SHA-256: 010b92869cb37f4f187aabe127cd0900d25132a0b400d27dc8c7a777ac5085d4
- That file is byte-identical to `Eric/references/firstscreen-20261121/fs-monitor-icon-D2-1024.png` (the path used by `draw_review.py`).

Recipes (do not invent new crop boxes):

- Eyes: `draw_review.py` crop `(458,164,676,291)` and the two-ellipse mask; compositing size `654×381` at `(273,-22)` on the 1200×900 native canvas, shown at `1308×762` / `(546,-44)` on the 2400×1800 canvas. Gaze frames use `sequence-5frames/draw_sequence.py` `gaze()`.
- Metal hub: `selected-base-0353-warm-palette/draw_warm.py` crop `(410,355,610,532)` from the same D2-1024, masked and resized to `400×354`, placed at `(1000,1664)` on the 2400×1800 canvas. The metal layer is not tinted.

See `ASSET-SOURCES.json` for the exact numbers.

## 2026-11-21 gaze/clarity revision

Shared design and original assets were read in place (no new service search). The highest-resolution D2 still is the 1024×1024 icon (`fs-monitor-icon-D2-1024.png` and the same-size `D2-source.jpg`). There is no SVG or larger raster of the D2 eyes. The documented eye crop is 218×127 source pixels, displayed at 654×381 pt (1308×762 on the 2400 canvas). That ceiling cannot be restored losslessly from the bitmap; sharpening or `.interpolation(.high)` is not treated as recovery, and no GenerateImage / AI upscale was used.

On-screen eyes are therefore a layered native vector redraw that keeps the documented D2 placement, proportions, and coloring (shell / sclera fixed; iris + highlights move together under the 18% sclera-radius clamp). The original `d2-eyes-*.png` files are retained as provenance and are not overwritten or drawn as moving sprites. The metal hub remains the D2-1024 bitmap crop `d2-hub.png`.

## 2026-11-21 spherical material (procedural, not a bitmap restore)

On-screen irises are a procedural Canvas material: radial fibers, a gold-brown
limbus ring, a dark pupil, and lighting-space highlights. Palette and
proportions are taken from the allowed D2 original

`Huluwa/icon-concepts-v1/D2-refined/fs-monitor-icon-D2-1024.png`

(byte-identical to `Eric/references/firstscreen-20261121/fs-monitor-icon-D2-1024.png`)
and from the warm-palette stills `02-overview.png` / `03-hover-users.png` as
material references only (those stills are not a compliant five-sector /
badge-free layout).

This is not a sharpened, interpolated, or AI-upscaled reconstruction of the
218×127 D2 eye crop. The files `d2-eyes-rest.png`, `d2-eyes-gaze-left.png`,
and `d2-eyes-gaze-right.png` remain as provenance and are not drawn as moving
sprites. Eye *shape* (shell / sclera ellipses, group span 1272/2400) is
unchanged from the 064745 baseline. Both globes rotate toward one shared
platter-plane target (`SphereGaze`); default aim is the current largest
chartable sector (Movies in the example set).


## 2026-11-21 sphere-normal raster (after 073448)

073448 used a planar affine iris disc, thick 2D fiber strokes, a gold
outline stroke, and separate screen-space highlight circles. That is the
"coin on a white ball" look. The globe is now a CPU raster (`SphereShade` +
`SphereEyeRaster`) that samples the unit sphere: iris/limbus/pupil are
spherical caps, and highlights use the same surface normal. CoreGraphics is
the macOS 13 public API; this is still a procedural material referenced to
the D2 1024 palette, not a restore of the 218×127 crop. Eye shape and
1272/2400 placement are unchanged.


## After 074605: row convention and material

074605 wrote the globe buffer with canvas-bottom in row 0, assuming
"CGImage row 0 is the bottom". SwiftUI Canvas / NSImage place the first
row at the *top* of the destination rect, so the final cacheDisplay PNG
had the iris above the sclera while Movies (and every other platter
target) was below. The raster is now top-down (row 0 = canvas minY) and
evidence measures the PNG iris centroid against the sclera center.

Material is still procedural: cream-white wrap (not a grey plastic
ball), cornea specular only on the iris/pupil cap, softer radial tissue
rather than denser meridians. Lids stay 2D ellipses with a radial shade
and a fixed upper-lid contact — not a modeled socket. Not a D2 bitmap
restore and not sharpened / AI imagery.
