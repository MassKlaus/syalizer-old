const std = @import("std");
const plug = @import("../plug.zig");
const settings = @import("./settings.zig");
const utils = @import("../utils.zig");
const PlugState = plug.PlugState;
const rl = @import("raylib");
const rg = @import("raygui");

fn handleVisualizerInput(plug_state: *PlugState) void {
    if (plug_state.outputMode == .video) {
        if (rl.isKeyPressed(.c)) {
            plug_state.outputMode = .screen;
        }
        return;
    }

    if (rl.isKeyPressed(.escape)) {
        plug_state.ClearFFT();
        if (plug_state.music) |music| {
            rl.stopMusicStream(music);
            rl.detachAudioStreamProcessor(music.stream, plug.CollectAudioSamples);
            rl.unloadMusicStream(music);
            plug_state.music = null;
        }
        plug_state.goBack();
    }

    if (rl.isKeyPressed(.m)) {
        plug_state.music_volume = if (plug_state.music_volume != 0) 0 else rl.getMasterVolume();
        rl.setMusicVolume(plug_state.music.?, plug_state.music_volume);
    }

    if (rl.isKeyDown(.down)) {
        plug_state.amplify -= 0.01;
    } else if (rl.isKeyDown(.up)) {
        plug_state.amplify += 0.01;
    }

    if (rl.isKeyPressed(.enter)) {
        plug_state.renderMode = switch (plug_state.renderMode) {
            .lines => .circle,
            .circle => .bars,
            .bars => .lines,
        };
    }

    if (rl.isKeyPressed(.r)) {
        plug_state.UnloadShaders();
        plug_state.LoadShaders() catch @panic("Massive Error");
    }

    if (rl.isKeyPressed(.l)) {
        plug_state.toggle_lines = !plug_state.toggle_lines;
    }

    if (rl.isKeyPressed(.t)) {
        plug_state.render_info = !plug_state.render_info;
    }

    if (rl.isKeyPressed(.p)) {
        plug_state.outputMode = .video;
    }

    if (rl.isKeyPressed(.space)) {
        plug_state.pause = !plug_state.pause;
        if (plug_state.music) |music| {
            if (plug_state.pause) {
                rl.pauseMusicStream(music);
            } else {
                rl.resumeMusicStream(music);
            }
        }
    }

    if (rl.isKeyPressed(.page_down)) {
        plug_state.processing_mode = switch (plug_state.processing_mode) {
            .normal => .smooth,
            .log => .normal,
            .smear => .log,
            .smooth => .smear,
        };
    }

    if (rl.isKeyPressed(.page_up)) {
        plug_state.processing_mode = switch (plug_state.processing_mode) {
            .normal => .log,
            .log => .smear,
            .smear => .smooth,
            .smooth => .normal,
        };
    }

    if (rl.isKeyPressed(.u)) {
        plug_state.view_UI = !plug_state.view_UI;
    }

    if (rl.isKeyPressed(.f8)) {
        plug_state.setting_UI = !plug_state.setting_UI;
    }
}

var appliedScrollOffset = rl.Vector2.init(0, 0);
var shaderScrollOffset = rl.Vector2.init(0, 0);
var renderContent = rl.Rectangle.init(0, 0, 0, 0);

