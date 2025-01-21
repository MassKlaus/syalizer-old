const std = @import("std");
const plug = @import("../plug.zig");
const PlugState = plug.PlugState;
const rl = @import("raylib");
const rg = @import("raygui");

fn handleSettingsInput(plug_state: *PlugState) void {
    if (rl.isKeyPressed(.escape)) {
        plug_state.goBack();
    }
}

pub fn RenderSettingsPage(plug_state: *PlugState) void {
    defer handleSettingsInput(plug_state);

    {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(plug_state.settings.back_color);

        _ = rg.guiButton(rl.Rectangle.init(10, 10, 50, 50), "<");
        _ = rg.guiButton(rl.Rectangle.init(110, 10, 50, 50), ">");
    }
}
