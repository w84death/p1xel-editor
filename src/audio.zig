const std = @import("std");

pub const Note = struct { id: usize, dur: f32 };
pub const Tune = []const Note;

pub const NoteDef = struct { val: u16, freq: f32 };

pub const NOTE_REST = 0;
// Octave 2
pub const NOTE_C2 = 1;
pub const NOTE_CS2 = 2;
pub const NOTE_D2 = 3;
pub const NOTE_DS2 = 4;
pub const NOTE_E2 = 5;
pub const NOTE_F2 = 6;
pub const NOTE_FS2 = 7;
pub const NOTE_G2 = 8;
pub const NOTE_GS2 = 9;
pub const NOTE_A2 = 10;
pub const NOTE_AS2 = 11;
pub const NOTE_B2 = 12;
// Octave 3
pub const NOTE_C3 = 13;
pub const NOTE_CS3 = 14;
pub const NOTE_D3 = 15;
pub const NOTE_DS3 = 16;
pub const NOTE_E3 = 17;
pub const NOTE_F3 = 18;
pub const NOTE_FS3 = 19;
pub const NOTE_G3 = 20;
pub const NOTE_GS3 = 21;
pub const NOTE_A3 = 22;
pub const NOTE_AS3 = 23;
pub const NOTE_B3 = 24;
// Octave 4
pub const NOTE_C4 = 25;
pub const NOTE_CS4 = 26;
pub const NOTE_D4 = 27;
pub const NOTE_DS4 = 28;
pub const NOTE_E4 = 29;
pub const NOTE_F4 = 30;
pub const NOTE_FS4 = 31;
pub const NOTE_G4 = 32;
pub const NOTE_GS4 = 33;
pub const NOTE_A4 = 34;
pub const NOTE_AS4 = 35;
pub const NOTE_B4 = 36;
// Octave 5
pub const NOTE_C5 = 37;
pub const NOTE_CS5 = 38;
pub const NOTE_D5 = 39;
pub const NOTE_DS5 = 40;
pub const NOTE_E5 = 41;
pub const NOTE_F5 = 42;
pub const NOTE_FS5 = 43;
pub const NOTE_G5 = 44;
pub const NOTE_GS5 = 45;
pub const NOTE_A5 = 46;
pub const NOTE_AS5 = 47;
pub const NOTE_B5 = 48;
// Octave 6
pub const NOTE_C6 = 49;
pub const NOTE_CS6 = 50;
pub const NOTE_D6 = 51;
pub const NOTE_DS6 = 52;
pub const NOTE_E6 = 53;
pub const NOTE_F6 = 54;
pub const NOTE_FS6 = 55;
pub const NOTE_G6 = 56;
pub const NOTE_GS6 = 57;
pub const NOTE_A6 = 58;
pub const NOTE_AS6 = 59;
pub const NOTE_B6 = 60;
// Octave 7
pub const NOTE_C7 = 61;
pub const NOTE_CS7 = 62;
pub const NOTE_D7 = 63;

pub const NOTE_TABLE = [_]NoteDef{
    .{ .val = 0xFFFF, .freq = 0.0 }, // 0: REST
    .{ .val = 0x4698, .freq = 65.41 }, // 1: C2
    .{ .val = 0x3F1D, .freq = 69.30 }, // 2: C#2
    .{ .val = 0x38FF, .freq = 73.42 }, // 3: D2
    .{ .val = 0x33A1, .freq = 77.78 }, // 4: D#2
    .{ .val = 0x2F01, .freq = 82.41 }, // 5: E2
    .{ .val = 0x2A0F, .freq = 87.31 }, // 6: F2
    .{ .val = 0x25C7, .freq = 92.50 }, // 7: F#2
    .{ .val = 0x221B, .freq = 98.00 }, // 8: G2
    .{ .val = 0x1F02, .freq = 103.83 }, // 9: G#2
    .{ .val = 0x1C70, .freq = 110.00 }, // 10: A2
    .{ .val = 0x1A52, .freq = 116.54 }, // 11: A#2
    .{ .val = 0x189F, .freq = 123.47 }, // 12: B2
    .{ .val = 0x234C, .freq = 130.81 }, // 13: C3
    .{ .val = 0x1F8F, .freq = 138.59 }, // 14: C#3
    .{ .val = 0x1C80, .freq = 146.83 }, // 15: D3
    .{ .val = 0x19D1, .freq = 155.56 }, // 16: D#3
    .{ .val = 0x1781, .freq = 164.81 }, // 17: E3
    .{ .val = 0x1508, .freq = 174.61 }, // 18: F3
    .{ .val = 0x12E4, .freq = 185.00 }, // 19: F#3
    .{ .val = 0x110E, .freq = 196.00 }, // 20: G3
    .{ .val = 0x0F81, .freq = 207.65 }, // 21: G#3
    .{ .val = 0x0E38, .freq = 220.00 }, // 22: A3
    .{ .val = 0x0D29, .freq = 233.08 }, // 23: A#3
    .{ .val = 0x0C50, .freq = 246.94 }, // 24: B3
    .{ .val = 0x11A6, .freq = 261.63 }, // 25: C4
    .{ .val = 0x0FC8, .freq = 277.18 }, // 26: C#4
    .{ .val = 0x0E40, .freq = 293.66 }, // 27: D4
    .{ .val = 0x0CE9, .freq = 311.13 }, // 28: D#4
    .{ .val = 0x0BC1, .freq = 329.63 }, // 29: E4
    .{ .val = 0x0A84, .freq = 349.23 }, // 30: F4
    .{ .val = 0x0972, .freq = 369.99 }, // 31: F#4
    .{ .val = 0x0887, .freq = 392.00 }, // 32: G4
    .{ .val = 0x07C1, .freq = 415.30 }, // 33: G#4
    .{ .val = 0x071C, .freq = 440.00 }, // 34: A4
    .{ .val = 0x0695, .freq = 466.16 }, // 35: A#4
    .{ .val = 0x0628, .freq = 493.88 }, // 36: B4
    .{ .val = 0x08D3, .freq = 523.25 }, // 37: C5
    .{ .val = 0x07E4, .freq = 554.37 }, // 38: C#5
    .{ .val = 0x0720, .freq = 587.33 }, // 39: D5
    .{ .val = 0x0675, .freq = 622.25 }, // 40: D#5
    .{ .val = 0x05E1, .freq = 659.25 }, // 41: E5
    .{ .val = 0x0542, .freq = 698.46 }, // 42: F5
    .{ .val = 0x04B9, .freq = 739.99 }, // 43: F#5
    .{ .val = 0x0444, .freq = 783.99 }, // 44: G5
    .{ .val = 0x03E1, .freq = 830.61 }, // 45: G#5
    .{ .val = 0x038E, .freq = 880.00 }, // 46: A5
    .{ .val = 0x034B, .freq = 932.33 }, // 47: A#5
    .{ .val = 0x0314, .freq = 987.77 }, // 48: B5
    .{ .val = 0x046A, .freq = 1046.50 }, // 49: C6
    .{ .val = 0x03F2, .freq = 1108.73 }, // 50: C#6
    .{ .val = 0x0390, .freq = 1174.66 }, // 51: D6
    .{ .val = 0x033B, .freq = 1244.51 }, // 52: D#6
    .{ .val = 0x02F1, .freq = 1318.51 }, // 53: E6
    .{ .val = 0x02A1, .freq = 1396.91 }, // 54: F6
    .{ .val = 0x025D, .freq = 1479.98 }, // 55: F#6
    .{ .val = 0x0222, .freq = 1567.98 }, // 56: G6
    .{ .val = 0x01F1, .freq = 1661.22 }, // 57: G#6
    .{ .val = 0x01C7, .freq = 1760.00 }, // 58: A6
    .{ .val = 0x01A6, .freq = 1864.66 }, // 59: A#6
    .{ .val = 0x018A, .freq = 1975.53 }, // 60: B6
    .{ .val = 0x0235, .freq = 2093.00 }, // 61: C7
    .{ .val = 0x01F9, .freq = 2217.46 }, // 62: C#7
    .{ .val = 0x01C8, .freq = 2349.32 }, // 63: D7
};

