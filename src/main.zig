const rl = @import("raylib");
const std = @import("std");
const root = @import("root.zig");
const plug = @import("plug.zig");
const Complex = std.math.Complex;
const testing = std.testing;
const PlugState = plug.PlugState;

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

    //-------------------------------------------------------------------------------------
    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    rl.initWindow(screenWidth, screenHeight, "Syaliser");
    defer rl.closeWindow(); // Close window and OpenGL context

    state = try PlugState.init(&allocator, 12);
    const state_ptr: *anyopaque = @ptrCast(&state);

    plugInit(state_ptr);
    defer plugClose(state_ptr);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Hot Reloading
        //----------------------------------------------------------------------------------
        if (rl.isKeyPressed(.f5)) {
            std.log.debug("RELOADING", .{});

            // Unload DLL
            startHotReloading(state_ptr);

            // Fetch New DLL
            try unloadPlugDll();

            try recompilePlugDll(allocator);

            loadPlugDll() catch @panic("Failed to load game.dll");

            endHotReloading(state_ptr);
            std.log.debug("FINISHED RELOADING", .{});
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
fn loadPlugDll() !void {
    if (plug_dyn_lib != null) @panic("Invalid Behavior");

    var dyn_lib: std.DynLib = undefined;
    dyn_lib = std.DynLib.open("syalizer.plug.dll") catch {
        return error.OpenFail;
    };

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

fn recompilePlugDll(alloc: std.mem.Allocator) !void {
    // the command to run
    const argv = [_][]const u8{ "zig", "build", "-Dplug_only=true" };

    // init a ChildProcess... cleanup is done by calling wait().
    var proc = std.process.Child.init(&argv, alloc);

    try proc.spawn();
    // wait() returns a tagged union. If the compilations fails that union
    // will be in the state .{ .Exited = 2 }
    const term = try proc.wait();
    switch (term) {
        .Exited => |exited| {
            if (exited == 2) return error.RecompileFail;
        },
        else => return,
    }
}
