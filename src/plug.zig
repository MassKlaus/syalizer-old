const std = @import("std");
const testing = std.testing;
const Complex = std.math.Complex;
const rl = @import("raylib");
const root = @import("root.zig");

pub var global_plug_state: *PlugState = undefined;
const samplesize = std.math.pow(u64, 2, 12);

pub const PlugState = struct {
    allocator: *std.mem.Allocator,
    samples: [samplesize]f32 = [1]f32{0.0} ** samplesize,
    complex_samples: [samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** samplesize,
    complex_amplitudes: [samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** samplesize,
    amplitudes: [samplesize]f32 = [1]f32{0.0} ** samplesize,
    max_amplitude: f32 = 0,
    samples_writer: u64 = 0,
    music: rl.Music,
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

    var buffer_size = frames * 2;

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

    root.FT.NoAllocFFT(&global_plug_state.complex_amplitudes, &global_plug_state.complex_samples);

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
}

export fn plugInit(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));
    global_plug_state = plug_state;

    plug_state.music = rl.loadMusicStream("music/MusicMoment.wav");
    rl.attachAudioStreamProcessor(plug_state.music.stream, CollectAudioSamples);

    std.debug.print("Music Frames: {}", .{plug_state.music.frameCount});
    rl.playMusicStream(plug_state.music);
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

fn limitAmplitudeRange(plug_state: *PlugState, min: u64, max: u64) []const f32 {
    const amplitudes = &plug_state.*.amplitudes;
    const valid_amps = amplitudes[0 .. (amplitudes.len / 2) + 1];
    const frequency_step = global_plug_state.music.stream.sampleRate / samplesize;

    const min_index = @divFloor(min, frequency_step);
    var max_index = @divFloor(max, frequency_step);

    if (max_index >= valid_amps.len) {
        max_index = valid_amps.len;
    } else {
        max_index += 1;
    }

    return valid_amps[min_index..max_index];
}

export fn plugUpdate(plug_state_ptr: *anyopaque) void {
    const plug_state: *PlugState = @ptrCast(@alignCast(plug_state_ptr));

    {
        rl.beginDrawing();
        defer rl.endDrawing();

        const amplitudes: []const f32 = limitAmplitudeRange(plug_state, 200, 1500);

        rl.clearBackground(rl.Color.black);

        const amount_of_points: u64 = 50;
        const samples_per_point: u64 = (amplitudes.len) / amount_of_points;

        const line_length: f64 = @as(f64, @floatFromInt(rl.getRenderWidth())) / 2.0;
        const point_gap: f64 = line_length / @as(f64, @floatFromInt(amount_of_points));
        const y_offset: i32 = @as(i32, @divFloor(rl.getRenderHeight(), 2));
        const x_offset: i32 = @intFromFloat(line_length);
        const max_height: f64 = @as(f64, @floatFromInt(rl.getRenderHeight())) / 3.0;
        var x: f64 = 0;

        var index: u64 = 0;
        const max_amplitude = plug_state.max_amplitude;

        var previousPosX: i32 = 0;
        var previousPosY: i32 = 0;

        var first_point = true;

        while (index < amplitudes.len and samples_per_point > 0 and max_amplitude > 0) : (index += samples_per_point) {
            defer x += point_gap;

            var line_total: f64 = 0;

            var stop = index + samples_per_point;

            if (stop > amplitudes.len) {
                stop = amplitudes.len;
            }

            for (index..stop) |value| {
                const amplitude = amplitudes[value];
                line_total += amplitude;
            }

            const height: i32 = @intFromFloat(max_height * 1 * ((line_total / @as(f32, @floatFromInt(samples_per_point))) / max_amplitude));
            const posY = height;
            const posX = @as(i32, @intFromFloat(x));

            if (first_point) {
                previousPosX = posX;
                previousPosY = posY;
                first_point = false;
            }

            rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset - posY, rl.Color.green);
            rl.drawLine(x_offset + previousPosX, y_offset + previousPosY, x_offset + posX, y_offset + posY, rl.Color.green);

            rl.drawLine(x_offset - previousPosX, y_offset - previousPosY, x_offset - posX, y_offset + posY, rl.Color.green);
            rl.drawLine(x_offset + previousPosX, y_offset - previousPosY, x_offset + posX, y_offset + posY, rl.Color.green);

            rl.drawLine(x_offset - previousPosX, y_offset - previousPosY, x_offset - posX, y_offset - posY, rl.Color.green);
            rl.drawLine(x_offset - previousPosX, y_offset + previousPosY, x_offset - posX, y_offset + posY, rl.Color.green);

            previousPosX = posX;
            previousPosY = posY;
        }

        rl.drawFPS(10, 100);
    }
}
