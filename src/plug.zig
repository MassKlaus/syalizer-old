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

    pub const RenderOutput = enum(u8) {
        screen = 0,
        video = 1,
    };

    const PlugCore = struct {
        temp_buffer: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        samples: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        complex_samples: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        complex_amplitudes: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
    };
    core: PlugCore,

    allocator: *std.mem.Allocator,
    temp_buffer: []f32,
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
    output_target: rl.RenderTexture2D = undefined,
    shaders: std.ArrayList(ShaderInfo),
    amplify: f32 = 1,
    renderMode: RenderModes = .lines,
    outputMode: RenderOutput = .screen,
    toggleLines: bool = false,
    renderInfo: bool = true,
    pause: bool = false,

    pub fn init(allocator: *std.mem.Allocator, sample_level: usize) PlugError!PlugState {
        if (sample_level > max_level) {
            return PlugError.TooLarge;
        }

        var core: PlugCore = .{};
        const samplesize = std.math.pow(u64, 2, sample_level);

        return .{
            .allocator = allocator,
            .core = core,
            .temp_buffer = core.temp_buffer[0..samplesize],
            .samples = core.samples[0..samplesize],
            .complex_samples = core.complex_samples[0..samplesize],
            .complex_amplitudes = core.complex_amplitudes[0..samplesize],
            .amplitudes = core.amplitudes[0..samplesize],
            .shaders = std.ArrayList(ShaderInfo).init(allocator.*),
            .texture_target = rl.loadRenderTexture(1920, 1080),
            .output_target = rl.loadRenderTexture(1920, 1080),
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

// a frame is L+R | f32 takes both sides
fn CollectAudioSamples(buffer: ?*anyopaque, frames: c_uint) callconv(.C) void {
    const frame_buffer: ?[*]const f32 = @ptrCast(@alignCast(buffer.?));

    if (frame_buffer == null) {
        std.log.info("Incorrect Data", .{});
        return;
    }

    const frame_count: usize = @intCast(frames);
    const buffer_size: usize = frame_count * 2;
    const data_buffer = (frame_buffer.?)[0..buffer_size];

    CollectAudioSamplesZig(data_buffer);
}

fn CollectAudioSamplesZig(samples: []const f32) void {
    const availableSpace = global_plug_state.samples.len - global_plug_state.samples_writer;

    for (samples, 0..) |sample, i| {
        if (i % 2 == 0) {
            global_plug_state.temp_buffer[i / 2] = sample;
        }
    }

    var sliced_data: []const f32 = global_plug_state.temp_buffer[0 .. samples.len / 2];

    if (sliced_data.len > global_plug_state.samples.len) {
        sliced_data = sliced_data[(sliced_data.len - global_plug_state.samples.len)..sliced_data.len];
    }

    if (sliced_data.len > availableSpace) {
        const end_samples_to_replace = global_plug_state.samples[global_plug_state.samples_writer..];
        const source_data = sliced_data[0..availableSpace];
        std.mem.copyForwards(f32, end_samples_to_replace, source_data);

        var remaining_space = sliced_data.len - availableSpace;

        if (remaining_space > global_plug_state.samples_writer) {
            remaining_space = global_plug_state.samples_writer;
        }

        const start_samples_to_replace = global_plug_state.samples[0..remaining_space];
        std.mem.copyForwards(f32, start_samples_to_replace, sliced_data[availableSpace .. availableSpace + remaining_space]);
    } else {
        const sliceToEdit = global_plug_state.samples[global_plug_state.samples_writer..];
        std.mem.copyForwards(f32, sliceToEdit, sliced_data);
    }

    global_plug_state.samples_writer = (global_plug_state.samples_writer + sliced_data.len) % global_plug_state.samples.len;

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

    rl.setTraceLogLevel(.warning);

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

fn limitFrequencyRange(plug_state: *PlugState, min: f32, max: f32) []const f32 {
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

    if (rl.isKeyPressed(.t)) {
        plug_state.renderInfo = !plug_state.renderInfo;
    }

    if (rl.isKeyPressed(.p)) {
        rl.pauseMusicStream(plug_state.music);
        RenderVideoWithFFMPEG();
        rl.resumeMusicStream(plug_state.music);
    }

    if (rl.isKeyPressed(.space)) {
        plug_state.pause = !plug_state.pause;
        if (plug_state.pause) {
            rl.pauseMusicStream(plug_state.music);
        } else {
            rl.resumeMusicStream(plug_state.music);
        }
    }
}

export fn plugUpdate(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    // Music Polling
    //----------------------------------------------------------------------------------
    rl.updateMusicStream(plug_state.music);
    //----------------------------------------------------------------------------------

    handleInput(plug_state);

    {
        const amplitudes: []const f32 = limitFrequencyRange(plug_state, 200, 3000);

        RenderFrameToTexture(plug_state.texture_target, amplitudes);

        if (plug_state.outputMode == .screen) {
            PrintTextureToScreen(plug_state.texture_target);
        }
    }
}

fn CalculateLinePointPositions(bottom_points: []rl.Vector2, top_points: []rl.Vector2, points_size: usize, point_counter: usize, x_offset: i32, y_offset: i32, posX: i32, posY: i32) void {
    const offset = rl.Vector2.init(@floatFromInt(x_offset), @floatFromInt(y_offset));
    const lastPoint = if (point_counter == 0) rl.Vector2.init(@floatFromInt(posX), @floatFromInt(posY)) else bottom_points[points_size / 2 + point_counter - 1].subtract(offset);
    const previousPosX = @as(i32, @intFromFloat(lastPoint.x));
    const previousPosY = @as(i32, @intFromFloat(lastPoint.y));

    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset + posY));
    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset + posY));

    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(x_offset + posX), @floatFromInt(y_offset - posY));
    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(x_offset - posX), @floatFromInt(y_offset - posY));

    if (global_plug_state.toggleLines) {
        rl.drawLine(x_offset - previousPosX, y_offset - previousPosY, x_offset - posX, y_offset + posY, rl.Color.green);
        rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset + posY, rl.Color.green);
    }
}

