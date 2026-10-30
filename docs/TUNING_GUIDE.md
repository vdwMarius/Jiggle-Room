# Tuning guide: making jelly feel right

All feel parameters live on each jelly's **JellyData** resource
(`assets/jellies/*.tres`). The six "player" ones (stiffness, damping, wobble
Hz, max squish, mass, bounciness) can also be changed in-game under
**Colour → Feel**. Those changes save per jelly type. Use *Reset to default*
to go back to the `.tres` values.

**Workflow:** open a `.tres` in the Inspector while the game is running
(Remote tab) or use the in-game sliders. Then **Slow** mode (0.25×) is the
best way to judge the shape of a wobble.

## The target: big, juicy gelatin wobble

| Property | Target | Controlled by |
| --- | --- | --- |
| Very wobbly | 4–6 visible oscillations after a hit | `damping` (ζ) ≈ 0.10–0.14 |
| Rich, not a single bounce | Several modes ring at different speeds: sway 0.7×, body 1×, second mode 1.65× | `sway_amount`, `secondary_wobble` |
| Planted base | The bottom stays put while the top sways, like gelatin on a plate | `sway_amount`, `sag_amount` |
| Settles in ~2 s | Settle time ≈ 4 / (ζ·ω) | `damping` × `wobble_frequency` |
| Never balloon-like | No uniform inflation; every deformation is volume-preserving or along the surface | Built into the shader |
| Never mushy | Deformation capped at about 30–34 % of radius | `max_deformation` 0.3–0.34 |

Rule of thumb: **settle time ≈ 0.64 / (damping × wobble_frequency)** seconds.
The defaults give 0.64 / (0.12 × 2.6) = **2.0 s**. For the firmer, quicker
v1 feel use `damping` 0.2 and `wobble_frequency` 3.2 (1.0 s).

## Core parameters

| Parameter | Range | Default | Lower → | Higher → |
| --- | --- | --- | --- | --- |
| `wobble_frequency` (Hz) | 1–8 | 2.6 | Slow, heavy, lazy jelly (big pudding) | Fast, tight buzz (gummy bear) |
| `damping` (ζ) | 0.05–0.8 | 0.12 | Rings for ages, a "boing-boing" toy | Dead, clay-like; above 0.6 barely wobbles |
| `stiffness` | 0–1 | 0.35 | Softer: grabs, lag, stretch and impacts all deform more (×1.6 at 0) | Firmer: everything deforms less (×0.4 at 1) |
| `max_deformation` | 0.1–0.35 | 0.32 | Subtle, solid look | Big squish (above 0.34 starts to look mushy) |
| `mass` (kg) | 0.2–5 | 1.0 | Floaty, easily flung, pushed around by others | Heavy and planted, shoves smaller jellies |
| `bounciness` | 0–0.95 | 0.35 | Lands with a splat | Superball (combined with wall bounce, capped at 1) |
| `friction` | 0–1 | 0.6 | Slides around (see also *Slippery floor*) | Grippy, rolls instead of sliding |

> Mass scales with size³ automatically when you pinch or merge.

## Advanced parameters (Inspector only)

| Parameter | Default | Effect |
| --- | --- | --- |
| `stretch_per_speed` | 0.04 | How much speed turns into elongation. 0.06+ looks cartoony |
| `lag_amount` | 1.0 | How far floppy parts trail. Octopus 2.0, dolphin 1.6, cube 1.0 |
| `impact_squash_per_speed` | 0.055 | Flatten per m/s of impact. At 5 m/s with default stiffness that's about 0.3 |
| `sway_amount` | 1.0 | How far the top sways over the planted base when pushed, poked, dragged or released. Blob 1.25, octopus 1.4. Also an in-game slider |
| `sag_amount` | 0.07 | Resting squash under its own weight. Disappears in zero-g and while held, so landing makes it wobble down into place |
| `secondary_wobble` | 0.7 | Faster elliptical ring after hits. 0 gives a single clean bounce; 1.2+ gives a very "boingy" shimmer |
| `ripple_amplitude` | 0.12 | Tap ripple height (fraction of radius) |
| `ripple_decay` | 2.2 | How quickly ripples die out (1/s). Lower values make long-lasting rings |
| `ripple_frequency_scale` | 2.5 | Ripple speed relative to the wobble. Higher gives a quicker shimmer |
| `ripple_wavelength` | 0.55 | Distance between ripple rings (fraction of radius). Lower gives finer rings |
| `core_floppiness` | 0.25 | How much black (rigid) vertices still move. 0 makes a solid core with wobbly limbs |

## Recipes

| Feel | Changes from default |
| --- | --- |
| **Juicy gelatin** (default) | — |
| **Firm gelatin dessert** (v1 default) | `wobble_frequency` 3.2, `damping` 0.2, `stiffness` 0.45, `max_deformation` 0.28, `sway_amount` 0.6, `secondary_wobble` 0.4 |
| **Gummy bear** | `wobble_frequency` 5.5, `damping` 0.3, `stiffness` 0.7, `max_deformation` 0.18 |
| **Water balloon** | `wobble_frequency` 2.0, `damping` 0.12, `stiffness` 0.2, `lag_amount` 1.5, `bounciness` 0.2 |
| **Bouncy superball jelly** | `bounciness` 0.85, `damping` 0.25, `impact_squash_per_speed` 0.06 |
| **Lazy pudding** | `wobble_frequency` 1.8, `damping` 0.35, `mass` 2.5, `bounciness` 0.1 |
| **Jiggly octopus** | `lag_amount` 2.0, `core_floppiness` 0.15, `damping` 0.16, `wobble_frequency` 2.6 |

## Troubleshooting the feel

| Symptom | Fix |
| --- | --- |
| Looks like it's inflating | Lower `stretch_per_speed` and check that `max_deformation` ≤ 0.3. Make sure the mesh is centred (prep script) so squash pivots correctly |
| Mushy or melty | Raise `stiffness`, lower `max_deformation`, raise `damping` a little |
| Wobbles forever | Raise `damping` (settle time ∝ 1/(ζ·f)) |
| Sways like a tree in the wind | Lower `sway_amount` or raise `stiffness` |
| Looks like it's sinking when resting | Lower `sag_amount` |
| Too stiff or "plastic" | Lower `damping` to 0.15 and `stiffness` to 0.3 |
| Limbs don't trail | Paint them redder in Blender, raise `lag_amount`, lower `core_floppiness` |
| Whole body sways like a flag | Paint the core black, lower `core_floppiness` |
| Ripples invisible | Raise `ripple_amplitude` and lower `ripple_wavelength`. Low-poly meshes need ≥ ~2k vertices to show ripples |
| Ripples look noisy | Raise `ripple_wavelength` and `ripple_decay` |
| Jitter while resting | It's physics, not the shader. Raise `angular_damp` in `_apply_physics_material`, or use `collision = SPHERE` |

## Haptics and sound

`scripts/autoload/feedback.gd`:

* `impact(speed, wobble_hz)` maps 0.6–8.6 m/s to a vibration of 12–45 ms at
  25–100 % amplitude and −18 to 0 dB. Above 4 m/s it picks "boing", otherwise
  "squelch". Above 2.5 m/s a low "wub-wub" wobble sound plays too.
* A **wobble tail** of up to 3 fading haptic pulses follows each solid hit,
  spaced one wobble period apart, so you feel the jelly ring.
* Pitch is randomised between 0.85 and 1.2×, and lowered in slow-mo.
* Rate limits are 40 ms for haptics and 50–90 ms per sound kind, so a jelly
  rattling in a corner doesn't buzz constantly.
