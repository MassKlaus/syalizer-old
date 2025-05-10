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
    const allocator = gpa.allocator();

    defer {
        if (gpa.deinit() == .leak) {
            std.log.info("Memory is leaking.", .{});
        }
    }

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1920;
    const screenHeight = 1080;

    //-------------------------------------------------------------------------------------
    rl.initWindow(screenWidth, screenHeight, "Syaliser");

    rl.initAudioDevice();
    defer rl.closeAudioDevice();

    state = PlugState.init(allocator, 12) catch @panic("State failed to initialize.");
    const state_ptr: *PlugState = &state;

    plug.plugInit(state_ptr);
    defer plug.plugClose(state_ptr);

    // Main game loop
    state_ptr.log("Loop start", .{}, false);
    while (!(rl.windowShouldClose() or state_ptr.close)) { // Detect window close button or ESC key

        //----------------------------------------------------------------------------------
        plug.plugUpdate(state_ptr);
        //----------------------------------------------------------------------------------

    }
}
