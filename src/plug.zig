const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const testing = std.testing;
const Complex = std.math.Complex;
const root = @import("root.zig");
const visualizer = @import("pages/visualizer.zig");
const utils = @import("./utils.zig");
const menu = @import("pages/selection_menu.zig");
const settings_page = @import("pages/settings.zig");
const Subbands = @import("./models/subband.zig");
const EnergyHistory = @import("./models/energy_history.zig");

var global_plug_state: *PlugState = undefined;

const max_level = 20;
const max_samplesize = std.math.pow(u64, 2, max_level);

const subband_count: u64 = 64;
const sample_block_size: u64 = 1024;

pub var text_buffer: [1024]u8 = [1]u8{0} ** 1024;

// TODO: Check data re-ordering
pub const PlugState = struct {
    const PlugError = error{TooLarge};

    pub const RenderModes = enum(u8) {
        lines = 0,
        circle = 1,
        bars = 2,
    };

    pub const RenderOutput = enum(u8) {
        screen = 0,
        video = 1,
    };

    pub const Pages = enum {
        SelectionMenu,
        Visualizer,
        Settings,
    };

    pub const ProcessingMode = enum(u8) {
        normal = 0,
        log,
        smooth,
        smear,
    };

    pub const ShaderInfo = struct {
        shader: rl.Shader,
        filename: [:0]const u8,
    };

    pub const SongInfo = struct {
        path: [:0]const u8,
        filename: [:0]const u8,
    };

    const PlugCore = struct {
        temp_buffer: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        samples: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        smooth_samples: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        complex_samples: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        complex_amplitudes: [max_samplesize]Complex(f32) = [1]Complex(f32){Complex(f32).init(0, 0)} ** max_samplesize,
        amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        log_amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        smear_amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,
        smooth_amplitudes: [max_samplesize]f32 = [1]f32{0.0} ** max_samplesize,

        // sound energy for beat detection
        energy_blocks: [EnergyHistory.default_block_count * subband_count]f32 = [1]f32{0.0} ** (EnergyHistory.default_block_count * subband_count),
        subbands: [subband_count]Subbands,

        //fft sound energy beat detection

    };

    const UserSettings = struct {
        front_color: rl.Color,
        back_color: rl.Color,
        focused_color: rl.Color,
        pressed_color: rl.Color,
        border_color: rl.Color,
        fps: i32,
        background: ?[]u8,

        pub fn init() UserSettings {
            return .{
                .front_color = rl.Color.green,
                .back_color = rl.Color.black,
                .border_color = rl.Color.green,
                .focused_color = rl.Color.lime,
                .pressed_color = rl.Color.dark_green,
                .fps = 60,
                .background = null,
            };
        }
    };

    // hardcoded arrays
    core: *PlugCore,

    allocator: std.mem.Allocator,

    // Buffers holding the different data used to render the sound
    samplesize: u64,
    temp_buffer: []f32,
    samples: []f32,
    smooth_samples: []f32,
    complex_samples: []Complex(f32),
    complex_amplitudes: []Complex(f32),
    amplitudes: []f32,
    log_amplitudes: []f32,
    smear_amplitudes: []f32,
    smooth_amplitudes: []f32,

    subbands: []Subbands,

    max_amplitude: f32 = 0,
    max_log_amplitude: f32 = 0,
    max_smooth_amplitude: f32 = 0,
    max_smear_amplitude: f32 = 0,
    energy_block_index: u64 = 0,
    sample_accumulator: u64 = 0,
    energy_block_counter: u64 = 0,
    is_a_beat: bool = false,

    // Output amplifier
    amplify: f32 = 1,

    // Music Currently Handling
    music: ?rl.Music = null,
    music_volume: f32 = 50,
    songs: []SongInfo,
    song: ?*SongInfo = null,
    preview_song: ?*SongInfo = null,
    preview_audio: ?rl.Wave = null,
    preview_audio_data: []f32 = undefined,

    // Collection Of Shaders
    shaders: []ShaderInfo,

    background_texture: ?rl.Texture2D = null,
    ping_texture: rl.RenderTexture2D = undefined,
    pong_texture: rl.RenderTexture2D = undefined,
    render_texture: rl.RenderTexture2D = undefined,
    shader_texture: rl.RenderTexture2D = undefined,
    final_texture: rl.RenderTexture2D = undefined,

    // Enum State
    page: Pages = .SelectionMenu,
    renderMode: RenderModes = .lines,
    outputMode: RenderOutput = .screen,
    processing_mode: ProcessingMode = .normal,

    // Render Tracking
    render_total_frames: f32 = 0,
    render_frame_counter: f32 = 0,

    // Togglable Edits
    toggle_lines: bool = false,
    render_info: bool = true,
    pause: bool = false,
    close: bool = false,
    view_UI: bool = true,
    display_shader_UI: bool = false,

    log_file: std.fs.File,
    log_writer: std.fs.File.Writer,

    //Page stack
    pages: std.ArrayListUnmanaged(Pages),
    settings: UserSettings,

    // Shader Stack: Allows applying multiple shaders in series by order
    apply_shader_stack: bool = false,
    applied_shaders: std.ArrayListUnmanaged(*ShaderInfo),

    pub fn init(allocator: std.mem.Allocator, sample_level: usize) PlugError!PlugState {
        if (sample_level > max_level) {
            return PlugError.TooLarge;
        }

        // This avoid the issue of stack moving of the value keeping us safe from any un-intended creations
        var core = allocator.create(PlugCore) catch @panic("Memory is not enough to create core");
        const samplesize = std.math.pow(u64, 2, @min(max_level, sample_level));

        var subbands = allocator.alloc(Subbands, subband_count) catch @panic("Memory is not enough to create core");

        const file = std.fs.cwd().createFile("./output.log", .{ .truncate = true }) catch @panic("Cannot create file");

        const emu: PlugState = .{
            .allocator = allocator,
            .core = core,
            .samplesize = samplesize,
            .smooth_samples = core.smooth_samples[0..samplesize],
            .temp_buffer = core.temp_buffer[0..samplesize],
            .samples = core.samples[0..samplesize],
            .complex_samples = core.complex_samples[0..samplesize],
            .complex_amplitudes = core.complex_amplitudes[0..samplesize],
            .amplitudes = core.amplitudes[0..samplesize],
            .log_amplitudes = core.log_amplitudes[0..samplesize],
            .smear_amplitudes = core.smear_amplitudes[0..samplesize],
            .smooth_amplitudes = core.smooth_amplitudes[0..samplesize],
            .subbands = subbands,
            .shaders = undefined,
            .songs = undefined,
            .ping_texture = rl.loadRenderTexture(1920, 1080) catch @panic("Failed to create the render Texture"),
            .pong_texture = rl.loadRenderTexture(1920, 1080) catch @panic("Failed to create the render Texture"),
            .render_texture = rl.loadRenderTexture(1920, 1080) catch @panic("Failed to create the render Texture"),
            .shader_texture = rl.loadRenderTexture(1920, 1080) catch @panic("Failed to create the shader Texture"),
            .pages = std.ArrayListUnmanaged(Pages){},
            .settings = UserSettings.init(),
            .log_file = file,
            .log_writer = file.writer(),
            .applied_shaders = std.ArrayListUnmanaged(*ShaderInfo){},
        };

        const clean_amps = emu.amplitudes[0 .. samplesize / 2];
        const subband_range = clean_amps.len / subband_count;

        for (0..subband_count) |i| {
            const band = clean_amps[i * subband_range ..][0..subband_range];
            const buffer = emu.core.energy_blocks[i * EnergyHistory.default_block_count ..][0..EnergyHistory.default_block_count];
            subbands[i] = Subbands.init(band, buffer);
        }

        return emu;
    }

    pub fn deinit(self: *PlugState) void {
        self.unloadShaders();
        self.unloadSongList();
        rl.unloadTexture(self.render_texture.texture);
        rl.unloadTexture(self.shader_texture.texture);
        if (self.background_texture) |bg| {
            rl.unloadTexture(bg);
        }

        self.applied_shaders.clearAndFree(self.allocator);
        self.pages.deinit(self.allocator);
        self.allocator.destroy(self.core);
        self.allocator.free(self.subbands);
        if (self.settings.background) |bg| {
            self.allocator.free(bg);
        }
    }

    pub fn loadShaders(self: *PlugState) !void {
        var shaders_dir = std.fs.cwd().openDir("./shaders", .{ .iterate = true }) catch blk: {
            self.logInfo("Failed to open shader folder, trying to create it.", .{});
            std.fs.cwd().makeDir("./shaders") catch |err| {
                self.logError("Failed to create shader folder. Quitting", .{});
                return err;
            };

            break :blk std.fs.cwd().openDir("./shaders", .{ .iterate = true }) catch |err| {
                return err;
            };
        };

        defer shaders_dir.close();

        self.log("Shaders Folder Opened", .{}, false);

        var walker = shaders_dir.walk(self.allocator) catch |err| {
            self.logError("Failed to initalize shader walker.", .{});
            return err;
        };
        defer walker.deinit();
        self.log("Shaders Walker Created", .{}, false);

        var shadersList = std.ArrayListUnmanaged(ShaderInfo){};
        errdefer shadersList.deinit(self.allocator);

        while (walker.next()) |Optionalentry| {
            if (Optionalentry) |entry| {
                if (!std.ascii.endsWithIgnoreCase(entry.basename, ".fs")) continue;
                self.logInfo("Handling Entry \"{s}\"", .{entry.basename});

                const path: []const u8 = try shaders_dir.realpath(entry.path, &text_buffer);
                const valid_path = try utils.adaptStringAlloc(self.allocator, path);
                defer self.allocator.free(valid_path);

                const name = try utils.adaptStringAlloc(self.allocator, entry.basename);
                const shader: ShaderInfo = .{
                    .filename = name,
                    .shader = rl.loadShader(null, valid_path) catch continue,
                };

                try shadersList.append(self.allocator, shader);
            } else break;
        } else |err| {
            self.logError("Walker Errored. {}", .{err});
            return err;
        }

        self.shaders = try shadersList.toOwnedSlice(self.allocator);
        self.logInfo("{} Shaders Loaded", .{self.shaders.len});
    }

    pub fn unloadShaders(self: *PlugState) void {
        for (self.shaders) |shaderInfo| {
            rl.unloadShader(shaderInfo.shader);
            self.allocator.free(shaderInfo.filename);
        }

        self.allocator.free(self.shaders);
    }

    const validSongExtensions = [_][]const u8{ ".mp3", ".flac", ".wav", ".ogg", ".qoa", ".xm", ".mod" };
    pub fn loadSongList(self: *PlugState) !void {
        var songs_dir = std.fs.cwd().openDir("./music", .{ .iterate = true }) catch blk: {
            self.logInfo("Failed to open music folder, trying to create it.", .{});
            std.fs.cwd().makeDir("./music") catch |err| {
                self.logError("Failed to create music folder. Quitting", .{});
                return err;
            };

            break :blk std.fs.cwd().openDir("./music", .{ .iterate = true }) catch |err| {
                return err;
            };
        };
        defer songs_dir.close();

        self.log("Music Folder Opened", .{}, false);

        var walker = songs_dir.walk(self.allocator) catch |err| {
            self.logError("Failed to initalize song walker.", .{});
            return err;
        };
        defer walker.deinit();

        self.log("Music Walker Created", .{}, false);

        var songList = std.ArrayListUnmanaged(SongInfo){};
        errdefer songList.deinit(self.allocator);

        while (walker.next()) |Optionalentry| {
            if (Optionalentry) |entry| {
                const valid_extension = for (validSongExtensions) |extension| {
                    if (std.ascii.endsWithIgnoreCase(entry.basename, extension)) break true;
                } else false;

                if (!valid_extension) continue;

                self.log("Handling Entry \"{s}\"", .{entry.basename}, false);
                const path: []const u8 = try songs_dir.realpath(entry.path, &text_buffer);
                const valid_path = try utils.adaptStringAlloc(self.allocator, path);
                const name = try utils.adaptStringAlloc(self.allocator, entry.basename);

                try songList.append(self.allocator, .{ .filename = name, .path = valid_path });
                continue;
            }

            break;
        } else |err| {
            self.logError("Walker Errored. {}", .{err});
            return err;
        }

        self.songs = try songList.toOwnedSlice(self.allocator);
        self.logInfo("{} Songs Loaded", .{self.songs.len});
    }

    pub fn unloadSongList(self: *PlugState) void {
        for (self.songs) |songInfo| {
            self.allocator.free(songInfo.filename);
            self.allocator.free(songInfo.path);
        }

        self.allocator.free(self.songs);
    }

    pub fn clearFFT(plug_state: *PlugState) void {
        for (0..plug_state.samples.len) |i| {
            plug_state.samples[i] = 0.0;
            plug_state.smooth_amplitudes[i] = 0.0;
            plug_state.smear_amplitudes[i] = 0.0;
            plug_state.smooth_samples[i] = 0.0;
            plug_state.log_amplitudes[i] = 0.0;
            plug_state.complex_amplitudes[i] = Complex(f32).init(0, 0);
            plug_state.complex_samples[i] = Complex(f32).init(0, 0);
        }

        for (0..plug_state.subbands.len) |i| {
            for (0..plug_state.subbands[i].history.energy_blocks.items.len) |j| {
                plug_state.subbands[i].history.energy_blocks.items[j] = 0.0;
            }
        }

        plug_state.sample_accumulator = 0;
        plug_state.energy_block_index = 0;
        plug_state.energy_block_counter = 0;
        plug_state.render_frame_counter = 0;
        plug_state.render_total_frames = 0;
    }

    pub fn navigateTo(plug_state: *PlugState, page: Pages) void {
        plug_state.pages.append(plug_state.allocator, page) catch @panic("Failed to append page.");
        plug_state.page = page;
    }

    pub fn goBack(plug_state: *PlugState) void {
        _ = plug_state.pages.pop();

        if (plug_state.pages.items.len != 0) {
            plug_state.page = plug_state.pages.items[plug_state.pages.items.len - 1];
        }
    }

    pub fn loadConfig(plug_state: *PlugState) !UserSettings {
        var file = try std.fs.cwd().openFile(".config", .{ .mode = .read_only });
        defer file.close();

        const content = try file.readToEndAlloc(plug_state.allocator, 999_999_999);
        defer plug_state.allocator.free(content);

        var settings = UserSettings.init();

        var lineReader = std.mem.splitAny(u8, content, "\n");
        while (lineReader.next()) |line| {
            var lineSplitter = std.mem.splitAny(u8, std.mem.trim(u8, line, "\r\n \t"), "=");

            const dirty_name = lineSplitter.next();
            const dirty_value = lineSplitter.next();

            if (dirty_name == null or dirty_value == null) {
                continue;
            }

            const name = std.mem.trim(u8, dirty_name.?, "\r\n \t");
            const value = std.mem.trim(u8, dirty_value.?, "\r\n \t");

            if (std.mem.count(u8, name, "color") > 0) {
                var valueSplitter = std.mem.splitAny(u8, value, " ");
                const red_str = valueSplitter.next();
                const green_str = valueSplitter.next();
                const blue_str = valueSplitter.next();

                if (red_str == null and green_str == null and blue_str == null) {
                    continue;
                }

                const red = try std.fmt.parseInt(u8, std.mem.trim(u8, red_str.?, "\r\n \t"), 10);
                const green = try std.fmt.parseInt(u8, std.mem.trim(u8, green_str.?, "\r\n \t"), 10);
                const blue = try std.fmt.parseInt(u8, std.mem.trim(u8, blue_str.?, "\r\n \t"), 10);

                const color = rl.Color.init(red, green, blue, 255);

                const typeInfo = @typeInfo(UserSettings);
                const structInfo = typeInfo.@"struct";
                {
                    inline for (structInfo.fields) |field| {
                        if (comptime field.type == rl.Color) {
                            if (std.mem.eql(u8, field.name, name)) {
                                @field(settings, field.name) = color;
                            }
                        }
                    }
                }
            }

            if (std.mem.eql(u8, name, "fps")) {
                const fps_value = try std.fmt.parseInt(i32, value, 10);
                settings.fps = fps_value;
            }

            if (std.mem.count(u8, name, "background") > 0) {
                const trimmed_path = std.mem.trim(u8, value, " \t\n");
                const path = try plug_state.allocator.alloc(u8, trimmed_path.len);
                std.mem.copyForwards(u8, path, trimmed_path);
                settings.background = path;
            }
        }

        return settings;
    }

    pub fn saveConfig(plug_state: *PlugState) !void {
        var file = try std.fs.cwd().createFile(".config", .{});
        const writer = file.writer();
        const typeInfo = @typeInfo(UserSettings);
        const structInfo = typeInfo.@"struct";
        inline for (structInfo.fields) |field| {
            if (comptime std.mem.eql(u8, field.name, "fps")) {
                try writer.print("fps={}\n", .{plug_state.settings.fps});
            } else if (field.type == rl.Color) {
                const value = @field(plug_state.settings, field.name);
                try writer.print("{s}={} {} {}\n", .{ field.name, value.r, value.g, value.b });
            } else if (comptime std.mem.eql(u8, field.name, "background")) {
                try writer.print("background={s}\n", .{plug_state.settings.background orelse ""});
            }
        }
    }

    pub fn log(plug_state: *PlugState, comptime format: []const u8, args: anytype, print_location: bool) void {
        if (print_location) {
            const info = std.debug.getSelfDebugInfo() catch @panic("Invalid debug info");
            const addr = @returnAddress();
            const tty: std.io.tty.Config = .no_color;
            std.debug.printSourceAtAddress(info, plug_state.log_writer, addr, tty) catch @panic("Failed to print log location");
        }

        plug_state.log_writer.print(format, args) catch @panic("Failed to print");
        plug_state.log_writer.print("\n", .{}) catch @panic("Failed to print");
    }

    pub inline fn logInfo(plug_state: *PlugState, comptime format: []const u8, args: anytype) void {
        log(plug_state, format, args, false);
    }

    pub inline fn logError(plug_state: *PlugState, comptime format: []const u8, args: anytype) void {
        log(plug_state, format, args, true);
    }
};

