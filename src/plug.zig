const std = @import("std");
const testing = std.testing;
const Complex = std.math.Complex;
const rl = @import("raylib");
const rg = @import("raygui");
const root = @import("root.zig");

pub var global_plug_state: *PlugState = undefined;
const max_level = 16;
const max_samplesize = std.math.pow(u64, 2, max_level);

const ShaderInfo = struct {
    shader: rl.Shader,
    filename: []const u8,
};

pub const PlugState = struct {
    const PlugError = error{TooLarge};
    pub const RenderModes = enum(u8) {
        lines = 0,
        circle = 1,
    };

    const PlugCore = struct {
        samples: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        complex_samples: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        complex_amplitudes: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
    };
    core: PlugCore,

    allocator: *std.mem.Allocator,
    samples: []f32,
    complex_samples: []Complex(f32),
    complex_amplitudes: []Complex(f32),
    amplitudes: []f32,
    max_amplitude: f32 = 0,
    samples_writer: u64 = 0,
    music: rl.Music = undefined,
    shader: ?ShaderInfo = undefined,
    shader_index: usize = 0,
    texture_target: rl.RenderTexture2D = undefined,
    shaders: std.ArrayList(ShaderInfo),
    amplify: f32 = 1,
    renderMode: RenderModes = .circle,
    toggleLines: bool = true,

    pub fn init(allocator: *std.mem.Allocator, sample_level: usize) PlugError!PlugState {
        if (sample_level > max_level) {
            return PlugError.TooLarge;
        }

        var core: PlugCore = .{};
        const samplesize = std.math.pow(u64, 2, sample_level);

        return .{
            .allocator = allocator,
            .core = core,
            .samples = core.samples[0..samplesize],
            .complex_samples = core.complex_samples[0..samplesize],
            .complex_amplitudes = core.complex_amplitudes[0..samplesize],
            .amplitudes = core.amplitudes[0..samplesize],
            .shaders = std.ArrayList(ShaderInfo).init(allocator.*),
            .texture_target = rl.loadRenderTexture(1920, 1080),
        };
    }

    pub fn deinit(self: *PlugState) void {
        self.shaders.deinit();
    }
};

inline fn complexAmpToNormalAmp(complex_amplitude: Complex(f32)) f32 {
    var imag = complex_amplitude.im;
    var real = complex_amplitude.re;

    if (real < 0) real = real * -1;
    if (imag < 0) imag = imag * -1;

    if (real > imag) {
        return real;
    }

    return imag;
}

fn CollectAudioSamples(buffer: ?*anyopaque, frames: c_uint) callconv(.C) void {
    const frame_buffer: ?[*]const f32 = @ptrCast(@alignCast(buffer.?));

    if (frame_buffer == null) {
        std.log.info("Incorrect Data", .{});
        return;
    }

    var buffer_size: usize = @intCast(frames * 2);

    if (buffer_size > global_plug_state.samples.len) {
        buffer_size = global_plug_state.samples.len;
    }
    const sliced_data = frame_buffer.?[0..buffer_size];
    const availableSpace = global_plug_state.samples.len - global_plug_state.samples_writer;

    if (sliced_data.len > availableSpace) {
        const end_samples_to_replace = global_plug_state.samples[global_plug_state.samples_writer..];
        std.mem.copyForwards(f32, end_samples_to_replace, sliced_data[0..availableSpace]);

        var remaining_space = sliced_data.len - availableSpace;

        if (remaining_space > global_plug_state.samples_writer) {
            remaining_space = global_plug_state.samples_writer;
        }
        const start_samples_to_replace = global_plug_state.samples[0..remaining_space];
        std.mem.copyForwards(f32, start_samples_to_replace, sliced_data[availableSpace..]);
    } else {
        const sliceToEdit = global_plug_state.samples[global_plug_state.samples_writer..];
        std.mem.copyForwards(f32, sliceToEdit, sliced_data);
    }

    global_plug_state.samples_writer = (global_plug_state.samples_writer + frames) % global_plug_state.samples.len;

    for (global_plug_state.samples, 0..) |sample, i| {
        global_plug_state.complex_samples[i] = Complex(f32).init(sample, 0);
    }

    root.FT.NoAllocFFT(global_plug_state.complex_amplitudes, global_plug_state.complex_samples);

    global_plug_state.max_amplitude = 0;
    for (global_plug_state.complex_amplitudes, 0..global_plug_state.complex_amplitudes.len) |complex_amplitude, i| {
        global_plug_state.amplitudes[i] = complexAmpToNormalAmp(complex_amplitude);

        if (global_plug_state.amplitudes[i] > global_plug_state.max_amplitude) {
            global_plug_state.max_amplitude = global_plug_state.amplitudes[i];
        }
    }
}

export fn plugClose(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    rl.stopMusicStream(plug_state.music);
    rl.detachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);
    UnloadShaders();
    plug_state.deinit();
}