fn CalculateCirclePointPositions(bottom_points: []rl.Vector2, top_points: []rl.Vector2, points_size: usize, point_counter: usize, x_offset: i32, y_offset: i32, height: i32, angle: f64) void {
    const base_radius: i32 = 100;
    const inner_radius = base_radius - 80;
    const radius = @as(f64, @floatFromInt(height + base_radius));

    const circle_offset_y = y_offset;
    const circle_offset_x = x_offset;

    const circle_posY = @as(i32, @intFromFloat(radius * std.math.sin(angle)));
    const circle_posX = @as(i32, @intFromFloat(radius * std.math.cos(angle)));

    const inner_circle_posY = @as(i32, @intFromFloat(inner_radius * std.math.sin(angle)));
    const inner_circle_posX = @as(i32, @intFromFloat(inner_radius * std.math.cos(angle)));

    bottom_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y - circle_posY));
    bottom_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x - circle_posX), @floatFromInt(circle_offset_y + circle_posY));

    top_points[points_size / 2 + point_counter] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y - circle_posY));
    top_points[points_size / 2 - point_counter - 1] = rl.Vector2.init(@floatFromInt(circle_offset_x + circle_posX), @floatFromInt(circle_offset_y + circle_posY));

    if (global_plug_state.toggleLines) {
        rl.drawLine(circle_offset_x - inner_circle_posX - @divFloor(circle_posX, 4), circle_offset_y + inner_circle_posY + @divFloor(circle_posY, 4), circle_offset_x - circle_posX, circle_offset_y + circle_posY, rl.Color.green);
        rl.drawLine(circle_offset_x + inner_circle_posX + @divFloor(circle_posX, 4), circle_offset_y + inner_circle_posY + @divFloor(circle_posY, 4), circle_offset_x + circle_posX, circle_offset_y + circle_posY, rl.Color.green);
        rl.drawLine(circle_offset_x - inner_circle_posX - @divFloor(circle_posX, 4), circle_offset_y - inner_circle_posY - @divFloor(circle_posY, 4), circle_offset_x - circle_posX, circle_offset_y - circle_posY, rl.Color.green);
        rl.drawLine(circle_offset_x + inner_circle_posX + @divFloor(circle_posX, 4), circle_offset_y - inner_circle_posY - @divFloor(circle_posY, 4), circle_offset_x + circle_posX, circle_offset_y - circle_posY, rl.Color.green);
    }
}

fn RenderFrameToTexture(texture: rl.RenderTexture, amplitudes: []const f32) void {
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

    var index: u64 = 0;
    const max_amplitude = global_plug_state.max_amplitude;

    var previousPosX: i32 = 0;
    var previousPosY: i32 = 0;

    var point_counter: usize = 0;

    {
        rl.beginTextureMode(texture);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.black);

        while (index < amplitudes.len and samples_per_point > 0 and max_amplitude > 0 and point_counter < points_size / 2) : (index += samples_per_point) {
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

            const height: i32 = @intFromFloat(max_height * global_plug_state.amplify * 1 * ((line_total / @as(f32, @floatFromInt(samples_per_point))) / max_amplitude));

            const posY = height;
            const posX = @as(i32, @intFromFloat(line_step * @as(f64, @floatFromInt(point_counter))));

            if (global_plug_state.renderMode == .lines) {
                CalculateLinePointPositions(&bottom_points, &top_points, points_size, point_counter, x_offset, y_offset, posX, posY);
            } else {
                const angle = circle_angle_step * @as(f64, @floatFromInt(point_counter));

                CalculateCirclePointPositions(&bottom_points, &top_points, points_size, point_counter, x_offset, y_offset, height, angle);
            }

            previousPosX = posX;
            previousPosY = posY;
        }

        rl.drawLineStrip(&bottom_points, rl.Color.green);
        rl.drawLineStrip(&top_points, rl.Color.green);
    }
}

