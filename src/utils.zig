const std = @import("std");
const rl = @import("raylib");

pub fn initRectangle(x: i32, y: i32, width: i32, height: i32) rl.Rectangle {
    return rl.Rectangle.init(@floatFromInt(x), @floatFromInt(y), @floatFromInt(width), @floatFromInt(height));
}

var zero_terminated_buffer: [1024]u8 = [1]u8{0} ** 1024;

pub fn adaptString(text: []const u8) [:0]const u8 {
    std.mem.copyForwards(u8, &zero_terminated_buffer, text);
    zero_terminated_buffer[text.len] = 0;
    return zero_terminated_buffer[0..text.len :0];
}

pub fn adaptStringAlloc(allocator: std.mem.Allocator, text: []const u8) ![:0]const u8 {
    var zero_terminated_text = try allocator.alloc(u8, text.len + 1);
    std.mem.copyForwards(u8, zero_terminated_text, text);
    zero_terminated_text[text.len] = 0;
    return zero_terminated_text[0..text.len :0];
}
