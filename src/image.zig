const std = @import("std");
const dvui = @import("dvui");
const detect = @import("detect.zig");

/// Properties of image.
pub const ImageProp = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn deinit(self: *ImageProp) void {
        dvui.c.stbi_image_free(self.pixels.ptr);
        self.* = undefined;
    }

    pub fn index(self: ImageProp, x: usize, y: usize) usize {
        return (y * self.width + x) * 4;
    }

    /// Get the rgba value with the given pixel.
    pub fn rgbaAt(self: ImageProp, x: usize, y: usize) [4]u8 {
        const i = self.index(x, y);
        return .{
            self.pixels[i + 0],
            self.pixels[i + 1],
            self.pixels[i + 2],
            self.pixels[i + 3],
        };
    }

    /// Get the gray value with the given pixel.
    pub fn grayAt(self: ImageProp, x: usize, y: usize) u8 {
        const i = self.index(x, y);

        const r: u16 = self.pixels[i + 0];
        const g: u16 = self.pixels[i + 1];
        const b: u16 = self.pixels[i + 2];

        return @intCast((r * 77 + g * 150 + b * 29) >> 8);
    }
};