inline fn complexAmpToNormalAmp(complex_amplitude: Complex(f32)) f32 {
    return std.math.complex.abs(complex_amplitude);
}

// a frame is L+R | f32 takes both sides
pub fn collectAudioSamples(buffer: ?*anyopaque, frames: c_uint) callconv(.C) void {
    const frame_buffer: ?[*]const f32 = @ptrCast(@alignCast(buffer.?));

    if (frame_buffer == null or global_plug_state.music == null) {
        std.log.info("Incorrect Data", .{});
        return;
    }

    const frame_count: usize = @intCast(frames);
    const buffer_size: usize = frame_count * global_plug_state.music.?.stream.channels;
    const data_buffer = (frame_buffer.?)[0..buffer_size];

    collectAudioSamplesZig(data_buffer, global_plug_state.music.?.stream.channels);
}

pub fn collectAudioSamplesZig(samples: []const f32, channels: usize) void {
    const sized_samples = if (samples.len / 2 > global_plug_state.temp_buffer.len) samples[0 .. global_plug_state.temp_buffer.len * 2] else samples;
    for (sized_samples, 0..) |sample, i| {
        if (i % channels == 0) {
            global_plug_state.temp_buffer[i / channels] = sample;
        }
    }

    var sliced_data: []const f32 = global_plug_state.temp_buffer[0..@divFloor(sized_samples.len, channels)];

    if (sliced_data.len > global_plug_state.samples.len) {
        sliced_data = sliced_data[(sliced_data.len - global_plug_state.samples.len)..];
    }

    std.mem.rotate(f32, global_plug_state.samples, sliced_data.len);
    const target_write = global_plug_state.samples[(global_plug_state.samples.len - sliced_data.len)..];
    std.mem.copyForwards(f32, target_write, sliced_data);

    global_plug_state.sample_accumulator += sliced_data.len;
}

