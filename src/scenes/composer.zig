const std = @import("std");
const CONF = @import("../config.zig").CONF;
const DB16 = @import("../palette.zig").DB16;
const Fui = @import("../fui.zig").Fui;
const PIVOTS = @import("../fui.zig").PIVOTS;
const State = @import("../state.zig").State;
const StateMachine = @import("../state.zig").StateMachine;
const Vec2 = @import("../math.zig").Vec2;
const Mouse = @import("../math.zig").Mouse;
const AudioMod = @import("../audio.zig");
const Audio = AudioMod.Audio;
const Note = AudioMod.Note;
const Tune = AudioMod.Tune;

const sample_rate = 44100.0;
const samples_per_frame = @as(usize, @intFromFloat(sample_rate / 30.0));

const NoteDef = struct {
    name: [:0]const u8,
    id: usize,
};

const AVAILABLE_NOTES = [_]NoteDef{
    .{ .name = "C-4", .id = AudioMod.NOTE_C4 },
    .{ .name = "C#4", .id = AudioMod.NOTE_CS4 },
    .{ .name = "D-4", .id = AudioMod.NOTE_D4 },
    .{ .name = "D#4", .id = AudioMod.NOTE_DS4 },
    .{ .name = "E-4", .id = AudioMod.NOTE_E4 },
    .{ .name = "F-4", .id = AudioMod.NOTE_F4 },
    .{ .name = "F#4", .id = AudioMod.NOTE_FS4 },
    .{ .name = "G-4", .id = AudioMod.NOTE_G4 },
    .{ .name = "G#4", .id = AudioMod.NOTE_GS4 },
    .{ .name = "A-4", .id = AudioMod.NOTE_A4 },
    .{ .name = "A#4", .id = AudioMod.NOTE_AS4 },
    .{ .name = "B-4", .id = AudioMod.NOTE_B4 },
    .{ .name = "C-5", .id = AudioMod.NOTE_C5 },
};

const MAX_NOTES = 512;

fn getNoteName(id: usize) [:0]const u8 {
    for (AVAILABLE_NOTES) |n| {
        if (n.id == id) return n.name;
    }
    return "???";
}

const ComposerMode = enum {
    Insert,
    Preview,
};

pub const ComposerScene = struct {
    fui: Fui,
    sm: *StateMachine,
    audio: Audio,
    melody: [MAX_NOTES]Note,
    melody_len: usize,
    mode: ComposerMode,
    preview_buf: [1]Note,

    pub fn init(fui: Fui, sm: *StateMachine) ComposerScene {
        return ComposerScene{
            .fui = fui,
            .sm = sm,
            .audio = Audio.init(),
            .melody = undefined,
            .melody_len = 0,
            .mode = .Insert,
            .preview_buf = undefined,
        };
    }

    pub fn draw(self: *ComposerScene, mouse: Mouse) void {
        const px = self.fui.pivots[PIVOTS.TOP_LEFT].x;
        const py = self.fui.pivots[PIVOTS.TOP_LEFT].y;

        // Navigation
        if (self.fui.button(px, py, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse)) {
            self.audio.stop_tune();
            self.sm.goTo(State.main_menu);
        }

        // Playback Controls
        if (self.fui.button(px + 130, py, 100, 32, "Play", CONF.COLOR_MENU_NORMAL, mouse)) {
            if (self.melody_len > 0) {
                self.audio.play_tune(self.melody[0..self.melody_len]);
            }
        }
        if (self.fui.button(px + 240, py, 100, 32, "Stop", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.audio.stop_tune();
        }
        if (self.fui.button(px + 350, py, 100, 32, "Clear", CONF.COLOR_MENU_DANGER, mouse)) {
            self.audio.stop_tune();
            self.melody_len = 0;
        }

        const mode_str = switch (self.mode) {
            .Insert => "Insert",
            .Preview => "Preview",
        };
        if (self.fui.button(px + 460, py, 100, 32, mode_str, CONF.COLOR_MENU_HIGHLIGHT, mouse)) {
            self.mode = if (self.mode == .Insert) .Preview else .Insert;
        }

        // Note Palette (Left Column)
        const start_y = py + 48;
        var btn_y: i32 = start_y;

        self.fui.draw_text("Notes:", px, btn_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_MENU_TEXT);
        btn_y += 32;

        for (AVAILABLE_NOTES) |note_def| {
            if (self.fui.button(px, btn_y, 80, 24, note_def.name, CONF.COLOR_MENU_NORMAL, mouse)) {
                self.audio.stop_tune();

                // Play preview
                self.preview_buf[0] = .{ .id = note_def.id, .dur = 0.25 };
                self.audio.play_tune(&self.preview_buf);

                if (self.mode == .Insert) {
                    if (self.melody_len < MAX_NOTES) {
                        self.melody[self.melody_len] = .{ .id = note_def.id, .dur = 0.25 };
                        self.melody_len += 1;
                    }
                }
            }
            btn_y += 28;
        }

        // Add a generic Rest button
        if (self.fui.button(px, btn_y, 80, 24, "REST", CONF.COLOR_MENU_SECONDARY, mouse)) {
            self.audio.stop_tune();

            // Play silent preview (rest)
            self.preview_buf[0] = .{ .id = AudioMod.NOTE_REST, .dur = 0.25 };
            self.audio.play_tune(&self.preview_buf);

            if (self.mode == .Insert) {
                if (self.melody_len < MAX_NOTES) {
                    self.melody[self.melody_len] = .{ .id = AudioMod.NOTE_REST, .dur = 0.25 };
                    self.melody_len += 1;
                }
            }
        }

        // Melody Tracker (Center/Right Column)
        const track_x = px + 150;
        var track_y = start_y;

        self.fui.draw_text("Tracker:", track_x, track_y, CONF.FONT_DEFAULT_SIZE, CONF.COLOR_MENU_TEXT);
        track_y += 32;

        // Display notes
        var i: usize = 0;
        while (i < self.melody_len) : (i += 1) {
            const note = self.melody[i];
            var color: u32 = CONF.COLOR_MENU_SECONDARY;

            // Highlight current note
            if (self.audio.playing and self.audio.current_note == i) {
                color = CONF.COLOR_MENU_HIGHLIGHT;
            }

            // Note row
            var buf: [32]u8 = undefined;
            const name = if (note.id == AudioMod.NOTE_REST) "..." else getNoteName(note.id);
            const text = std.fmt.bufPrintZ(&buf, "{d:0>2} | {s}", .{ i, name }) catch "ERR";

            if (self.fui.button(track_x, track_y, 160, 20, text, color, mouse)) {
                // Remove note if clicked
                self.audio.stop_tune();
                var k = i;
                while (k < self.melody_len - 1) : (k += 1) {
                    self.melody[k] = self.melody[k + 1];
                }
                self.melody_len -= 1;
                // Adjust loop index
                if (i > 0) i -= 1;
            }

            track_y += 24;

            // Simple culling
            if (track_y > CONF.SCREEN_H - 50) break;
        }
    }

    pub fn update_audio(self: *ComposerScene, dt: f32) void {
        self.audio.update_audio(dt);
    }

    pub fn deinit(self: *ComposerScene) void {
        self.audio.deinit();
    }
};