export fn plugInit(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    global_plug_state = plug_state;

    plug_state.music = rl.loadMusicStream("music/MusicMoment.wav");
    rl.attachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);

    std.debug.print("Music Frames: {}", .{plug_state.music.frameCount});
    rl.playMusicStream(plug_state.music);

    LoadShaders() catch @panic("We fucked up");
}

fn AdaptString(allocator: *std.mem.Allocator, text: []const u8) ![:0]const u8 {
    var zero_terminated_text = try allocator.alloc(u8, text.len + 1);
    std.mem.copyForwards(u8, zero_terminated_text, text);
    zero_terminated_text[text.len] = 0;
    return zero_terminated_text[0..text.len :0];
}

fn LoadShaders() !void {
    var shaders_dir = try std.fs.cwd().openDir("./shaders", .{ .iterate = true });
    defer shaders_dir.close();

    var walker = try shaders_dir.walk(global_plug_state.allocator.*);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const path: []const u8 = try shaders_dir.realpathAlloc(global_plug_state.allocator.*, entry.path);
        defer global_plug_state.allocator.free(path);
        const valid_path = AdaptString(global_plug_state.allocator, path) catch "ERROR";
        defer global_plug_state.allocator.free(valid_path);

        const name = try global_plug_state.allocator.dupe(u8, entry.basename);

        try global_plug_state.shaders.append(.{ .filename = name, .shader = rl.loadShader(null, valid_path) });
    }
}

fn UnloadShaders() void {
    for (global_plug_state.shaders.items) |shaderInfo| {
        rl.unloadShader(shaderInfo.shader);
        global_plug_state.allocator.free(shaderInfo.filename);
    }

    global_plug_state.shaders.clearRetainingCapacity();
}

export fn startHotReloading(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    _ = plug_state;

    rl.detachAudioStreamProcessor(global_plug_state.music.stream, CollectAudioSamples);

    std.log.debug("Detached Audio", .{});
}

export fn endHotReloading(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    global_plug_state = plug_state;
    rl.attachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);

    std.log.debug("Ended Hot reloading s2", .{});
}

fn limitAmplitudeRange(plug_state: *PlugState, min: f32, max: f32) []const f32 {
    const amplitudes = plug_state.*.amplitudes;
    const amplitude_cutoff = (amplitudes.len / 2) + 1;
    const valid_amps = amplitudes[0..amplitude_cutoff];
    const sample_rate: f32 = @floatFromInt(global_plug_state.music.stream.sampleRate);
    const sample_size: f32 = @floatFromInt(plug_state.*.samples.len);
    const frequency_step: f32 = sample_rate / sample_size;

    const min_index: usize = @intFromFloat(std.math.floor(min / frequency_step));
    var max_index: usize = @intFromFloat(std.math.floor(max / frequency_step));

    if (max_index >= valid_amps.len) {
        max_index = valid_amps.len;
    } else {
        max_index += 1;
    }

    return valid_amps[min_index..max_index];
}

fn handleInput(plug_state: *PlugState) void {
    if (rl.isKeyPressed(.s)) {
        plug_state.shader = if (plug_state.shader != null) null else plug_state.shaders.items[plug_state.shader_index];
    }

    if (plug_state.shader != null) {
        if (rl.isKeyPressed(.left)) {
            plug_state.shader_index = if (plug_state.shader_index == 0) plug_state.shaders.items.len - 1 else plug_state.shader_index - 1;
        } else if (rl.isKeyPressed(.right)) {
            plug_state.shader_index = (plug_state.shader_index + 1) % plug_state.shaders.items.len;
        }

        plug_state.shader = plug_state.shaders.items[plug_state.shader_index];
    }

    if (rl.isKeyDown(.down)) {
        plug_state.amplify -= 0.01;
    } else if (rl.isKeyDown(.up)) {
        plug_state.amplify += 0.01;
    }

    if (rl.isKeyPressed(.enter)) {
        plug_state.renderMode = if (plug_state.renderMode == .circle) .lines else .circle;
    }

    if (rl.isKeyPressed(.r)) {
        UnloadShaders();
        LoadShaders() catch @panic("Massive Error");
    }

    if (rl.isKeyPressed(.l)) {
        plug_state.toggleLines = !plug_state.toggleLines;
    }
}