pub fn analyzeAudioSignal(plug_state: *PlugState, delta_time: f32) usize {
    // Smooth the audio
    for (plug_state.samples, 0..) |sample, i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(plug_state.samples.len));
        const hann: f32 = 0.5 - 0.5 * std.math.cos(2 * std.math.pi * t);
        plug_state.smooth_samples[i] = sample * hann;
    }

    for (plug_state.smooth_samples, 0..) |sample, i| {
        plug_state.complex_samples[i] = Complex(f32).init(sample, 0);
    }

    root.FT.NoAllocFFT(plug_state.complex_samples, plug_state.complex_amplitudes);

    plug_state.max_amplitude = 0;
    for (plug_state.complex_amplitudes, 0..plug_state.complex_amplitudes.len) |complex_amplitude, i| {
        plug_state.amplitudes[i] = complexAmpToNormalAmp(complex_amplitude);
        plug_state.max_amplitude = @max(plug_state.amplitudes[i], plug_state.max_amplitude);
    }

    // detect beat through fft
    const gap = plug_state.sample_accumulator - (plug_state.energy_block_counter * sample_block_size);

    if (gap >= sample_block_size) {
        for (0..subband_count) |i| {
            plug_state.subbands[i].extractBlockAndAppend();
        }
        plug_state.energy_block_counter += 1;
    }

    // "Squash" into the Logarithmic Scale
    const frequency_step: f32 = 1.06;
    const lowest_frequency: f32 = 1.0;
    var size: usize = 0;
    var frequency = lowest_frequency;
    plug_state.max_log_amplitude = 0;
    while (frequency < @as(f32, @floatFromInt(plug_state.samples.len)) / 2) : (frequency = std.math.ceil(frequency * frequency_step)) {
        const f1: f32 = std.math.ceil(frequency * frequency_step);
        var a: f32 = 0.0;

        var q: usize = @intFromFloat(frequency);
        while (q < @divFloor(plug_state.samples.len, 2) and q < @as(usize, @intFromFloat(f1))) : (q += 1) {
            const b: f32 = plug_state.amplitudes[q];
            if (b > a) a = b;
        }

        if (plug_state.max_log_amplitude < a) plug_state.max_log_amplitude = a;

        plug_state.log_amplitudes[size] = a;
        size += 1;
    }

    // Smooth out and smear the values
    plug_state.max_smooth_amplitude = 0;
    plug_state.max_smear_amplitude = 0;

    for (0..size) |i| {
        const smoothness: f32 = 8;
        plug_state.smooth_amplitudes[i] += (plug_state.log_amplitudes[i] - plug_state.smooth_amplitudes[i]) * smoothness * delta_time;
        if (plug_state.max_smooth_amplitude < plug_state.smooth_amplitudes[i]) plug_state.max_smooth_amplitude = plug_state.smooth_amplitudes[i];

        const smearness: f32 = 3;
        plug_state.smear_amplitudes[i] += (plug_state.smooth_amplitudes[i] - plug_state.smear_amplitudes[i]) * smearness * delta_time;
        if (plug_state.max_smear_amplitude < plug_state.smear_amplitudes[i]) plug_state.max_smear_amplitude = plug_state.smear_amplitudes[i];
    }

    return size;
}

