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
    rl.clearBackground(plug_state.settings.back_color);

    handleSettingsInput(plug_state);

    rl.beginDrawing();
    rl.endDrawing();
}