pub fn RenderSettingDialog(plug_state: *PlugState, size: rl.Rectangle) void {
    if (plug_state.setting_UI) {
        const offset_x: i32 = @intFromFloat(size.x);
        const offset_y: i32 = @intFromFloat(size.y);
        const width: i32 = @intFromFloat(size.width);
        const height: i32 = @intFromFloat(size.height);

        rl.drawRectangle(offset_x - 1, offset_y - 1, width + 2, height + 2, plug_state.settings.border_color);
        rl.drawRectangle(offset_x, offset_y, width, height, plug_state.settings.back_color);

        rl.drawText("Applied Shader List", offset_x + 10, offset_y + 20, 16, plug_state.settings.front_color);
        _ = rg.guiToggle(utils.init(offset_x + width - 100, offset_y + 10, 90, 50), "Enable", &plug_state.apply_shader_stack);

        const button_height: i32 = 200;

        const column_width: i32 = @divFloor(width, 2);
        const column_heigth: i32 = height - 60 - 24;
        const scroll_area_heigth: i32 = height - 60 + 2;

        const scroll_area_y: i32 = @intFromFloat(size.y + 60);
        const scissor_y: i32 = scroll_area_y + 24;
        const mouse_position = rl.getMousePosition();

        {
            const scroll_x: i32 = @intFromFloat(appliedScrollOffset.x);
            const scroll_y: i32 = @intFromFloat(appliedScrollOffset.y);
            const stack_height: i32 = @intCast(button_height * plug_state.applied_shaders.items.len);
            const stack_column_width = if (stack_height < column_heigth) column_width else column_width - 13;
            const scissor_stack_x: i32 = offset_x;
            const stack_x: i32 = scissor_stack_x + scroll_x;
            const stack_y: i32 = scissor_y + scroll_y;

            const position = utils.init(scissor_stack_x, scroll_area_y, column_width, scroll_area_heigth);
            _ = rg.guiScrollPanel(position, "Effect Stack", utils.init(0, 0, column_width, stack_height), &appliedScrollOffset, &renderContent);

            rl.beginScissorMode(scissor_stack_x, scissor_y, stack_column_width, column_heigth);
            defer rl.endScissorMode();

            rl.drawRectangle(scissor_stack_x, scissor_y, stack_column_width, column_heigth, plug_state.settings.back_color);

            var i: usize = 0;
            while (i < plug_state.applied_shaders.items.len) : (i += 1) {
                const shader = plug_state.applied_shaders.items[i];
                const index = @as(i32, @intCast(i));
                const position_y: i32 = stack_y + button_height * index;
                const text = plug.AdaptString(shader.filename);

                const button_rectangle = rl.Rectangle.init(@floatFromInt(stack_x), @floatFromInt(position_y), @floatFromInt(stack_column_width), button_height);

                if (rg.guiButton(button_rectangle, text) != 0 and rl.checkCollisionPointRec(mouse_position, position)) {
                    _ = plug_state.applied_shaders.orderedRemove(i);
                }
            }
        }

        {
            const scroll_x: i32 = @intFromFloat(shaderScrollOffset.x);
            const scroll_y: i32 = @intFromFloat(shaderScrollOffset.y);
            const shaders_height: i32 = @intCast(button_height * plug_state.shaders.len);
            const shaders_column_width = if (shaders_height < column_heigth) column_width else column_width - 13;
            const scissor_shader_x: i32 = offset_x + column_width;
            const shader_x: i32 = scissor_shader_x + scroll_x;
            const shader_y: i32 = scissor_y + scroll_y;
            const position = utils.init(scissor_shader_x, scroll_area_y, column_width, scroll_area_heigth);
            _ = rg.guiScrollPanel(position, "Available Effects", utils.init(0, 0, column_width, shaders_height), &shaderScrollOffset, &renderContent);

            rl.beginScissorMode(scissor_shader_x, scissor_y, shaders_column_width, column_heigth);
            defer rl.endScissorMode();

            rl.drawRectangle(scissor_shader_x, scissor_y, shaders_column_width, column_heigth, plug_state.settings.back_color);

            for (plug_state.shaders, 0..) |*shader, i| {
                const index = @as(i32, @intCast(i));
                const position_y: i32 = shader_y + button_height * index;
                const text = plug.AdaptString(shader.filename);
                const button_rectangle = rl.Rectangle.init(@floatFromInt(shader_x), @floatFromInt(position_y), @floatFromInt(shaders_column_width), button_height);

                if (rg.guiButton(button_rectangle, text) != 0 and rl.checkCollisionPointRec(mouse_position, position)) {
                    plug_state.applied_shaders.append(shader) catch @panic("Bullshit");
                }
            }
        }
    }
}

pub fn RenderVisualizerPage(plug_state: *PlugState) void {
    switch (plug_state.outputMode) {
        .screen => {
            const delta_time = rl.getFrameTime();
            const amp_data = plug.getAmplitudesToRender(plug_state, delta_time);

            RenderVisualizerFrameToTexture(plug_state, plug_state.render_texture, amp_data.amps, amp_data.max);
            plug.ApplyShadersToTexture(plug_state, plug_state.render_texture, plug_state.shader_texture);
            plug.PrintTextureToScreen(plug_state, plug_state.shader_texture, RenderVisualizerInfo);
        },
        .video => {
            RenderVisualizeVideoWithFFMPEG(plug_state);
        },
    }

    handleVisualizerInput(plug_state);
}

