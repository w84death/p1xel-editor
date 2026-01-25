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

const scale_tune: Tune = &[_]Note{
    .{ .id = AudioMod.NOTE_C4, .dur = 0.25 }, // C4
    .{ .id = AudioMod.NOTE_D4, .dur = 0.25 }, // D4
    .{ .id = AudioMod.NOTE_E4, .dur = 0.25 }, // E4
    .{ .id = AudioMod.NOTE_F4, .dur = 0.25 }, // F4
    .{ .id = AudioMod.NOTE_G4, .dur = 0.25 }, // G4
    .{ .id = AudioMod.NOTE_A4, .dur = 0.25 }, // A4
    .{ .id = AudioMod.NOTE_B4, .dur = 0.25 }, // B4
    .{ .id = AudioMod.NOTE_C5, .dur = 0.25 }, // C5
};

const melody_array = [_]Note{
    .{ .id = AudioMod.NOTE_C4, .dur = 0.25 }, // C
    .{ .id = AudioMod.NOTE_C4, .dur = 0.25 }, // C
    .{ .id = AudioMod.NOTE_G4, .dur = 0.25 }, // G
    .{ .id = AudioMod.NOTE_G4, .dur = 0.25 }, // G
    .{ .id = AudioMod.NOTE_A4, .dur = 0.25 }, // A
    .{ .id = AudioMod.NOTE_A4, .dur = 0.25 }, // A
    .{ .id = AudioMod.NOTE_G4, .dur = 0.5 }, // G
    .{ .id = AudioMod.NOTE_F4, .dur = 0.25 }, // F
    .{ .id = AudioMod.NOTE_F4, .dur = 0.25 }, // F
    .{ .id = AudioMod.NOTE_E4, .dur = 0.25 }, // E
    .{ .id = AudioMod.NOTE_E4, .dur = 0.25 }, // E
    .{ .id = AudioMod.NOTE_D4, .dur = 0.25 }, // D
    .{ .id = AudioMod.NOTE_D4, .dur = 0.25 }, // D
    .{ .id = AudioMod.NOTE_C4, .dur = 0.5 }, // C
};
const melody_tune: Tune = &melody_array;

pub const ComposerScene = struct {
    fui: Fui,
    sm: *StateMachine,
    audio: Audio,
    pub fn init(fui: Fui, sm: *StateMachine) ComposerScene {
        return ComposerScene{
            .fui = fui,
            .sm = sm,
            .audio = Audio.init(),
        };
    }
    pub fn draw(self: *ComposerScene, mouse: Mouse) void {
        const px = self.fui.pivots[PIVOTS.TOP_LEFT].x;
        const py = self.fui.pivots[PIVOTS.TOP_LEFT].y;
        if (self.fui.button(px, py, 120, 32, "< Menu", CONF.COLOR_MENU_SECONDARY, mouse)) {
            self.sm.goTo(State.main_menu);
        }

        if (self.fui.button(px, py + 64, 200, 32, "Play Scale", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.audio.play_tune(scale_tune);
        }

        if (self.fui.button(px, py + 64 + 40, 200, 32, "Play Melody", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.audio.play_tune(melody_tune);
        }

        if (self.fui.button(px, py + 64 + 80, 160, 32, "Stop", CONF.COLOR_MENU_NORMAL, mouse)) {
            self.audio.stop_tune();
        }
    }
    pub fn update_audio(self: *ComposerScene, dt: f32) void {
        self.audio.update_audio(dt);
    }
    pub fn deinit(self: *ComposerScene) void {
        self.audio.deinit();
    }
};
