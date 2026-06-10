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

const ImgEdgeDir = enum {
    Vertical,
    Horizontal,
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
    try detectEdge(prop, .Vertical, stats.min_y, stats.min_x, stats.max_x);
    std.debug.print("Bottom:\n", .{});
    try detectEdge(prop, .Vertical, stats.max_y, stats.min_x, stats.max_x);
    std.debug.print("Left:\n", .{});
    try detectEdge(prop, .Horizontal, stats.min_x, stats.min_y, stats.max_y);
    std.debug.print("Right:\n", .{});
    try detectEdge(prop, .Horizontal, stats.max_x, stats.min_y, stats.max_y);
}

/// Detect notch of edge in range with the given image direction.
inline fn detectEdge(prop: GrayImgProp, dir: ImgEdgeDir, fixed: usize, head: usize, tail: usize) !void {
    std.debug.assert(head < tail);

    var count: usize = 0;
    var curr: usize = head + 1;

    while (curr <= tail) {
        const prev_val = switch (dir) {
            .Vertical => try prop.at(curr - 1, fixed),
            .Horizontal => try prop.at(fixed, curr - 1),
        };
        const curr_val = switch (dir) {
            .Vertical => try prop.at(curr, fixed),
            .Horizontal => try prop.at(fixed, curr),
        };

        if (prev_val != 255 or curr_val != 0) {
            curr += 1;
            continue;
        }

        const start = curr;

        while (curr <= tail and try prop.at(curr, fixed) == 0) {
            const curr_notch_val = switch (dir) {
                .Vertical => try prop.at(curr, fixed),
                .Horizontal => try prop.at(fixed, curr),
            };
            if (curr_notch_val != 0) break;
            curr += 1;
        }

        count += 1;
        std.debug.print("  Length: {d}\n", .{transform(prop, curr - start, dir)});
    }
    std.debug.print("Total count: {d}\n", .{count});
    endPrint();
}

/// Print the basic location info.
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

/// Transform the num with the given image direction.(1000 x 1000)
inline fn transform(prop: GrayImgProp, num: usize, dir: ImgEdgeDir) usize {
    const real: usize = 1000;
    const side_len = switch (dir) {
        .Vertical => prop.width,
        .Horizontal => prop.height,
    };

    return (num * real + side_len / 2) / side_len;
}