pub fn plugClose(plug_state: *PlugState) void {
    if (plug_state.music) |music| {
        rl.stopMusicStream(music);
        rl.detachAudioStreamProcessor(music.stream, collectAudioSamples);
    }

    plug_state.deinit();
}

pub fn plugInit(plug_state: *PlugState) void {
    global_plug_state = plug_state;
    plug_state.settings = plug_state.loadConfig() catch blk: {
        plug_state.saveConfig() catch {
            plug_state.logError("Failed to setup Config.", .{});
        };
        break :blk PlugState.UserSettings.init();
    };

    rl.setTraceLogLevel(.warning);
    rl.setTargetFPS(plug_state.settings.fps); // Set our game to run at 60 frames-per-second
    // rl.setTraceLogLevel(.warning);
    plug_state.navigateTo(.SelectionMenu);

    setupGuiStyle(plug_state);
    rl.setExitKey(.null);

    plug_state.loadSongList() catch |err| {
        plug_state.log("Failed to load Song List.", .{}, true);
        plug_state.logInfo("Error: {}", .{err});
        @panic("Error: Failed to load Song list.");
    };

    plug_state.loadShaders() catch |err| {
        plug_state.log("Failed to load Shader List.", .{}, true);
        plug_state.logInfo("Error: {}", .{err});
        @panic("Error: Failed to load Shader list.");
    };

    if (plug_state.settings.background) |bg| bgscope: {
        const background = rl.loadImage(utils.adaptString(bg)) catch |err| {
            plug_state.log("Failed to load background.", .{}, true);
            plug_state.logInfo("Error: {}", .{err});
            break :bgscope;
        };

        plug_state.background_texture = rl.loadTextureFromImage(background) catch |err| {
            plug_state.log("Failed to load background.", .{}, true);
            plug_state.logInfo("Error: {}", .{err});
            break :bgscope;
        };

        plug_state.logInfo("Loaded background successfully.", .{});
    }
}

