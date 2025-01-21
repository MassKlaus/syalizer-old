const rl = @import("raylib");
const std = @import("std");
const root = @import("root.zig");
const plug = @import("plug.zig");
const builtin = @import("builtin");
const Complex = std.math.Complex;
const testing = std.testing;
const PlugState = plug.PlugState;

var state: PlugState = undefined;

pub fn main() anyerror!void {
    // loadPlugDll() catch @panic("Failed to load plug.dll");

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

    state = try PlugState.init(&allocator, 12);
    const state_ptr: *PlugState = &state;

    state_ptr.log("Here", .{}, false);

    plug.plugInit(state_ptr);
    defer plug.plugClose(state_ptr);

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Hot Reloading
        //----------------------------------------------------------------------------------
        plug.plugUpdate(state_ptr);
        //----------------------------------------------------------------------------------
    }
}
