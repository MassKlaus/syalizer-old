# Instructions

This uses raylib-zig so be sure to fetch build.zig.zon

Drop a song in the music folder named with MusicMoment.wav and the song should start

Project inspired by Mualizer

# How to use

Place any song in the music folder then start app, select song and enjoy.

Here is a [preview](https://www.youtube.com/watch?v=dQw4w9WgXcQ):

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
