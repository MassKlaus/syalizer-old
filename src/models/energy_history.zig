const Self = @This();

pub const default_block_count = 43;

energy_blocks: std.ArrayListUnmanaged(f32),
contains_beat: bool = false,

pub fn init(buffer: []f32) Self {
    return .{ .energy_blocks = std.ArrayListUnmanaged(f32).initBuffer(buffer) };
}

pub fn pushEnergyBlock(self: *Self, energy: f32) void {
    self.contains_beat = self.isItABeat(energy);

    if (self.energy_blocks.items.len == self.energy_blocks.capacity) {
        std.mem.rotate(f32, self.energy_blocks.items, 1);
        _ = self.energy_blocks.pop();
    }

    self.energy_blocks.appendAssumeCapacity(energy);
}

pub fn isItABeat(self: *Self, energy_block: f32) bool {
    var sum: f32 = 0.0;
    for (self.energy_blocks.items) |block| {
        sum += block;
    }

    const average_energy = sum / @as(f32, @floatFromInt(self.energy_blocks.items.len));

    var variance: f32 = 0.0;
    for (self.energy_blocks.items) |block| {
        variance += (block - average_energy) * (block - average_energy);
    }

    variance = variance / @as(f32, @floatFromInt(self.energy_blocks.items.len));

    const c = std.math.clamp((-0.0025714 * variance) + 1.5142857, 1.3, 1.7);

    return energy_block > c * average_energy;
}

const std = @import("std");
