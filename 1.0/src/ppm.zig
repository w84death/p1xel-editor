const std = @import("std");

pub const RGB = packed struct { r: u8, g: u8, b: u8 };
pub const Color = packed union { value: u24, data: RGB };
pub const Ppm = struct {
    width: usize,
    height: usize,
    data: []Color,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Ppm {
        const data = try allocator.alloc(Color, width * height);
        return Ppm{
            .width = width,
            .height = height,
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Ppm) void {
        self.allocator.free(self.data);
    }

    pub fn save(self: *Ppm, filename: []const u8) !void {
        var file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var buffer: [8192]u8 = undefined;
        var fwrite = file.writer(&buffer);
        const writer = &fwrite.interface;
        try writer.print("P3\n{} {}\n255\n", .{ self.width, self.height });

        for (self.data) |pixel| {
            try writer.print("{} {} {}\n", .{ pixel.data.r, pixel.data.g, pixel.data.b });
        }

        try writer.flush();
    }
};
