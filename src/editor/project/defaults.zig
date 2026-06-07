const CONF = @import("../../engine/config.zig").CONF;

pub const PaletteColor = [3]u8;

pub fn paletteBanks(comptime bank_count: usize) [bank_count][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return [_][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor{clearPalettes()} ** bank_count;
}

pub fn paletteSets(
    comptime image_bank_count: usize,
    comptime palette_bank_count: usize,
) [image_bank_count][palette_bank_count][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    return duplicatePaletteSets(image_bank_count, palette_bank_count, paletteBanks(palette_bank_count));
}

pub fn duplicatePaletteSets(
    comptime image_bank_count: usize,
    comptime palette_bank_count: usize,
    shared: [palette_bank_count][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor,
) [image_bank_count][palette_bank_count][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    var sets: [image_bank_count][palette_bank_count][CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor = undefined;
    for (&sets) |*set| set.* = shared;
    return sets;
}

fn clearPalettes() [CONF.PALETTE_COUNT][CONF.COLORS_PER_PALETTE]PaletteColor {
    const grayscale = [CONF.COLORS_PER_PALETTE]PaletteColor{
        .{ 0, 0, 0 },
        .{ 85, 85, 85 },
        .{ 170, 170, 170 },
        .{ 255, 255, 255 },
    };
    return [_][CONF.COLORS_PER_PALETTE]PaletteColor{grayscale} ** CONF.PALETTE_COUNT;
}