fn CalculateLinePointPositions(plug_state: *PlugState, bottom_points: []rl.Vector2, top_points: []rl.Vector2, points_size: usize, point_counter: usize, x_offset: i32, y_offset: i32, posX: i32, posY: i32) void {
    const offset = rl.Vector2.init(@floatFromInt(x_offset), @floatFromInt(y_offset));
    const lastPoint = if (point_counter == 0) rl.Vector2.init(@floatFromInt(posX), @floatFromInt(posY)) else bottom_points[points_size / 2 + point_counter - 1].subtract(offset);
    const previousPosX = @as(i32, @intFromFloat(lastPoint.x));
    const previousPosY = @as(i32, @intFromFloat(lastPoint.y));

    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset + posY));
    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset + posY));

    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset - posY));
    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset - posY));

    if (plug_state.toggle_lines) {
        rl.drawLine(x_offset - previousPosX, y_offset - previousPosY, x_offset - posX, y_offset + posY, plug_state.settings.front_color);
        rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset + posY, plug_state.settings.front_color);
    }
}

fn CalculateCirclePointPositions(plug_state: *PlugState, bottom_points: []rl.Vector2, top_points: []rl.Vector2, points_size: usize, point_counter: usize, x_offset: i32, y_offset: i32, height: i32, angle: f32) void {
    const base_radius: i32 = 100;
    const inner_radius = base_radius - 80;
    const radius = @as(f64, @floatFromInt(height + base_radius));

    const circle_offset_y = y_offset;
    const circle_offset_x = x_offset;

    const circle_posX = @as(i32, @intFromFloat(radius * std.math.cos(angle)));
    const circle_posY = @as(i32, @intFromFloat(radius * std.math.sin(angle)));

    const inner_circle_posY = @as(i32, @intFromFloat(inner_radius * std.math.sin(angle)));
    const inner_circle_posX = @as(i32, @intFromFloat(inner_radius * std.math.cos(angle)));

    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y - circle_posY));
    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y + circle_posY));

    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y - circle_posY));
    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y + circle_posY));

    if (plug_state.toggle_lines) {
        rl.drawLine(circle_offset_x - inner_circle_posX - @divFloor(circle_posX, 4), circle_offset_y + inner_circle_posY + @divFloor(circle_posY, 4), circle_offset_x - circle_posX, circle_offset_y + circle_posY, plug_state.settings.front_color);
        rl.drawLine(circle_offset_x + inner_circle_posX + @divFloor(circle_posX, 4), circle_offset_y + inner_circle_posY + @divFloor(circle_posY, 4), circle_offset_x + circle_posX, circle_offset_y + circle_posY, plug_state.settings.front_color);
        rl.drawLine(circle_offset_x - inner_circle_posX - @divFloor(circle_posX, 4), circle_offset_y - inner_circle_posY - @divFloor(circle_posY, 4), circle_offset_x - circle_posX, circle_offset_y - circle_posY, plug_state.settings.front_color);
        rl.drawLine(circle_offset_x + inner_circle_posX + @divFloor(circle_posX, 4), circle_offset_y - inner_circle_posY - @divFloor(circle_posY, 4), circle_offset_x + circle_posX, circle_offset_y - circle_posY, plug_state.settings.front_color);
    }
}