fn setupGuiStyle(plug_state: *PlugState) void {
    rg.setStyle(.default, .{ .control = .base_color_normal }, plug_state.settings.back_color.toInt());
    rg.setStyle(.default, .{ .control = .border_color_normal }, plug_state.settings.front_color.toInt());
    rg.setStyle(.default, .{ .control = .text_color_normal }, plug_state.settings.front_color.toInt());

    rg.setStyle(.default, .{ .control = .base_color_pressed }, plug_state.settings.back_color.toInt());
    rg.setStyle(.default, .{ .control = .border_color_pressed }, plug_state.settings.pressed_color.toInt());
    rg.setStyle(.default, .{ .control = .text_color_pressed }, plug_state.settings.pressed_color.toInt());

    rg.setStyle(.default, .{ .control = .base_color_focused }, plug_state.settings.back_color.toInt());
    rg.setStyle(.default, .{ .control = .border_color_focused }, plug_state.settings.focused_color.toInt());
    rg.setStyle(.default, .{ .control = .text_color_focused }, plug_state.settings.focused_color.toInt());

    rg.setStyle(.listview, .{ .control = .border_color_focused }, plug_state.settings.front_color.toInt());
    rg.setStyle(.listview, .{ .control = .border_color_pressed }, plug_state.settings.front_color.toInt());
}

