const std = @import("std");
const rl = @import("raylib");
const CONF = @import("config.zig").CONF;

pub const DB16 = struct {
    pub const BLACK = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const DEEP_PURPLE = rl.Color{ .r = 68, .g = 32, .b = 52, .a = 255 };
    pub const NAVY_BLUE = rl.Color{ .r = 48, .g = 52, .b = 109, .a = 255 };
    pub const DARK_GRAY = rl.Color{ .r = 78, .g = 74, .b = 78, .a = 255 };
    pub const BROWN = rl.Color{ .r = 133, .g = 76, .b = 48, .a = 255 };
    pub const DARK_GREEN = rl.Color{ .r = 52, .g = 101, .b = 36, .a = 255 };
    pub const RED = rl.Color{ .r = 208, .g = 70, .b = 72, .a = 255 };
    pub const LIGHT_GRAY = rl.Color{ .r = 117, .g = 113, .b = 97, .a = 255 };
    pub const BLUE = rl.Color{ .r = 89, .g = 125, .b = 206, .a = 255 };
    pub const ORANGE = rl.Color{ .r = 210, .g = 125, .b = 44, .a = 255 };
    pub const STEEL_BLUE = rl.Color{ .r = 133, .g = 149, .b = 161, .a = 255 };
    pub const GREEN = rl.Color{ .r = 109, .g = 170, .b = 44, .a = 255 };
    pub const PINK_BEIGE = rl.Color{ .r = 210, .g = 170, .b = 153, .a = 255 };
    pub const CYAN = rl.Color{ .r = 109, .g = 194, .b = 202, .a = 255 };
    pub const YELLOW = rl.Color{ .r = 218, .g = 212, .b = 94, .a = 255 };
    pub const WHITE = rl.Color{ .r = 222, .g = 238, .b = 214, .a = 255 };
};

pub const Palette = struct {
    swatch: u8 = 1, // second, after transparent
    index: u8 = 0,
    current: [4]u8 = [4]u8{ 0, 3, 7, 15 },
    db: [CONF.MAX_PALETTES][4]u8 = undefined,
    count: u8 = 0,
    updated: bool = false,
    pub fn init() Palette {
        return Palette{};
    }
    pub fn getColorFromIndex(self: Palette, index: u8) rl.Color {
        _ = self;
        return switch (index) {
            0 => DB16.BLACK,
            1 => DB16.DEEP_PURPLE,
            2 => DB16.NAVY_BLUE,
            3 => DB16.DARK_GRAY,
            4 => DB16.BROWN,
            5 => DB16.DARK_GREEN,
            6 => DB16.RED,
            7 => DB16.LIGHT_GRAY,
            8 => DB16.BLUE,
            9 => DB16.ORANGE,
            10 => DB16.STEEL_BLUE,
            11 => DB16.GREEN,
            12 => DB16.PINK_BEIGE,
            13 => DB16.CYAN,
            14 => DB16.YELLOW,
            15 => DB16.WHITE,
            else => DB16.BLACK,
        };
    }
    pub fn loadPalettesFromFile(self: *Palette) void {
        const file = std.fs.cwd().openFile(CONF.PALETTES_FILE, .{}) catch {
            self.db[0] = .{ 0, 3, 7, 15 };
            self.current = self.db[0];
            self.count = 1;
            return;
        };
        defer file.close();

        const data = file.readToEndAlloc(std.heap.page_allocator, 1024 * 1024) catch {
            self.db[0] = .{ 0, 3, 7, 15 };
            self.current = self.db[0];
            self.count = 1;
            return;
        };
        defer std.heap.page_allocator.free(data);

        self.count = @min(data.len / 4, CONF.MAX_PALETTES);
        for (0..self.count) |i| {
            self.db[i][0] = data[i * 4];
            self.db[i][1] = data[i * 4 + 1];
            self.db[i][2] = data[i * 4 + 2];
            self.db[i][3] = data[i * 4 + 3];
        }

        if (self.count == 0) {
            self.db[0] = .{ 0, 3, 7, 15 };
            self.current = self.db[0];
            self.count = 1;
        } else {
            self.current = self.db[0];
        }
    }
    pub fn savePalettesToFile(self: *Palette) void {
        var buf: [CONF.MAX_PALETTES * 4]u8 = undefined;
        for (0..self.count) |i| {
            buf[i * 4] = self.db[i][0];
            buf[i * 4 + 1] = self.db[i][1];
            buf[i * 4 + 2] = self.db[i][2];
            buf[i * 4 + 3] = self.db[i][3];
        }

        const file = std.fs.cwd().createFile(CONF.PALETTES_FILE, .{}) catch return;
        defer file.close();
        _ = file.write(buf[0 .. self.count * 4]) catch return;
    }
    pub fn updatePalette(self: *Palette) void {
        self.db[self.index] = self.current;
        self.savePalettesToFile();
        self.updated = false;
    }
    pub fn newPalette(self: *Palette) void {
        if (self.count < CONF.MAX_PALETTES) {
            self.db[self.count] = self.current;
            self.index = self.count;
            self.count += 1;
            self.savePalettesToFile();
            self.updated = false;
        }
    }
    pub fn deletePalette(self: *Palette) void {
        if (self.count <= 1) {
            return;
        }

        var i = self.index;
        while (i < self.count - 1) : (i += 1) {
            self.db[i] = self.db[i + 1];
        }
        self.count -= 1;
        self.index = if (self.index > 0) self.index - 1 else 0;
        self.current = self.db[self.index];
        self.updated = false;
        self.savePalettesToFile();
    }
    pub fn swapCurrentSwatch(self: *Palette, new: u8) void {
        self.current[self.swatch] = new;
        self.updated = true;
    }
    pub fn cyclePalette(self: *Palette) void {
        if (self.count > 0) {
            self.index = @mod(self.index + 1, self.count);
            self.current = self.db[self.index];
            self.updated = false;
        }
    }
    pub fn prevPalette(self: *Palette) void {
        if (self.count > 0 and self.index > 0) {
            self.index = self.index - 1;
            self.current = self.db[self.index];
            self.updated = false;
        }
    }
    pub fn nextPalette(self: *Palette) void {
        if (self.count > 0 and self.index < self.count - 1) {
            self.index = self.index + 1;
            self.current = self.db[self.index];
            self.updated = false;
        }
    }
};
