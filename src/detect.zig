const std = @import("std");
const dvui = @import("dvui");
const constants = @import("constants.zig");
const image = @import("image.zig");
const AppState = @import("root").AppState;

pub fn detectImage(app: *AppState) void {
    if (app.img_prop) |prop| {
        var i: usize = 0;
        const pix_len = prop.pixels.len;
        for (0..(pix_len / 4)) |r_idx| {
            i = (i + 1) % prop.width;
            if (prop.pixels[4 * r_idx] == 0 or prop.pixels[4 * r_idx] == 255) continue;
            std.debug.print("({d} {d} {d} {d}) ", .{
                prop.pixels[4 * r_idx],
                prop.pixels[4 * r_idx + 1],
                prop.pixels[4 * r_idx + 2],
                prop.pixels[4 * r_idx + 3],
            });
            if (i == 0) {
                std.debug.print("\n", .{});
            }
        }
        std.debug.print("\n", .{});
    } else {
        std.log.err("No image to detect!", .{});
        return;
    }

    app.status = .Detected;
}