fn limitFrequencyRange(plug_state: *PlugState, min: f32, max: f32) []const f32 {
    const amplitudes = plug_state.*.amplitudes;
    const amplitude_cutoff = (amplitudes.len / 2);
    const valid_amps = amplitudes[0..amplitude_cutoff];
    const sample_rate: f32 = @floatFromInt(plug_state.music.?.stream.sampleRate);
    const sample_size: f32 = @floatFromInt(plug_state.*.samples.len);
    const frequency_step: f32 = sample_rate / sample_size;

    const min_index: usize = @intFromFloat(std.math.floor(min / frequency_step));
    var max_index: usize = @intFromFloat(std.math.floor(max / frequency_step));

    if (max_index >= valid_amps.len) {
        max_index = valid_amps.len;
    } else {
        max_index += 1;
    }

    return valid_amps[min_index..max_index];
}

pub fn getAmplitudesToRender(plug_state: *PlugState, delta_time: f32) struct { amps: []const f32, max: f32 } {
    const size = analyzeAudioSignal(plug_state, delta_time);

    const amplitudes = switch (plug_state.processing_mode) {
        .normal => limitFrequencyRange(plug_state, 50, 4000),
        .log => plug_state.log_amplitudes[0..size],
        .smooth => plug_state.smooth_amplitudes[0..size],
        .smear => plug_state.smear_amplitudes[0..size],
    };

    const max_amplitude = switch (plug_state.processing_mode) {
        .normal => plug_state.max_amplitude,
        .log => plug_state.max_log_amplitude,
        .smooth => plug_state.max_smooth_amplitude,
        .smear => plug_state.max_smear_amplitude,
    };

    return .{ .amps = amplitudes, .max = max_amplitude };
}