// const image = rl.loadImageFromTexture(texture.texture);
// defer rl.unloadImage(image);
// _ = rl.exportImage(image, "Screen.png");

fn PrintTextureToScreen(texture: rl.RenderTexture) void {
    rl.beginDrawing();
    defer rl.endDrawing();

    if (global_plug_state.shader != null) {
        rl.beginShaderMode(global_plug_state.shader.?.shader);
        defer rl.endShaderMode();
        rl.drawTextureRec(texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    } else {
        rl.drawTextureRec(texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    }
    WriteInfo();
}

fn WriteInfo() void {
    if (global_plug_state.renderInfo) {
        const name = if (global_plug_state.shader) |shader| shader.filename else "None";

        const output = std.fmt.allocPrint(global_plug_state.allocator.*, "Shader: {s}", .{name}) catch @panic("BAD");
        defer global_plug_state.allocator.free(output);
        const text = AdaptString(global_plug_state.allocator, output) catch "ERROR";
        defer global_plug_state.allocator.free(text);

        rl.drawText(text, 10, 30, 16, rl.Color.green);

        const output_amp = std.fmt.allocPrint(global_plug_state.allocator.*, "Amplitude: {d:.2}", .{global_plug_state.amplify}) catch @panic("BAD");
        defer global_plug_state.allocator.free(output_amp);
        const text_amp = AdaptString(global_plug_state.allocator, output_amp) catch "ERROR";
        defer global_plug_state.allocator.free(text_amp);

        rl.drawText(text_amp, 10, 50, 16, rl.Color.green);
    }
}

fn PrintToImage(input_texture: rl.RenderTexture) rl.Image {
    const output_texture = global_plug_state.output_target;
    rl.beginTextureMode(output_texture);

    if (global_plug_state.shader) |shader| {
        rl.beginShaderMode(shader.shader);
        defer rl.endShaderMode();
        rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    } else {
        rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    }
    WriteInfo();

    rl.endTextureMode();

    return rl.loadImageFromTexture(output_texture.texture);
}

fn ClearFFT() void {
    for (0..global_plug_state.samples.len) |i| {
        global_plug_state.samples[i] = 0;
    }
    global_plug_state.samples_writer = 0;
}

fn RenderVideoWithFFMPEG() void {
    const argv = [_][]const u8{ "ffmpeg", "-loglevel", "verbose", "-y", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "1920x1080", "-r", "60", "-i", "-", "-i", "music/MusicMoment.wav", "-c:v", "libx264", "-b:v", "25000k", "-c:a", "aac", "-b:a", "200k", "output.mp4" };
    var proc = std.process.Child.init(&argv, global_plug_state.allocator.*);
    proc.stdin_behavior = .Pipe;
    proc.spawn() catch @panic("Failed ffmpeg launch");

    const audio = rl.loadWave("music/MusicMoment.wav");
    defer rl.unloadWave(audio);

    ClearFFT();

    var processed_frames: usize = 0;
    const frame_rate: usize = 60;
    const frame_count: usize = @intCast(audio.frameCount);
    const sampling_rate: usize = @intCast(audio.sampleRate);
    const sample_buffer = rl.loadWaveSamples(audio);

    const standard_frame_step: usize = @divFloor(sampling_rate, frame_rate);

    std.log.info("\nVisualizer Data: {} {} {} {} {}\n", .{ sample_buffer.len, audio.frameCount, audio.sampleSize, audio.sampleRate, standard_frame_step });

    var frame_step: usize = 0;
    var counter: usize = 0;
    const amplitudes: []const f32 = limitFrequencyRange(global_plug_state, 200, 3000);

    while (frame_count > processed_frames) : (processed_frames += frame_step) {
        defer counter += 1;
        frame_step = if (frame_count - processed_frames > standard_frame_step) standard_frame_step else frame_count - processed_frames;

        RenderFrameToTexture(global_plug_state.texture_target, amplitudes);
        const image = PrintToImage(global_plug_state.texture_target);
        defer rl.unloadImage(image);

        const pixels_raw: [*]const u8 = @ptrCast(@alignCast(image.data));

        const pixels: []const u8 = pixels_raw[0 .. 1920 * 1080 * 4];
        _ = proc.stdin.?.write(pixels) catch @panic("Bad Pipe!");

        const sampled_frames = sample_buffer[processed_frames * audio.channels .. (processed_frames + frame_step) * audio.channels];
        CollectAudioSamplesZig(sampled_frames);
    }
    std.log.info("Ended: Finished Rendering Frames: {}\n", .{counter});

    proc.stdin.?.close();
    proc.stdin = null;

    _ = proc.wait() catch @panic("Can't wait for process.");
    std.log.info("Rendering Done. \n", .{});
}
