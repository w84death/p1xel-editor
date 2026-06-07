const std = @import("std");
const builtin = @import("builtin");

pub fn pixelTransferPath(buf: *[512]u8) ![]const u8 {
    return switch (builtin.os.tag) {
        .windows => std.fmt.bufPrint(buf, "C:\\Windows\\Temp\\p1xel_image_clip.p1xpix", .{}),
        else => std.fmt.bufPrint(buf, "/tmp/p1xel_image_clip.p1xpix", .{}),
    };
}

pub fn readU16(bytes: []const u8) u16 {
    return @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
}

pub fn writeU16(bytes: []u8, value: u16) void {
    bytes[0] = @intCast(value & 0xFF);
    bytes[1] = @intCast(value >> 8);
}
