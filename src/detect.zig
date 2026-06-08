const std = @import("std");
const dvui = @import("dvui");
const image = @import("image.zig");

pub fn detectImage(image_prop: image.ImageProp) void {
    _ = image_prop;
}

/// Change image bytes into rgba-ImageProp.
pub fn imageBytesToRgba(image_bytes: []const u8) !image.ImageProp {
    var w_i: c_int = 0;
    var h_i: c_int = 0;
    var channels_in_file: c_int = 0;

    const data = dvui.c.stbi_load_from_memory(
        image_bytes.ptr,
        @intCast(image_bytes.len),
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
