const std = @import("std");
const dvui = @import("dvui");

/// Properties of rgba image.
pub const RgbaImgProp = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn deinit(self: *RgbaImgProp) void {
        dvui.c.stbi_image_free(self.pixels.ptr);
        self.* = undefined;
    }

    pub fn index(self: RgbaImgProp, x: usize, y: usize) usize {
        return (y * self.width + x) * 4;
    }

    /// Get the rgba value with the given pixel.
    pub fn rgbaAt(self: RgbaImgProp, x: usize, y: usize) [4]u8 {
        const i = self.index(x, y);
        return .{
            self.pixels[i + 0],
            self.pixels[i + 1],
            self.pixels[i + 2],
            self.pixels[i + 3],
        };
    }

    /// Get the gray value with the given pixel.
    pub fn grayAt(self: RgbaImgProp, x: usize, y: usize) u8 {
        const i = self.index(x, y);

        const r: u16 = self.pixels[i + 0];
        const g: u16 = self.pixels[i + 1];
        const b: u16 = self.pixels[i + 2];

        return @intCast((r * 77 + g * 150 + b * 29) >> 8);
    }
};

/// Properties of gray image.
pub const GrayImgProp = struct {
    width: usize,
    height: usize,
    pixels: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
    ) !GrayImgProp {
        const len = try std.math.mul(usize, width, height);
        const pixels = try allocator.alloc(u8, len);
        return .{
            .width = width,
            .height = height,
            .pixels = pixels,
        };
    }

    pub fn deinit(self: *GrayImgProp, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
        self.* = undefined;
    }

    pub fn index(self: GrayImgProp, x: usize, y: usize) usize {
        return y * self.width + x;
    }

    pub fn at(self: GrayImgProp, x: usize, y: usize) u8 {
        return self.pixels[self.index(x, y)];
    }

    pub fn set(self: *GrayImgProp, x: usize, y: usize, value: u8) void {
        self.pixels[self.index(x, y)] = value;
    }
};

/// Change image bytes into RgbaImgProp.
pub fn imageBytesToRgba(img_bytes: []const u8) !RgbaImgProp {
    var w_i: c_int = 0;
    var h_i: c_int = 0;
    var channels: c_int = 0;

    const data: [*c]u8 = try getImageData(img_bytes, &w_i, &h_i, &channels);

    const w: usize = @intCast(w_i);
    const h: usize = @intCast(h_i);

    const pixel_count = try std.math.mul(usize, w, h);
    const len = try std.math.mul(usize, pixel_count, 4);

    const rgba_pixels: []u8 = data[0..len];

    return .{
        .width = w,
        .height = h,
        .pixels = rgba_pixels,
    };
}

/// Change image bytes into GrayImgProp.
pub fn imageBytesToGray(allocator: std.mem.Allocator, img_bytes: []const u8) !GrayImgProp {
    var rgba = try imageBytesToRgba(img_bytes);
    defer rgba.deinit();

    var gray_img = try GrayImgProp.init(allocator, rgba.width, rgba.height);

    for (0..rgba.height) |y| {
        for (0..rgba.width) |x| {
            gray_img.set(x, y, rgba.grayAt(x, y));
        }
    }

    return gray_img;
}

/// Get image pixels data with stb_image.
inline fn getImageData(img_bytes: []const u8, w_i: [*c]c_int, h_i: [*c]c_int, channels: [*c]c_int) ![*c]u8 {
    const data = dvui.c.stbi_load_from_memory(
        img_bytes.ptr,
        @intCast(img_bytes.len),
        w_i,
        h_i,
        channels,
        4,
    ) orelse return error.ImageDecodeFailed;

    if (w_i.* <= 0 or h_i.* <= 0) {
        dvui.c.stbi_image_free(data);
        return error.InvalidImageSize;
    }

    return data;
}
