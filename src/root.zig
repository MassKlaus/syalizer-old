const std = @import("std");
const Complex = std.math.Complex;
const testing = std.testing;

pub const FT = struct {
    pub fn FFT(allocator: std.mem.Allocator, input: []Complex(f32)) ![]Complex(f32) {
        var output = try allocator.alloc(Complex(f32), input.len);

        for (0..input.len) |i| {
            output[i] = input[i];
        }

        _FFT(input, 1, output, input.len);

        return output;
    }

    pub fn NoAllocFFT(output: []Complex(f32), input: []Complex(f32)) void {
        for (0..input.len) |i| {
            output[i] = input[i];
        }

        _FFT(input, 1, output, input.len);
    }

    fn _FFT(input: []Complex(f32), stride: u32, output: []Complex(f32), size: usize) void {
        if (size <= 1) {
            output[0] = input[0];
            return;
        }

        _FFT(input, stride * 2, output, size / 2);

        var odd_input = input;
        odd_input.ptr = input.ptr + stride;
        odd_input.len = input.len - stride;

        var odd_output = output;
        odd_output.ptr = output.ptr + size / 2;
        odd_output.len = output.len - size / 2;
        _FFT(odd_input, stride * 2, odd_output, size / 2);

        var k: u32 = 0;
        while (k < size / 2) : (k += 1) {
            const t: f32 = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(size));
            const v = std.math.complex.exp(Complex(f32).init(0, 2 * std.math.pi * t)).mul(output[k + size / 2]);
            const e = output[k];

            output[k] = e.add(v);
            output[k + size / 2] = e.sub(v);
        }
    }

    pub fn DFT(allocator: std.mem.Allocator, input: []Complex(f32)) !([]Complex(f32)) {
        var amplitudes = try allocator.alloc(Complex(f32), input.len);

        const time_base = @as(f32, 1.0 / @as(f32, @floatFromInt(input.len)));

        for (0..input.len) |frequency| {
            amplitudes[frequency] = Complex(f32).init(0, 0);

            const frequency_f = @as(f32, @floatFromInt(frequency));

            for (input, 0..) |sample, i| {
                const time = time_base * @as(f32, @floatFromInt(i));

                amplitudes[frequency] = amplitudes[frequency].add(std.math.complex.exp(Complex(f32).init(0, std.math.pi * 2 * time * frequency_f)).mul(sample));
            }
        }

        return amplitudes;
    }
};

fn GenerateComplexTestWave(allocator: std.mem.Allocator, size: u32) ![]Complex(f32) {
    var samples = try allocator.alloc(Complex(f32), size);

    const time_base = @as(f32, 1.0 / @as(f32, @floatFromInt(size)));

    for (0..size) |i| {
        const time = time_base * @as(f32, @floatFromInt(i));
        samples[i] = Complex(f32).init(std.math.cos(time * std.math.pi * 2) + std.math.sin(time * std.math.pi * 2 * 2), 0);
    }

    return samples;
}

test "testing fast fourier implementation" {
    const testalloc = testing.allocator;

    const wave = try GenerateComplexTestWave(testalloc, 16);
    defer testalloc.free(wave);

    const amplitudes = try FT.DFT(testalloc, wave);
    defer testalloc.free(amplitudes);

    for (amplitudes, 0..) |amplitude, i| {
        std.debug.print("{:0>2}: {d: ^8.2} | {d: ^8.2}\n", .{ i, std.math.round(amplitude.re), std.math.round(amplitude.im) });
    }

    const fftAmplitudes = try FT.FFT(testalloc, wave);
    defer testalloc.free(fftAmplitudes);

    for (fftAmplitudes, amplitudes, 0..) |amplitude, examplitude, i| {
        std.debug.print("{:0>2}: {d: ^8.2} | {d: ^8.2} || {d: ^8.2} | {d: ^8.2} \n", .{ i, std.math.round(amplitude.re), std.math.round(amplitude.im), std.math.round(examplitude.re), std.math.round(examplitude.im) });
    }
}
