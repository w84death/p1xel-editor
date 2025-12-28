const std = @import("std");
const CONF = @import("config.zig").CONF;
const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};
pub const DB16 = struct {
    pub const BLACK: u32 = 0xFF140C1C;
    pub const DEEP_PURPLE: u32 = 0xFF442434;
    pub const NAVY_BLUE: u32 = 0xFF30346D;
    pub const DARK_GRAY: u32 = 0xFF4E4A4F;
    pub const BROWN: u32 = 0xFF854C30;
    pub const DARK_GREEN: u32 = 0xFF346524;
    pub const RED: u32 = 0xFFD04648;
    pub const LIGHT_GRAY: u32 = 0xFF757161;
    pub const BLUE: u32 = 0xFF597DCE;
    pub const ORANGE: u32 = 0xFFD27D2C;
    pub const STEEL_BLUE: u32 = 0xFF8595A1;
    pub const GREEN: u32 = 0xFF6DAA2C;
    pub const PINK_BEIGE: u32 = 0xFFD2AA99;
    pub const CYAN: u32 = 0xFF6DC2CA;
    pub const YELLOW: u32 = 0xFFDAD45E;
    pub const WHITE: u32 = 0xFFDEEED6;
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
    pub fn get_rgba_from_index(self: Palette, index: u8) u32 {
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
