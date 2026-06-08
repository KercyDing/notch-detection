const std = @import("std");
const image = @import("image.zig");
const GrayImgProp = image.GrayImgProp;
const AppState = @import("root").AppState;

pub var threshold_fraq: f32 = 50.0 / 255.0;

/// Get the gray threshold with threshold_fraq.
pub fn threshold() u8 {
    return @intFromFloat(@round(255.0 * threshold_fraq));
}

const BinaryStats = struct {
    white_count: usize = 0,
    black_count: usize = 0,
    min_x: usize = std.math.maxInt(usize),
    min_y: usize = std.math.maxInt(usize),
    max_x: usize = 0,
    max_y: usize = 0,
};

/// Detect the notch of the image.
pub fn detectImage(app: *AppState) !void {
    var stats: BinaryStats = .{};

    if (app.img_bytes) |bytes| {
        var prop = try image.imageBytesToGray(app.allocator, bytes);
        defer prop.deinit(app.allocator);

        grayToBinary(&prop);

        detectBinary(prop, &stats) catch |err| {
            std.log.err("No white pixel detected: {}", .{err});
            std.log.err("Please try lowering the threshold,", .{});
            std.log.err("or change with the correct image.", .{});
            std.debug.print("──────────\n", .{});
        };
    } else {
        std.log.err("Cannot find image.", .{});
        std.debug.print("──────────\n", .{});
        return;
    }

    app.status = .Detected;
}

/// Convey the GrayImgProp into binary.
fn grayToBinary(prop: *GrayImgProp) void {
    for (prop.pixels) |*pixel| {
        const t = threshold();
        if (pixel.* > t) {
            pixel.* = 255;
        } else pixel.* = 0;
    }
}

/// Detect min/max pixel of the binary image.
fn detectBinary(prop: GrayImgProp, stats: *BinaryStats) !void {
    const width = prop.width;

    for (prop.pixels, 0..) |pixel, idx| {
        if (pixel == 255) { // white
            const x = idx % width;
            const y = idx / width;

            if (stats.min_x > x) stats.min_x = x;
            if (stats.min_y > y) stats.min_y = y;
            if (stats.max_x < x) stats.max_x = x;
            if (stats.max_y < y) stats.max_y = y;

            stats.white_count += 1;
        } else if (pixel == 0) { // black
            stats.black_count += 1;
        } else {
            std.log.err("The grayToBinary conversion failed.", .{});
            std.debug.print("──────────\n", .{});
        }
    }

    if (stats.white_count == 0) return error.NoWhiteDetected;

    showInfo(stats.*);
}

inline fn showInfo(stats: BinaryStats) void {
    const box_w = stats.max_x - stats.min_x + 1;
    const box_h = stats.max_y - stats.min_y + 1;

    std.debug.print("min_x: {d}\n", .{stats.min_x});
    std.debug.print("min_y: {d}\n", .{stats.min_y});
    std.debug.print("max_x: {d}\n", .{stats.max_x});
    std.debug.print("max_y: {d}\n", .{stats.max_y});
    std.debug.print("box_w: {d}\n", .{box_w});
    std.debug.print("box_h: {d}\n", .{box_h});
    std.debug.print("──────────\n", .{});
}
