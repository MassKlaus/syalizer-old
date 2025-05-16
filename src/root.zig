const std = @import("std");
const root = @import("root.zig");
const rl = @import("raylib");
const Complex = std.math.Complex;
const testing = std.testing;

fn bitSwap(x: usize, bits: usize) usize {
    var result: usize = 0;
    for (0..bits) |i| {
        const shift: u6 = @intCast(i);
        const bit = (x >> shift) & 1;
        const opposite_shift: u6 = @intCast(bits - 1 - i);
        result |= (bit << opposite_shift);
    }

    return result;
}

inline fn bitCount(size: usize) usize {
    return std.math.log2(size);
}

pub const FT = struct {
    pub fn FFT(allocator: std.mem.Allocator, input: []Complex(f32)) ![]Complex(f32) {
        const output = try allocator.alloc(Complex(f32), input.len);

        NoAllocFFT(input, output);

        return output;
    }

    pub fn NoAllocFFT(input: []Complex(f32), output: []Complex(f32)) void {
        for (0..input.len) |i| {
            output[i] = input[i];
        }

        _FFT(output);
    }

    fn _FFT(data: []Complex(f32)) void {
        const size = data.len;
        const bits: usize = bitCount(size);

        for (0..size) |i| {
            const j: usize = bitSwap(i, bits);

            if (i < j) {
                const temp = data[j];
                data[j] = data[i];
                data[i] = temp;
            }
        }

        var s: usize = 1;
        while (s <= bits) : (s += 1) {
            const m = @as(usize, 1) << @intCast(s);
            const m_half = m / 2;
            const wlen = std.math.complex.exp(Complex(f32).init(0, -2 * std.math.pi / @as(f32, @floatFromInt(m))));

            var k: usize = 0;
            while (k < size) : (k += m) {
                var w = Complex(f32).init(1, 0);

                var j: usize = 0;
                while (j < m_half) : (j += 1) {
                    const u = data[k + j];
                    const v = data[k + j + m_half].mul(w);
                    data[k + j] = u.add(v);
                    data[k + j + m_half] = u.sub(v);
                    w = w.mul(wlen);
                }
            }
        }
    }

    pub fn NoAllocDFT(input: []Complex(f32), output: []Complex(f32)) void {
        const size_float = @as(f32, @floatFromInt(output.len));

        // k is the frency we are studying
        for (0..input.len) |k| {
            const k_float: f32 = @floatFromInt(k);
            output[k] = Complex(f32).init(0, 0);

            // t is the temporal offset in the list of inputs
            for (0..input.len) |t| {
                const t_float: f32 = @floatFromInt(t);
                const angle = std.math.complex.exp(Complex(f32).init(0, -2 * std.math.pi * k_float * t_float / size_float));

                // multiply the input with the offset sin wave to see if it is within range of the wanted frequency
                output[k] = output[k].add(input[t].mul(angle));
            }
        }
    }

    pub fn DFT(allocator: std.mem.Allocator, input: []Complex(f32)) !([]Complex(f32)) {
        const amplitudes = try allocator.alloc(Complex(f32), input.len);

        NoAllocDFT(input, amplitudes);

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

    const DFTamplitudes = try FT.DFT(testalloc, wave);
    defer testalloc.free(DFTamplitudes);

    const FFTamplitudes = try FT.FFT(testalloc, wave);
    defer testalloc.free(FFTamplitudes);

    for (FFTamplitudes, DFTamplitudes) |FFTamplitude, DFTamplitude| {
        const FFT_re = std.math.round(FFTamplitude.re);
        const FFT_im = std.math.round(FFTamplitude.im);

        const DFT_re = std.math.round(DFTamplitude.re);
        const DFT_im = std.math.round(DFTamplitude.im);

        try testing.expect(FFT_re == DFT_re and FFT_im == DFT_im);
    }
}
