const rl = @import("raylib");
const std = @import("std");
const root = @import("root.zig");
const Complex = std.math.Complex;
const testing = std.testing;

const samplesize = std.math.pow(u64, 2, 10);
var global_samples: [samplesize]f32 = [1]f32{0.0} ** samplesize;
var global_complex_samples: [samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** samplesize;
var global_complex_amplitudes: [samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** samplesize;
var global_amplitudes: [samplesize]f32 = [1]f32{0.0} ** samplesize;
var global_max_amplitude: f32 = 0;

var global_samples_writer: u64 = 0;

var plugDrawUI: *const fn (amplitudes_ptr: *anyopaque, size: c_long, max: f32) void = undefined;

fn ComplexAmpToNormalAmp(complex_amplitude: Complex(f32)) f32 {
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

    if (frame_buffer == null) {
        std.log.info("Incorrect Data", .{});
        return;
    }
    var buffer_size = frames * 2;

    if (buffer_size > global_samples.len) {
        buffer_size = global_samples.len;
    }
    const sliced_data = frame_buffer.?[0..buffer_size];

    const availableSpace = global_samples.len - global_samples_writer;

    if (sliced_data.len > availableSpace) {
        const end_samples_to_replace = global_samples[global_samples_writer..];
        std.mem.copyForwards(f32, end_samples_to_replace, sliced_data[0..availableSpace]);

        var remaining_space = sliced_data.len - availableSpace;

        if (remaining_space > global_samples_writer) {
            remaining_space = global_samples_writer;
        }
        const start_samples_to_replace = global_samples[0..remaining_space];
        std.mem.copyForwards(f32, start_samples_to_replace, sliced_data[availableSpace..]);
    } else {
        const sliceToEdit = global_samples[global_samples_writer..];
        std.mem.copyForwards(f32, sliceToEdit, sliced_data);
    }

    global_samples_writer = (global_samples_writer + frames) % global_samples.len;

    for (global_samples, 0..) |sample, i| {
        global_complex_samples[i] = Complex(f32).init(sample, 0);
    }

    root.FT.NoAllocFFT(&global_complex_amplitudes, &global_complex_samples);

    global_max_amplitude = 0;
    for (global_complex_amplitudes, 0..global_complex_amplitudes.len) |complex_amplitude, i| {
        global_amplitudes[i] = ComplexAmpToNormalAmp(complex_amplitude);

        if (global_amplitudes[i] > global_max_amplitude) {
            global_max_amplitude = global_amplitudes[i];
        }
    }
}

pub fn main() anyerror!void {
    loadPlugDll() catch @panic("Failed to load plug.dll");

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1920;
    const screenHeight = 1080;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        if (gpa.deinit() == .leak) {
            std.debug.print("Leaked Memory dumbass.", .{});
        }
    }

    var allocator = gpa.allocator();

    //--------------------------------------------------------------------------------------
    const text = try allocator.alloc(u8, 50);
    defer allocator.free(text);

    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    const music = rl.loadMusicStream("music/MusicMoment.wav");
    defer rl.stopMusicStream(music);

    std.debug.print("Music Frames: {}", .{music.frameCount});

    rl.playMusicStream(music);
    defer rl.stopMusicStream(music);

    rl.attachAudioStreamProcessor(music.stream, CollectAudioSamples);

    rl.initWindow(screenWidth, screenHeight, "Syaliser");
    defer rl.closeWindow(); // Close window and OpenGL context

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Hot Reloading
        //----------------------------------------------------------------------------------
        if (rl.isKeyPressed(.key_f5)) {
            // Unload DLL
            try unloadPlugDll();
            recompilePlugDll(allocator) catch {
                std.debug.print("Failed to recompile game.dll\n", .{});
            };

            // Fetch New DLL
            loadPlugDll() catch @panic("Failed to load game.dll");
        }

        // Music Polling
        //----------------------------------------------------------------------------------
        // plugProcessAudio();
        rl.updateMusicStream(music);

        // Draw
        //----------------------------------------------------------------------------------
        {
            rl.beginDrawing();
            defer rl.endDrawing();

            plugDrawUI(&global_amplitudes, samplesize, global_max_amplitude);
        }
        //----------------------------------------------------------------------------------
    }
}

var plug_dyn_lib: ?std.DynLib = null;
fn loadPlugDll() !void {
    // TODO: implement
    if (plug_dyn_lib != null) return error.AlreadyLoaded;
    var dyn_lib = std.DynLib.open("zig-out/bin/syalizer.plug.dll") catch {
        return error.OpenFail;
    };

    plug_dyn_lib = dyn_lib;
    plugDrawUI = dyn_lib.lookup(@TypeOf(plugDrawUI), "plugDrawUI") orelse return error.LookupFail;
    std.debug.print("Loaded plug.dll\n", .{});
}

fn unloadPlugDll() !void {
    if (plug_dyn_lib) |*dyn_lib| {
        dyn_lib.close();
        plug_dyn_lib = null;
    } else {
        return error.AlreadyUnloaded;
    }
}

fn recompilePlugDll(allocator: std.mem.Allocator) !void {
    const process_args = [_][]const u8{
        "zig",
        "build",
        "-Dplug_only=true", // This '=true' is important!+
    };
    var build_process = std.process.Child.init(&process_args, allocator);
    try build_process.spawn();
    // wait() returns a tagged union. If the compilations fails that union
    // will be in the state .{ .Exited = 2 }
    const term = try build_process.wait();
    switch (term) {
        .Exited => |exited| {
            if (exited == 2) return error.RecompileFail;
        },
        else => return,
    }

    // delete old dll

    try std.fs.cwd().deleteFile("./zig-out/bin/syalizer.plug.dll");
    try std.fs.cwd().rename("./zig-out/bin/syalizer.plug.next.dll", "./zig-out/bin/syalizer.plug.dll");
}