fn RenderVisualizerFrameToTexture(plug_state: *PlugState, output_texture: rl.RenderTexture, amplitudes: []const f32, max_amplitude: f32) void {
    const amount_of_points: usize = 50;
    const samples_per_point: usize = @divFloor(amplitudes.len, amount_of_points);
    const points_size = (amount_of_points + 1) * 2;

    var bottom_points: [points_size]rl.Vector2 = [1]rl.Vector2{rl.Vector2.init(0, 0)} ** (points_size);
    var top_points: [points_size]rl.Vector2 = [1]rl.Vector2{rl.Vector2.init(0, 0)} ** (points_size);

    const line_length: f32 = @as(f32, @floatFromInt(rl.getRenderWidth())) / 2.0;
    const line_step: f32 = line_length / @as(f32, @floatFromInt(amount_of_points));
    const circle_angle_step = std.math.pi / @as(f32, @floatFromInt(amount_of_points));

    const y_offset: i32 = @as(i32, @divFloor(rl.getRenderHeight(), 2));
    const x_offset: i32 = @intFromFloat(line_length);
    const max_height: f32 = @as(f32, @floatFromInt(rl.getRenderHeight())) / 3.0;

    var index: usize = 0;

    var point_counter: usize = 0;

    {
        rl.beginTextureMode(output_texture);
        defer rl.endTextureMode();

        rl.clearBackground(plug_state.settings.back_color);

        while (index < amplitudes.len and samples_per_point > 0 and max_amplitude > 0 and point_counter < points_size / 2) : (index += samples_per_point) {
            defer point_counter += 1;

            var line_total: f32 = 0;

            var stop = index + samples_per_point;

            if (stop > amplitudes.len) {
                stop = amplitudes.len;
            }

            for (index..stop) |value| {
                const amplitude = amplitudes[value];
                line_total += amplitude;
            }

            const height: i32 = @intFromFloat(max_height * plug_state.amplify * 1 * ((line_total / @as(f32, @floatFromInt(samples_per_point)))) / max_amplitude);

            const posY = height;
            const posX = @as(i32, @intFromFloat(line_step)) * @as(i32, @intCast(point_counter));

            switch (plug_state.renderMode) {
                .lines => {
                    CalculateLinePointPositions(plug_state, &bottom_points, &top_points, points_size, point_counter, x_offset, y_offset, posX, posY);
                },
                .circle => {
                    const angle = circle_angle_step * @as(f32, @floatFromInt(point_counter));
                    CalculateCirclePointPositions(plug_state, &bottom_points, &top_points, points_size, point_counter, x_offset, y_offset, height, angle);
                },
                .bars => {
                    rl.drawRectangle(x_offset - posX, y_offset - posY, @intFromFloat(line_step), height, plug_state.settings.front_color);
                    rl.drawRectangle(x_offset + posX, y_offset - posY, @intFromFloat(line_step), height, plug_state.settings.front_color);
                    rl.drawRectangle(x_offset - posX, y_offset, @intFromFloat(line_step), height, plug_state.settings.front_color);
                    rl.drawRectangle(x_offset + posX, y_offset, @intFromFloat(line_step), height, plug_state.settings.front_color);
                },
            }
        }

        if (plug_state.renderMode == .lines or plug_state.renderMode == .circle) {
            rl.drawLineStrip(&bottom_points, plug_state.settings.front_color);
            rl.drawLineStrip(&top_points, plug_state.settings.front_color);
        }
    }
}

var fpsBuffer: [100]u8 = [1]u8{0} ** 100;

fn RenderVisualizeVideoWithFFMPEG(plug_state: *PlugState) void {
    const fpsToText = std.fmt.bufPrintIntToSlice(&fpsBuffer, plug_state.settings.fps, 10, .lower, .{});
    const argv = [_][]const u8{ "ffmpeg", "-loglevel", "verbose", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "1920x1080", "-r", fpsToText, "-i", "-", "-i", plug_state.song.?.path, "-c:v", "libx264", "-b:v", "25000k", "-c:a", "aac", "-b:a", "200k", "output.mp4" };
    var proc = std.process.Child.init(&argv, plug_state.allocator.*);
    proc.stdin_behavior = .Pipe;
    proc.spawn() catch @panic("Failed ffmpeg launch");

    plug_state.ClearFFT();
    defer plug_state.ClearFFT();

    const audio = rl.loadWave(plug_state.song.?.path) catch @panic("Failed to load wave");
    defer rl.unloadWave(audio);

    plug_state.outputMode = .video;
    defer plug_state.outputMode = .screen;

    rl.pauseMusicStream(plug_state.music.?);
    defer {
        if (!plug_state.pause) {
            rl.resumeMusicStream(plug_state.music.?);
        }
    }

    var processed_frames: usize = 0;
    const frame_rate: usize = @intCast(plug_state.settings.fps);
    const frame_count: usize = @intCast(audio.frameCount);
    const sampling_rate: usize = @intCast(audio.sampleRate);
    const sample_buffer = rl.loadWaveSamples(audio);

    const standard_frame_step: usize = @divFloor(sampling_rate, frame_rate);

    plug_state.render_total_frames = @divExact(@as(f32, @floatFromInt(frame_count)), @as(f32, @floatFromInt(standard_frame_step)));

    var frame_step: usize = 0;
    var counter: usize = 0;
    const delta_time = 1.0 / @as(f32, @floatFromInt(frame_rate));

    rl.setTargetFPS(5000);

    while (frame_count > processed_frames and plug_state.outputMode == .video) : (processed_frames += frame_step) {
        defer counter += 1;
        frame_step = if (frame_count - processed_frames > standard_frame_step) standard_frame_step else frame_count - processed_frames;

        const amp_data = plug.getAmplitudesToRender(plug_state, delta_time);

        RenderVisualizerFrameToTexture(plug_state, plug_state.render_texture, amp_data.amps, amp_data.max);
        plug.ApplyShadersToTexture(plug_state, plug_state.render_texture, plug_state.shader_texture);

        const image = rl.loadImageFromTexture(plug_state.shader_texture.texture) catch continue;
        defer rl.unloadImage(image);

        plug.PrintTextureToScreen(plug_state, plug_state.shader_texture, RenderVisualizerInfo);

        const pixels_raw: [*]const u8 = @ptrCast(@alignCast(image.data));

        const pixels: []const u8 = pixels_raw[0 .. 1920 * 1080 * 4];
        _ = proc.stdin.?.write(pixels) catch @panic("Bad Pipe!");

        const sampled_frames = sample_buffer[processed_frames * audio.channels .. (processed_frames + frame_step) * audio.channels];
        plug.CollectAudioSamplesZig(sampled_frames, audio.channels);

        handleVisualizerInput(plug_state);
    }

    rl.setTargetFPS(plug_state.settings.fps);

    std.log.info("Ended: Finished Rendering Frames: {}\n", .{counter});

    proc.stdin.?.close();
    proc.stdin = null;

    if (plug_state.outputMode == .video) {
        _ = proc.wait() catch @panic("Can't wait for process.");
    } else {
        std.log.info("Canceling Render. \n", .{});
        _ = proc.kill() catch @panic("Failed to kill process.");
    }

    std.log.info("Rendering Done. \n", .{});
}

