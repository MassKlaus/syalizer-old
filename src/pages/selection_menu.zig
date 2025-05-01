const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const plug = @import("../plug.zig");
const PlugState = plug.PlugState;

fn handleSelectionMenuInput(plug_state: *PlugState) void {
    if (rl.isKeyPressed(.r)) {
        plug_state.UnloadSongList();
        plug_state.LoadSongList() catch @panic("Massive Error");
    }

    if (rl.isKeyPressed(.escape)) {
        plug_state.close = true;
    }

    if (rl.isKeyPressed(.f8)) {
        plug_state.NavigateTo(.Settings);
    }
}

var scrollOffset = rl.Vector2.init(0, 0);
var renderContent = rl.Rectangle.init(0, 0, 0, 0);

pub fn RenderSelectionMenuPage(plug_state: *PlugState) void {
    const halfScreen = @divFloor(rl.getScreenWidth(), 2);
    const screenHeight = rl.getScreenHeight();

    defer handleSelectionMenuInput(plug_state);

    rl.beginDrawing();
    defer rl.endDrawing();

    rl.clearBackground(plug_state.settings.back_color);

    const button_height: i32 = 200;
    const panel_height = button_height * plug_state.songs.len;

    var max_width = halfScreen - 1 - 13;
    const max_heigth = screenHeight - 42 - 1;

    if (panel_height < max_heigth) {
        max_width += 13;
    }

    _ = rg.guiScrollPanel(rl.Rectangle.init(0, 18, @floatFromInt(halfScreen), @floatFromInt(screenHeight)), "Music Selection Menu", rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(halfScreen)), @as(f32, @floatFromInt(panel_height))), &scrollOffset, &renderContent);

    rl.beginScissorMode(0, 42, halfScreen, screenHeight);
    defer rl.endScissorMode();

    const base_x: i32 = @intFromFloat(scrollOffset.x + 1);
    const base_y: i32 = @intFromFloat(scrollOffset.y + 42);

    rl.drawRectangle(1, 42, max_width, max_heigth, rl.Color.black);
    rl.drawLine(1 + max_width, 42, 1 + max_width, 42 + max_heigth, plug_state.settings.front_color);
    const mouse_position = rl.getMousePosition();

    for (plug_state.songs, 0..) |*song, i| {
        const index = @as(i32, @intCast(i));
        const position_y: i32 = base_y + button_height * index;
        const text = plug.AdaptString(song.filename);

        const button_rectangle = rl.Rectangle.init(@floatFromInt(base_x), @floatFromInt(position_y), @floatFromInt(max_width), button_height);

        if (rg.guiButton(button_rectangle, text) != 0) {
            plug_state.logInfo("Song \"{s}\" Selected.", .{song.path});

            plug_state.NavigateTo(.Visualizer);

            const music = rl.loadMusicStream(song.path) catch @panic("Failed to load the music file.");

            plug_state.music = music;
            plug_state.song = song;
            plug_state.pause = false;
            plug_state.music_volume = rl.getMasterVolume();
            plug_state.ClearFFT();

            rl.attachAudioStreamProcessor(music.stream, plug.CollectAudioSamples);
            rl.playMusicStream(music);

            std.debug.print("Music Frames: {}", .{music.frameCount});
        } else if (rl.checkCollisionPointRec(mouse_position, button_rectangle) and (plug_state.preview_song == null or song != plug_state.preview_song.?)) {
            std.log.info("Preview: {s}", .{song.filename});

            plug_state.preview_song = song;
            // plug_state.preview_audio = rl.loadWave(song.path);
            // plug_state.preview_audio_data = rl.loadWaveSamples(plug_state.preview_audio.?);
        }
    }
}