pub fn plugUpdate(plug_state: *PlugState) void {
    switch (plug_state.page) {
        .SelectionMenu => {
            menu.RenderSelectionMenuPage(plug_state);
        },
        .Visualizer => {
            if (plug_state.music) |music| {
                rl.updateMusicStream(music);
                visualizer.RenderVisualizerPage(plug_state);
            }
        },
        .Settings => {
            settings_page.RenderSettingsPage(plug_state);
        },
    }
}

pub fn printTextureToScreen(plug_state: *PlugState, texture: *rl.RenderTexture, infoRender: ?(fn (plug_state: *PlugState) void)) void {
    rl.beginDrawing();
    defer rl.endDrawing();

    if (plug_state.background_texture) |bg| {
        rl.drawTextureRec(bg, rl.Rectangle.init(0, 0, 1920, 1080), rl.Vector2.init(0, 0), rl.Color.white);
    } else {
        rl.clearBackground(rl.Color.blank);
    }

    rl.drawTextureRec(texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);

    if (infoRender) |extraRender| {
        extraRender(plug_state);
    }
}

pub fn applyShadersToTexture(plug_state: *PlugState, input_texture: *rl.RenderTexture2D, output_texture: *rl.RenderTexture2D) void {
    if (!plug_state.apply_shader_stack or plug_state.applied_shaders.items.len == 0) {
        // No shaders, copy input directly to output
        rl.beginTextureMode(output_texture.*);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.blank);

        rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
        return;
    }

    {
        rl.beginTextureMode(plug_state.ping_texture);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.blank);

        rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    }

    var ping = &plug_state.ping_texture;
    var pong = &plug_state.pong_texture;

    for (plug_state.applied_shaders.items) |shader| {
        applyShaderToTexture(shader, ping, pong);

        const temp = ping;
        ping = pong;
        pong = temp;
    }

    {
        rl.beginTextureMode(output_texture.*);
        defer rl.endTextureMode();

        rl.clearBackground(rl.Color.blank);

        rl.drawTextureRec(ping.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
    }
}

fn applyShaderToTexture(shader: *PlugState.ShaderInfo, input_texture: *const rl.RenderTexture2D, output_texture: *const rl.RenderTexture2D) void {
    rl.beginTextureMode(output_texture.*);
    defer rl.endTextureMode();

    rl.clearBackground(rl.Color.blank);

    rl.beginShaderMode(shader.shader);
    defer rl.endShaderMode();

    rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);
}

pub fn printToImage(input_texture: rl.RenderTexture, output_texture: rl.RenderTexture) rl.Image {
    rl.beginTextureMode(output_texture);
    defer rl.endTextureMode();

    rl.drawTextureRec(input_texture.texture, rl.Rectangle.init(0, 0, 1920, -1080), rl.Vector2.init(0, 0), rl.Color.white);

    return rl.loadImageFromTexture(output_texture.texture);
}
