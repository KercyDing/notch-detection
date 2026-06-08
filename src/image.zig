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

/// Change image bytes into rgba-ImageProp.
pub fn imageBytesToRgba(img_bytes: []const u8) !ImageProp {
    var w_i: c_int = 0;
    var h_i: c_int = 0;
    var channels_in_file: c_int = 0;

    const data = dvui.c.stbi_load_from_memory(
        img_bytes.ptr,
        @intCast(img_bytes.len),
        &w_i,
        &h_i,
        &channels_in_file,
        4,
    ) orelse return error.ImageDecodeFailed;

    if (w_i <= 0 or h_i <= 0) {
        dvui.c.stbi_image_free(data);
        return error.InvalidImageSize;
    }

    const w: usize = @intCast(w_i);
    const h: usize = @intCast(h_i);

    const pixel_count = try std.math.mul(usize, w, h);
    const len = try std.math.mul(usize, pixel_count, 4);

    return .{
        .width = w,
        .height = h,
        .pixels = data[0..len],
    };
}
