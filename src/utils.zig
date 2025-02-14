const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");

pub fn init(x: i32, y: i32, width: i32, height: i32) rl.Rectangle {
    return rl.Rectangle.init(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height));
}
