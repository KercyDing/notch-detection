const std = @import("std");
const endPrint = @import("root").endPrint;
const image = @import("image.zig");
const GrayImgProp = image.GrayImgProp;
const AppState = @import("root").AppState;

pub var threshold_fraq: f32 = 20.0 / 255.0;

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
            endPrint();
        };
    } else {
        std.log.err("Cannot find image.", .{});
        endPrint();
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
            endPrint();
        }
    }

    if (stats.white_count == 0) return error.NoWhiteDetected;

    // debugBasicInfo(stats.*);

    std.debug.print("Top:\n", .{});
    try detectVerticalEdge(prop, stats.min_y, stats.min_x, stats.max_x);
    std.debug.print("Bottom:\n", .{});
    try detectVerticalEdge(prop, stats.max_y, stats.min_x, stats.max_x);
    std.debug.print("Left:\n", .{});
    try detectHorizonalEdge(prop, stats.min_x, stats.min_y, stats.max_y);
    std.debug.print("Right:\n", .{});
    try detectHorizonalEdge(prop, stats.max_x, stats.min_y, stats.max_y);
}

inline fn detectVerticalEdge(prop: GrayImgProp, y: usize, left: usize, right: usize) !void {
    std.debug.assert(left < right);

    var count: usize = 0;
    var curr: usize = left + 1;

    while (curr <= right) {
        const prev_bin_val = try prop.at(curr - 1, y);
        const curr_bin_val = try prop.at(curr, y);

        if (prev_bin_val != 255 or curr_bin_val != 0) {
            curr += 1;
            continue;
        }

        const start = curr;
        while (curr <= right and try prop.at(curr, y) == 0) {
            curr += 1;
        }

        count += 1;
        std.debug.print("  Len: {d}\n", .{transform(curr - start, prop.width)});
    }
    std.debug.print("Total count: {d}\n", .{count});
    endPrint();
}

inline fn detectHorizonalEdge(prop: GrayImgProp, x: usize, top: usize, btm: usize) !void {
    std.debug.assert(top < btm);

    var count: usize = 0;
    var curr: usize = top + 1;

    while (curr <= btm) {
        const prev_bin_val = try prop.at(x, curr - 1);
        const curr_bin_val = try prop.at(x, curr);

        if (prev_bin_val != 255 or curr_bin_val != 0) {
            curr += 1;
            continue;
        }

        const start = curr;
        while (curr <= btm and try prop.at(x, curr) == 0) {
            curr += 1;
        }

        count += 1;
        std.debug.print("  Len: {d}\n", .{transform(curr - start, prop.height)});
    }
    std.debug.print("Total count: {d}\n", .{count});
    endPrint();
}

inline fn debugBasicInfo(stats: BinaryStats) void {
    const box_w = stats.max_x - stats.min_x + 1;
    const box_h = stats.max_y - stats.min_y + 1;

    std.debug.print("Basic Info:\n", .{});
    std.debug.print("min_x: {d}\n", .{stats.min_x});
    std.debug.print("min_y: {d}\n", .{stats.min_y});
    std.debug.print("max_x: {d}\n", .{stats.max_x});
    std.debug.print("max_y: {d}\n", .{stats.max_y});
    std.debug.print("box_w: {d}\n", .{box_w});
    std.debug.print("box_h: {d}\n", .{box_h});
    endPrint();
}

inline fn transform(num: usize, side_len: usize) usize {
    return (num * 1000 + side_len / 2) / side_len;
}