fn RenderVisualizerInfo(plug_state: *PlugState) void {
    RenderVisualizerData(plug_state);
    RenderVisualizerUI(plug_state);
}

fn RenderVisualizerData(plug_state: *PlugState) void {
    if (plug_state.render_info) {
        const output = std.fmt.bufPrint(&plug.text_buffer, "Shaders: {}", .{plug_state.apply_shader_stack}) catch @panic("BAD");
        const text = plug.AdaptString(output);

        rl.drawText(text, 10, 30, 16, plug_state.settings.front_color);

        const output_amp = std.fmt.bufPrint(&plug.text_buffer, "Amplitude: {d:.2}", .{plug_state.amplify}) catch @panic("BAD");
        const text_amp = plug.AdaptString(output_amp);

        rl.drawText(text_amp, 10, 50, 16, plug_state.settings.front_color);

        switch (plug_state.processing_mode) {
            .normal => rl.drawText("Processing: Normal", 10, 70, 16, plug_state.settings.front_color),
            .log => rl.drawText("Processing: Log", 10, 70, 16, plug_state.settings.front_color),
            .smooth => rl.drawText("Processing: Smooth", 10, 70, 16, plug_state.settings.front_color),
            .smear => rl.drawText("Processing: Smear", 10, 70, 16, plug_state.settings.front_color),
        }

        switch (plug_state.renderMode) {
            .circle => rl.drawText("Rendering: Circle", 10, 90, 16, plug_state.settings.front_color),
            .lines => rl.drawText("Rendering: Lines", 10, 90, 16, plug_state.settings.front_color),
            .bars => rl.drawText("Rendering: Bars", 10, 90, 16, plug_state.settings.front_color),
        }

        if (plug_state.outputMode == .video) {
            plug_state.render_frame_counter += 1;
            const progress_percentage = plug_state.render_frame_counter * 100 / plug_state.render_total_frames;
            const output_text = std.fmt.bufPrint(&plug.text_buffer, "Rendering Video {d:.2}%", .{progress_percentage}) catch "Format Error! ";
            const valid_output_text = plug.AdaptString(output_text);
            rl.drawText(valid_output_text, 1720, 30, 16, plug_state.settings.front_color);
        }

        rl.drawFPS(1720, 50);
    }
}

fn RenderVisualizerUI(plug_state: *PlugState) void {
    const width: f32 = 1400;
    const height: f32 = 800;
    const start_x = (1920 - width) / 2;
    const start_y = (1080 - height) / 2;

    const size = rl.Rectangle.init(start_x, start_y, width, height);
    RenderSettingDialog(plug_state, size);
}
