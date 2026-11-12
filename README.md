# dms-wallfx

Character-outline (`BiRefNet`) and contagion shader wallpaper transitions with a fullscreen skewed coverflow carousel for **DankMaterialShell (DMS / Dux Shell)** on **Niri** and **Hyprland**.

## Features

- **4-Stage Character-Outline Transition (`perfil`)**:
  1. Dims the old wallpaper slightly like a stage.
  2. Traces the main character's silhouette with two racing pen strokes from top to bottom.
  3. Fills the character inward in crisp 4px stepped cells with a subtle camera settle.
  4. Erupts the new background outward from the character's silhouette across the screen.
- **Contagion Fallback (`contagio`)**:
  - For landscapes or abstract wallpapers without a single distinct subject, 6–12 colonies spread across a multi-scale noise field with a glowing ember edge.
- **Skewed Coverflow Wallpaper Carousel**:
  - Fullscreen GPU-accelerated parallelogram card carousel (`WlrLayer.Overlay`).
  - Navigate with `←`/`→`, `H`/`L`, `A`/`D`, or mouse wheel; press `Enter` (or click the center card) to apply, `R` to jump to a random card, or `Esc` to close.
- **Automatic DMS Integration**:
  - Syncs with DMS's native `SessionData.setWallpaper()` so Material 3 (`matugen`) dynamic system themes update automatically.
  - Optionally intercepts wallpaper changes triggered from DMS's built-in wallpaper picker or CLI (`dms ipc call wallpaper set ...`).
- **Zero-Config Python Environment**:
  - Automatically bootstraps `~/.local/share/wallfx/venv` (`rembg`, `onnxruntime`, `opencv-python-headless`, `numpy`, `pillow`) on first launch.

## Installation

### Manual / Local Install
```bash
git clone https://github.com/AverageMateo/dms-wallfx.git ~/.config/DankMaterialShell/plugins/wallfx
```
Then enable **WallFX Transitions & Carousel** in **DMS Settings → Plugins**.

## IPC Commands & Keybinds

Bind any of these commands in Niri (`~/.config/niri/config.kdl`) or Hyprland (`~/.config/hypr/hyprland.conf`):

```bash
# Toggle the skewed coverflow wallpaper carousel
dms ipc call wallfx toggle

# Open / close the carousel explicitly
dms ipc call wallfx open
dms ipc call wallfx close

# Transition to a specific wallpaper
dms ipc call wallfx apply ~/Pictures/Wallpapers/example.png

# Transition to a random wallpaper from your wallpapers folder
dms ipc call wallfx random

# Pre-compute character outlines for all wallpapers in your folder
dms ipc call wallfx warm

# View FPS / frame-timing stats from the last transition
dms ipc call wallfx stats
```

### Example Niri Keybind (`~/.config/niri/user-config.kdl`)
```kdl
binds {
    Mod+W hotkey-overlay-title="Wallpaper Carousel (WallFX)" {
        spawn "dms" "ipc" "call" "wallfx" "toggle";
    }
}
```

## Credits

- Shader pipeline & contour map math adapted from [`pocket-dots`](https://github.com/diegoMalagrida/pocket-dots) by Diego Malagrida.
