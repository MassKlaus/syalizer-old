# Instructions

This uses raylib-zig so be sure to fetch build.zig.zon

Drop a song in the music folder named with MusicMoment.wav and the song should start

Project inspired by Mualizer

# Roadmap

To make your music visualizer really nice to use, consider adding these features:

- [ ] **Customizable Themes:**
    - [x] Allow background color customization.
    - [x] Allow foreground color customization.
    - [x] Allow border color customization.
    - [ ] Allow shape customization beyond current render modes (lines, circle, bars).
    - [ ] Implement preset themes.
    - [ ] Allow user to save/load custom themes.

- [ ] **3D Visuals:**
    - [ ] Implement basic 3D effects (rotating cubes, simple particle systems).
    - [ ] Implement advanced 3D effects (waves, complex particle systems).
    - [ ] Add controls for 3D camera movement (zoom, rotation, position).
    - [ ] Allow user to customize 3D parameters.
    - [ ] Implement 3D Render Mode.

- [ ] **Advanced Shader Effects:**
    - [X] Implement basic GLSL shader effects.
    - [X] Implement advanced GLSL shader effects for dynamic visuals.
    - [X] Allow user to load custom shaders.
    - [ ] Add more complex shader settings that can be controller from the menu.

- [ ] **Enhanced Beat Sync Effects:**
    - [ ] Energy beat detection.
    - [ ] Spectral beat detection.
    - [ ] Make visual elements react more precisely to audio beats.
    - [ ] Add options for different beat-reactive effects.
    - [ ] Implement visual effects that react to specific frequency ranges.

- [ ] **Multi-Channel Analysis:**
    - [ ] Implement separate visual effects for vocals, bass, and treble.
    - [ ] Allow user to customize visual effects for each channel.
    - [ ] Display individual channel visualizations.

- [ ] **Playlist Support:**
    - [ ] Implement local playlist support.
    - [ ] Integrate with online music streaming services.
    - [ ] Add playlist management features (add, remove, shuffle).

- [ ] **Recording & Export:**
    - [ ] Allow users to save visualizations as videos.
    - [ ] Add options for video resolution and quality.

- [ ] **VJ Mode:**
    - [ ] Implement synchronization with DJ software.
    - [ ] Add controls for VJ-specific features.
    - [ ] Allow user to map visual effects to MIDI controllers.

- [ ] **More UI Options:**
    - [ ] Move away from raygui and into Imgui (possibly).
    - [ ] Add more user interface customization options.
    - [ ] Improve UI responsiveness.
    - [ ] Add more visual adjustment sliders and buttons.

- [ ] **Settings Menu:**
    - [ ] Implement a settings menu for user preferences.
    - [ ] Allow users to adjust audio input/output settings.
    - [ ] Allow users to adjust performance settings.


# How to use

Place any song in the music folder then start app, select song and enjoy.

Here is a [preview](https://www.youtube.com/watch?v=DanNElyrI_8):

[![Video Preview of the app](https://img.youtube.com/vi/DanNElyrI_8/0.jpg)](https://www.youtube.com/watch?v=DanNElyrI_8)

# Controls

## Visualizer Controls

This document outlines the controls for the visualizer application, as defined in the `handleVisualizerInput` function.

**Output Mode Switching:**

* **C:** When generating video, press 'C' to cancel.

**General Application Controls:**

* **Escape:** Stop the current song and go back to selection menu.

**Music Controls:**

* **M:** Mute/Unmute song.

* **Space:** Pause or resume the currently playing song.

**Visualizer Adjustments:**

* **Down Arrow:** Decrease the amplification factor by 0.01.

* **Up Arrow:** Increase the amplification factor by 0.01.

* **Enter:** Cycle through render modes: lines, circle, and bars.

* **R:** Reload all shaders and fetch new oness / remove deleted ones.

* **L:** Toggle line rendering.

* **T:** Toggle rendering of information (e.g., debug data).

* **P:** Start Rendering Video.

**FFT Processing Mode:**

* **Page Down:** Cycle through processing modes in the following order: normal -> smooth -> smear -> log.

* **Page Up:** Cycle through processing modes in the following order: normal -> log -> smear -> smooth.

**User Interface Controls:**

* **U:** Toggle the main user interface.

* **F8:** Toggle the shadersUI interface.

## Selection Menu Controls

This document outlines the controls for the selection menu, as defined in the `handleSelectionMenuInput` function.

* **R:** Reload the song list.
* **Escape:** Close the application.
* **F8:** Navigate to the settings menu.