pub const FenAudio = opaque {};

extern fn fenster_audio_open(*FenAudio) c_int;
extern fn fenster_audio_available(*FenAudio) c_int;
extern fn fenster_audio_write(*FenAudio, [*]f32, usize) void;
extern fn fenster_audio_close(*FenAudio) void;

const FA_SIZE = 8192 * @sizeOf(f32) + 64; // Approximate size for buffer + pointers

pub const Audio = struct {
    fa_ptr: *FenAudio,
    fa_buf: []u8,
    playing: bool,
    tune: ?Tune = null,
    current_note: usize = 0,
    current_time: f32 = 0.0,
    sample_rate: f32 = 44100.0,
    u: usize = 0, // for phase or counter
    pub fn init() Audio {
        const fa_buf = std.heap.page_allocator.alloc(u8, FA_SIZE) catch unreachable;
        const fa = @as(*FenAudio, @ptrCast(fa_buf.ptr));
        _ = fenster_audio_open(fa);
        return Audio{
            .fa_ptr = fa,
            .fa_buf = fa_buf,
            .playing = false,
            .tune = null,
            .current_note = 0,
            .current_time = 0.0,
            .sample_rate = 44100.0,
            .u = 0,
        };
    }
    pub fn deinit(self: *Audio) void {
        fenster_audio_close(self.fa_ptr);
        std.heap.page_allocator.free(self.fa_buf);
    }
    pub fn update_audio(self: *Audio, dt: f32) void {
        _ = dt;
        if (!self.playing or self.tune == null) return;

        const samples_per_frame: usize = @intFromFloat(self.sample_rate / 30.0);
        var buf: [1470]f32 = undefined;

        const avail = fenster_audio_available(self.fa_ptr);
        if (avail <= 0) return;

        const to_write = @min(samples_per_frame, @as(usize, @intCast(avail)));
        var i: usize = 0;

        while (i < to_write) : (i += 1) {
            // Advance note if time is up
            var note = self.tune.?[self.current_note];
            if (self.current_time >= note.dur) {
                self.current_note += 1;
                self.current_time = 0.0;
                if (self.current_note >= self.tune.?.len) {
                    self.playing = false;
                    break;
                }
                note = self.tune.?[self.current_note];
            }

            const freq = NOTE_TABLE[note.id].freq;
            if (freq == 0.0) {
                buf[i] = 0.0;
            } else {
                const phase_step: u32 = @intFromFloat(freq * 65536.0 / self.sample_rate);
                self.u += phase_step;
                const phase_bit = (self.u >> 16) & 1;
                const wave = if (phase_bit == 0) @as(f32, 1.0) else @as(f32, -1.0);
                buf[i] = wave * 0.5;
            }

            self.current_time += 1.0 / self.sample_rate;
        }

        // Write to audio
        if (i > 0) {
            fenster_audio_write(self.fa_ptr, @as([*]f32, @ptrCast(&buf[0])), i);
        }
    }
    pub fn play_tune(self: *Audio, tune: Tune) void {
        self.tune = tune;
        self.current_note = 0;
        self.current_time = 0.0;
        self.playing = true;
    }
    pub fn stop_tune(self: *Audio) void {
        self.playing = false;
        self.tune = null;
    }
};
