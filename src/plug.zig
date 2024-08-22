const std = @import("std");
const testing = std.testing;
const Complex = std.math.Complex;
const rl = @import("raylib");
const root = @import("root.zig");

export fn plugDrawUI(amplitudes_ptr: *anyopaque, size: c_uint, max: f32) void {
    const buffer: [*]const f32 = @ptrCast(@alignCast(amplitudes_ptr));
    const amplitudes: []const f32 = buffer[0..size];

    rl.clearBackground(rl.Color.black);

    const amount_of_lines: u64 = 100;
    const samples_per_line: u64 = (amplitudes.len / 2) / amount_of_lines;

    const half_screen: f64 = @as(f64, @floatFromInt(rl.getRenderWidth())) / 2;
    const cell_width: f64 = half_screen / @as(f64, @floatFromInt(amount_of_lines));
    const cell_height: f64 = @as(f64, @floatFromInt(rl.getRenderHeight())) / 2.0;

    var x: f64 = 0;

    var index: u64 = 0;
    while (index < amplitudes.len / 2 and samples_per_line > 0 and max > 0) : (index += samples_per_line) {
        var line_total: f64 = 0;

        var stop = index + samples_per_line;

        if (stop > amplitudes.len / 2) {
            stop = amplitudes.len / 2;
        }

        for (index..stop) |value| {
            const amplitude = amplitudes[value];
            line_total += amplitude;
        }

        const height: i32 = @intFromFloat(cell_height * ((line_total / @as(f32, @floatFromInt(samples_per_line))) / max));
        const posY = @as(i32, @intFromFloat(cell_height));

        rl.drawRectangle(@intFromFloat(half_screen + x), posY, @intFromFloat(cell_width), height, rl.Color.pink);
        rl.drawRectangle(@intFromFloat(half_screen - x), posY, @intFromFloat(cell_width), height, rl.Color.pink);
        rl.drawRectangle(@intFromFloat(half_screen + x), posY - height, @intFromFloat(cell_width), height, rl.Color.blue);
        rl.drawRectangle(@intFromFloat(half_screen - x), posY - height, @intFromFloat(cell_width), height, rl.Color.blue);

        x += cell_width;
    }

    rl.drawText("Datasss", 190, 200, 20, rl.Color.light_gray);
}

var music: ?rl.Music = null;
