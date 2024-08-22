const rl = @import("raylib");
const std = @import("std");
const root = @import("root.zig");
const Complex = std.math.Complex;
const testing = std.testing;
const PlugState = root.PlugState;

var plugUpdate: *const fn (plug_state_ptr: *anyopaque) void = undefined;
var plugInit: *const fn (plug_state_ptr: *anyopaque) void = undefined;
var plugClose: *const fn (plug_state_ptr: *anyopaque) void = undefined;
var startHotReloading: *const fn (allocator_ptr: *anyopaque) void = undefined;
var endHotReloading: *const fn (allocator_ptr: *anyopaque) void = undefined;

var state: PlugState = undefined;

pub fn main() anyerror!void {
    loadPlugDll() catch @panic("Failed to load plug.dll");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    defer {
        if (gpa.deinit() == .leak) {
            std.log.debug("Memory is leaking.", .{});
        }
    }

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1920;
    const screenHeight = 1080;

    state = PlugState{ .allocator = &allocator, .music = undefined };
    const state_ptr: *anyopaque = @ptrCast(&state);

    //-------------------------------------------------------------------------------------
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.initWindow(screenWidth, screenHeight, "Syaliser");
    defer rl.closeWindow(); // Close window and OpenGL context

    plugInit(state_ptr);
    defer plugClose(state_ptr);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    var wants_to_hotreload = false;

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Hot Reloading
        //----------------------------------------------------------------------------------
        if (rl.isKeyPressed(.key_f5)) {
            std.log.debug("RELOADING", .{});
            state.isHotReloading = true;
            wants_to_hotreload = true;
        }

        if (wants_to_hotreload and state.canHotReload) {
            std.log.debug("RELOADING", .{});

            // Unload DLL
            startHotReloading(state_ptr);

            try recompilePlugDll();

            // Fetch New DLL
            try unloadPlugDll();
            loadPlugDll() catch @panic("Failed to load game.dll");

            endHotReloading(state_ptr);

            wants_to_hotreload = false;
            state.isHotReloading = false;
        }

        // Music Polling
        //----------------------------------------------------------------------------------
        rl.updateMusicStream(state.music);
        //----------------------------------------------------------------------------------

        plugUpdate(state_ptr);

        //----------------------------------------------------------------------------------

    }
}

var plug_dyn_lib: ?std.DynLib = null;
var toggle = true;
fn loadPlugDll() !void {
    if (plug_dyn_lib != null) @panic("Invalid Behavior");

    var dyn_lib: std.DynLib = undefined;
    if (toggle) {
        dyn_lib = std.DynLib.open("syalizer.plug.dll") catch {
            return error.OpenFail;
        };
    } else {
        dyn_lib = std.DynLib.open("syalizer.plug.next.dll") catch {
            return error.OpenFail;
        };
    }
    toggle = !toggle;

    plug_dyn_lib = dyn_lib;
    plugUpdate = dyn_lib.lookup(@TypeOf(plugUpdate), "plugUpdate") orelse return error.LookupFail;
    plugInit = dyn_lib.lookup(@TypeOf(plugInit), "plugInit") orelse return error.LookupFail;
    plugClose = dyn_lib.lookup(@TypeOf(plugClose), "plugClose") orelse return error.LookupFail;
    startHotReloading = dyn_lib.lookup(@TypeOf(startHotReloading), "startHotReloading") orelse return error.LookupFail;
    endHotReloading = dyn_lib.lookup(@TypeOf(endHotReloading), "endHotReloading") orelse return error.LookupFail;

    std.debug.print("Loaded plug.dll\n", .{});
}

fn unloadPlugDll() !void {
    if (plug_dyn_lib) |*dyn_lib| {
        dyn_lib.close();
        plug_dyn_lib = null;
        plugUpdate = undefined;
        plugInit = undefined;
        plugClose = undefined;
        startHotReloading = undefined;
        endHotReloading = undefined;
    } else {
        return error.AlreadyUnloaded;
    }
}

fn recompilePlugDll() !void {}
