const std = @import("std");
const testing = std.testing;
const Complex = std.math.Complex;
const rl = @import("raylib");
const root = @import("root.zig");

const PlugState = root.PlugState;

inline fn ComplexAmpToNormalAmp(complex_amplitude: Complex(f32)) f32 {
    var real = complex_amplitude.re;
    var imag = complex_amplitude.im;

    if (real < 0) real = real * -1;
    if (imag < 0) imag = imag * -1;

    if (real > imag) {
        return real;
    }

    return imag;
}

fn CollectAudioSamples(buffer: ?*anyopaque, frames: c_uint) callconv(.C) void {
    const frame_buffer: ?[*]const f32 = @ptrCast(@alignCast(buffer.?));

    if (root.global_plug_state.isHotReloading) {
        return;
    }

    if (frame_buffer == null) {
        std.log.info("Incorrect Data", .{});
        return;
    }

    root.global_plug_state.canHotReload = false;

    var buffer_size = frames * 2;

    if (buffer_size > root.global_plug_state.samples.len) {
        buffer_size = root.global_plug_state.samples.len;
    }
    const sliced_data = frame_buffer.?[0..buffer_size];
    const availableSpace = root.global_plug_state.samples.len - root.global_plug_state.samples_writer;

    if (sliced_data.len > availableSpace) {
        const end_samples_to_replace = root.global_plug_state.samples[root.global_plug_state.samples_writer..];
        std.mem.copyForwards(f32, end_samples_to_replace, sliced_data[0..availableSpace]);

        var remaining_space = sliced_data.len - availableSpace;

        if (remaining_space > root.global_plug_state.samples_writer) {
            remaining_space = root.global_plug_state.samples_writer;
        }
        const start_samples_to_replace = root.global_plug_state.samples[0..remaining_space];
        std.mem.copyForwards(f32, start_samples_to_replace, sliced_data[availableSpace..]);
    } else {
        const sliceToEdit = root.global_plug_state.samples[root.global_plug_state.samples_writer..];
        std.mem.copyForwards(f32, sliceToEdit, sliced_data);
    }

    root.global_plug_state.samples_writer = (root.global_plug_state.samples_writer + frames) % root.global_plug_state.samples.len;

    for (root.global_plug_state.samples, 0..) |sample, i| {
        root.global_plug_state.complex_samples[i] = Complex(f32).init(sample, 0);
    }

    root.FT.NoAllocFFT(&root.global_plug_state.complex_amplitudes, &root.global_plug_state.complex_samples);

    root.global_plug_state.max_amplitude = 0;
    for (root.global_plug_state.complex_amplitudes, 0..root.global_plug_state.complex_amplitudes.len) |complex_amplitude, i| {
        root.global_plug_state.amplitudes[i] = ComplexAmpToNormalAmp(complex_amplitude);

        if (root.global_plug_state.amplitudes[i] > root.global_plug_state.max_amplitude) {
            root.global_plug_state.max_amplitude = root.global_plug_state.amplitudes[i];
        }
    }

    root.global_plug_state.canHotReload = true;
}

export fn plugClose(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    rl.stopMusicStream(plug_state.music);
    rl.detachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);
}

export fn plugInit(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    root.global_plug_state = plug_state;

    plug_state.music = rl.loadMusicStream("music/MusicMoment.wav");
    rl.attachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);

    std.debug.print("Music Frames: {}", .{plug_state.music.frameCount});
    rl.playMusicStream(plug_state.music);
}

export fn startHotReloading(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    _ = plug_state;
    std.log.debug("Detached Audio", .{});
}

export fn endHotReloading(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    root.global_plug_state = plug_state;

    std.log.debug("Ended Hot reloading", .{});
}

export fn plugUpdate(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    {
        rl.beginDrawing();
        defer rl.endDrawing();

        const amplitudes: []const f32 = &plug_state.*.amplitudes;

        rl.clearBackground(rl.Color.black);

        const amount_of_lines: u64 = 100;
        const samples_per_line: u64 = (amplitudes.len / 2) / amount_of_lines;

        const half_screen: f64 = @as(f64, @floatFromInt(rl.getRenderWidth())) / 2;
        const cell_width: f64 = half_screen / @as(f64, @floatFromInt(amount_of_lines));
        const cell_height: f64 = @as(f64, @floatFromInt(rl.getRenderHeight())) / 2.0;

        var x: f64 = 0;

        var index: u64 = 0;
        const max_amplitude = plug_state.max_amplitude;
        while (index < amplitudes.len / 2 and samples_per_line > 0 and max_amplitude > 0) : (index += samples_per_line) {
            var line_total: f64 = 0;

            var stop = index + samples_per_line;

            if (stop > amplitudes.len / 2) {
                stop = amplitudes.len / 2;
            }

            for (index..stop) |value| {
                const amplitude = amplitudes[value];
                line_total += amplitude;
            }

            const height: i32 = @intFromFloat(cell_height * ((line_total / @as(f32, @floatFromInt(samples_per_line))) / max_amplitude));
            const posY = @as(i32, @intFromFloat(cell_height));

            rl.drawRectangle(@intFromFloat(half_screen + x), posY, @intFromFloat(cell_width), height, rl.Color.green);
            rl.drawRectangle(@intFromFloat(half_screen - x), posY, @intFromFloat(cell_width), height, rl.Color.yellow);
            rl.drawRectangle(@intFromFloat(half_screen + x), posY - height, @intFromFloat(cell_width), height, rl.Color.pink);
            rl.drawRectangle(@intFromFloat(half_screen - x), posY - height, @intFromFloat(cell_width), height, rl.Color.pink);

            x += cell_width;
        }

        rl.drawFPS(10, 100);
    }
}
