const std = @import("std");
const dvui = @import("dvui");
const image = @import("image.zig");
const AppState = @import("root").AppState;

pub fn detectImage(app: *AppState) void {
    app.status = .Detected;
}

/// Change image bytes into rgba-ImageProp.
pub fn imageBytesToRgba(img_bytes: []const u8) !image.ImageProp {
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
