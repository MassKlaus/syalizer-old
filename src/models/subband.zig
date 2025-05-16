const Self = @This();

fft_band: []f32,
history: EnergyHistory,

pub fn init(band: []f32, buffer: []f32) Self {
    return .{
        .history = EnergyHistory.init(buffer),
        .fft_band = band,
    };
}

pub fn extractBlockAndAppend(self: *Self) void {
    var energy_block: f32 = 0.0;

    for (self.fft_band) |amplitude| {
        energy_block += amplitude;
    }

    energy_block /= @floatFromInt(self.fft_band.len);

    self.history.pushEnergyBlock(energy_block);
}

const EnergyHistory = @import("energy_history.zig");