export fn plugUpdate(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    handleInput(plug_state);

    {
        const amplitudes: []const f32 = limitAmplitudeRange(plug_state, 200, 1500);

        const amount_of_points: u64 = 50;
        const samples_per_point: u64 = (amplitudes.len) / amount_of_points;
        const points_size = (amount_of_points + 1) * 2;
        var bottom_points: [points_size]rl.Vector2 = [1]rl.Vector2{rl.Vector2.init(0, 0)} ** (points_size);
        var top_points: [points_size]rl.Vector2 = [1]rl.Vector2{rl.Vector2.init(0, 0)} ** (points_size);

        const line_length: f64 = @as(f64, @floatFromInt(rl.getRenderWidth())) / 2.0;
        const line_step: f64 = line_length / @as(f64, @floatFromInt(amount_of_points));
        const circle_angle_step = std.math.pi / @as(f64, @floatFromInt(amount_of_points));

        const y_offset: i32 = @as(i32, @divFloor(rl.getRenderHeight(), 2));
        const x_offset: i32 = @intFromFloat(line_length);
        const max_height: f64 = @as(f64, @floatFromInt(rl.getRenderHeight())) / 3.0;
        var x: f64 = 0;

        var index: u64 = 0;
        const max_amplitude = plug_state.max_amplitude;

        var previousPosX: i32 = 0;
        var previousPosY: i32 = 0;

        var first_point = true;

        var point_counter: usize = 0;

        {
            rl.beginTextureMode(plug_state.texture_target);
            defer rl.endTextureMode();

            rl.clearBackground(rl.Color.black);

            while (index < amplitudes.len and samples_per_point > 0 and max_amplitude > 0 and point_counter < points_size / 2) : (index += samples_per_point) {
                defer x += line_step;
                defer point_counter += 1;

                var line_total: f64 = 0;

                var stop = index + samples_per_point;

                if (stop > amplitudes.len) {
                    stop = amplitudes.len;
                }

                for (index..stop) |value| {
                    const amplitude = amplitudes[value];
                    line_total += amplitude;
                }

                const height: i32 = @intFromFloat(max_height * plug_state.amplify * 1 * ((line_total / @as(f32, @floatFromInt(samples_per_point))) / max_amplitude));
                const posY = height;
                const posX = @as(i32, @intFromFloat(x));

                if (first_point) {
                    previousPosX = posX;
                    previousPosY = posY;
                    first_point = false;
                }

                if (plug_state.renderMode == .lines) {
                    // rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset - posY, rl.Color.green);
                    // rl.drawLine(x_offset + previousPosX, y_offset + previousPosY, x_offset + posX, y_offset + posY, rl.Color.green);
                    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset + posY));
                    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset + posY));

                    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset - posY));
                    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset - posY));

                    if (plug_state.toggleLines) {
                        rl.drawLine(x_offset - previousPosX, y_offset - previousPosY, x_offset - posX, y_offset + posY, rl.Color.green);
                        rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset + posY, rl.Color.green);
                    }
                } else {
                    const angle = circle_angle_step * @as(f64, @floatFromInt(point_counter));
                    const radius = @as(f64, @floatFromInt(height)) + 50;

                    const circle_offset_y = y_offset;
                    const circle_offset_x = x_offset;

                    const circle_posY = @as(i32, @intFromFloat(radius * std.math.sin(angle)));
                    const circle_posX = @as(i32, @intFromFloat(radius * std.math.cos(angle)));

                    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y - circle_posY));
                    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y + circle_posY));

                    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y - circle_posY));
                    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y + circle_posY));

                    if (plug_state.toggleLines) {
                        rl.drawLine(x_offset, y_offset, circle_offset_x - circle_posX, circle_offset_y + circle_posY, rl.Color.green);
                        rl.drawLine(x_offset, y_offset, circle_offset_x + circle_posX, circle_offset_y + circle_posY, rl.Color.green);
                        rl.drawLine(x_offset, y_offset, circle_offset_x - circle_posX, circle_offset_y - circle_posY, rl.Color.green);
                        rl.drawLine(x_offset, y_offset, circle_offset_x + circle_posX, circle_offset_y - circle_posY, rl.Color.green);
                    }
                }

                previousPosX = posX;
                previousPosY = posY;
            }

            rl.drawLineStrip(&bottom_points, rl.Color.green);
            rl.drawLineStrip(&top_points, rl.Color.green);
        }

        {
            rl.beginDrawing();
            defer rl.endDrawing();
            {
                if (plug_state.shader != null) rl.beginShaderMode(plug_state.shader.?.shader);
                defer if (plug_state.shader != null) rl.endShaderMode();

                const factor: f32 = if (plug_state.shader != null) 1 else -1;

                rl.drawTextureRec(plug_state.texture_target.texture, rl.Rectangle.init(0, 0, 1920, 1080 * factor), rl.Vector2.init(0, 0), rl.Color.white);
            }

            const name = if (plug_state.shader) |shader| shader.filename else "None";

            const output = std.fmt.allocPrint(plug_state.allocator.*, "Shader: {s}", .{name}) catch @panic("BAD");
            defer plug_state.allocator.free(output);
            const text = AdaptString(plug_state.allocator, output) catch "ERROR";
            defer plug_state.allocator.free(text);

            rl.drawText(text, 10, 30, 16, rl.Color.green);

            const output_amp = std.fmt.allocPrint(plug_state.allocator.*, "Amplitude: {d:.2}", .{plug_state.amplify}) catch @panic("BAD");
            defer plug_state.allocator.free(output_amp);
            const text_amp = AdaptString(plug_state.allocator, output_amp) catch "ERROR";
            defer plug_state.allocator.free(text_amp);

            rl.drawText(text_amp, 10, 50, 16, rl.Color.green);

            if (rg.guiButton(rl.Rectangle.init(10, 100, 120, 30), "#191#Show Message") != 0) std.log.info("Yeet", .{});
        }
    }
}
