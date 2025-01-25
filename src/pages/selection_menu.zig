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

    const buttonHeight: i32 = 200;
    const panelHeight = buttonHeight * plug_state.songs.items.len;

    var max_width = halfScreen - 1 - 13;
    const max_heigth = screenHeight - 42 - 1;

    if (panelHeight < max_heigth) {
        max_width += 13;
    }

    _ = rg.guiScrollPanel(rl.Rectangle.init(0, 18, @floatFromInt(halfScreen), @floatFromInt(screenHeight)), "Music Selection Menu", rl.Rectangle.init(0, 0, @as(f32, @floatFromInt(halfScreen)), @as(f32, @floatFromInt(panelHeight))), &scrollOffset, &renderContent);

    rl.beginScissorMode(0, 42, halfScreen, screenHeight * 2);
    defer rl.endScissorMode();

    const baseX: i32 = @intFromFloat(scrollOffset.x + 1);
    const baseY: i32 = @intFromFloat(scrollOffset.y + 42);

    rl.drawRectangle(1, 42, max_width, max_heigth, rl.Color.black);
    rl.drawLine(1 + max_width, 42, 1 + max_width, 42 + max_heigth, plug_state.settings.front_color);

    for (plug_state.songs.items, 0..) |*song, i| {
        const index = @as(i32, @intCast(i));
        const Y: i32 = baseY + buttonHeight * index;
        const text = plug.AdaptString(song.filename);

        const buttonRec = rl.Rectangle.init(@floatFromInt(baseX), @floatFromInt(Y), @floatFromInt(max_width), buttonHeight);
        const mousePosition = rl.getMousePosition();

        if (rg.guiButton(buttonRec, text) != 0) {
            plug_state.log_info("Song \"{s}\" Selected.", .{song.path});

            plug_state.NavigateTo(.Visualizer);

            const music = rl.loadMusicStream(song.path) catch @panic("Failed to load the music file.");

            plug_state.music = music;
            plug_state.song = song;

            rl.attachAudioStreamProcessor(music.stream, plug.CollectAudioSamples);
            rl.playMusicStream(music);

            std.debug.print("Music Frames: {}", .{music.frameCount});
        } else if (rl.checkCollisionPointRec(mousePosition, buttonRec) and (plug_state.preview_song == null or song != plug_state.preview_song.?)) {
            std.log.info("Preview: {s}", .{song.filename});

            plug_state.preview_song = song;
            // plug_state.preview_audio = rl.loadWave(song.path);
            // plug_state.preview_audio_data = rl.loadWaveSamples(plug_state.preview_audio.?);
        }
    }
}
