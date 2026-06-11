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

/// Band width of detection.
const band_width: usize = 3;

const BinaryStats = struct {
    white_count: usize,
    black_count: usize,
    min_x: usize,
    min_y: usize,
    max_x: usize,
    max_y: usize,
    box_w: usize,
    box_h: usize,
};

/// Side of image edges.
const EdgeSide = enum {
    Top,
    Bottom,
    Left,
    Right,
};

/// Detect the notch of the image.
pub fn detectImage(app: *AppState) !void {
    var stats = std.mem.zeroes(BinaryStats);

    if (app.img_bytes) |bytes| {
        var prop = try image.imageBytesToGray(app.allocator, bytes);
        defer prop.deinit(app.allocator);

        // 0. Initialize binary stats.
        stats.min_x = prop.width;
        stats.min_y = prop.height;

        // 1. Transform gray prop into binary prop.
        grayToBinary(&prop);

        // 2. Get binary stats with binary prop.
        getBinaryStats(prop, &stats) catch |err| {
            switch (err) {
                error.NoWhiteDetected => {
                    std.log.err(
                        \\No white pixel detected.
                        \\       Please lower the threshold,
                        \\       or replace with the correct image.
                    , .{});
                    endPrint();
                    app.status = .Error;
                    return;
                },
            }
        };

        // If you want to debug the basic info when detect,
        // uncomment the row below.
        //
        // debugBasicInfo(stats);

        // 3. Detect notch of the edges in side.
        detectEdge(prop, stats, .Top);
        detectEdge(prop, stats, .Bottom);
        detectEdge(prop, stats, .Left);
        detectEdge(prop, stats, .Right);
    } else {
        std.log.err("Cannot find image.", .{});
        endPrint();
        return;
    }

    app.status = .Detected;
}

/// Convey the GrayImgProp into binary.
fn grayToBinary(prop: *GrayImgProp) void {
    const t = threshold();
    for (prop.pixels) |*pixel| {
        if (pixel.* > t) {
            pixel.* = 255;
        } else pixel.* = 0;
    }
}

/// Get binary stats.
fn getBinaryStats(prop: GrayImgProp, stats: *BinaryStats) !void {
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

    stats.box_w = stats.max_x - stats.min_x + 1;
    stats.box_h = stats.max_y - stats.min_y + 1;
}

/// Detect notch of edge in range with the given edge side.
inline fn detectEdge(prop: GrayImgProp, stats: BinaryStats, side: EdgeSide) void {
    const fixed = switch (side) {
        .Top => stats.min_y,
        .Bottom => stats.max_y,
        .Left => stats.min_x,
        .Right => stats.max_x,
    };
    const head = switch (side) {
        .Top, .Bottom => stats.min_x,
        .Left, .Right => stats.min_y,
    };
    const tail = switch (side) {
        .Top, .Bottom => stats.max_x,
        .Left, .Right => stats.max_y,
    };

    std.debug.assert(head < tail);

    std.debug.print("{s}:\n", .{@tagName(side)});

    var count: usize = 0;
    var curr: usize = head + 1;

    while (curr <= tail) {
        const prev_has_white = hasWhiteWithBand(prop, side, fixed, curr - 1);
        const curr_has_white = hasWhiteWithBand(prop, side, fixed, curr);

        if (!prev_has_white or curr_has_white) {
            curr += 1;
            continue;
        }

        const start = curr;

        while (curr <= tail) {
            if (hasWhiteWithBand(prop, side, fixed, curr)) break;
            curr += 1;
        }

        count += 1;
        std.debug.print("  Length: {d}\n", .{transform(stats, side, curr - start)});
    }
    std.debug.print("Total count: {d}\n", .{count});
    endPrint();
}

/// Check if has white with the given band width.
inline fn hasWhiteWithBand(prop: GrayImgProp, side: EdgeSide, fixed: usize, pos: usize) bool {
    for (0..band_width) |i| {
        const bin_val = switch (side) {
            .Top => prop.at(pos, fixed + i),
            .Bottom => prop.at(pos, fixed - i),
            .Left => prop.at(fixed + i, pos),
            .Right => prop.at(fixed - i, pos),
        };

        if (bin_val == 255) return true;
    }

    return false;
}

/// Print the basic location info.
inline fn debugBasicInfo(stats: BinaryStats) void {
    std.debug.print(
        \\Basic Info:
        \\  min_x: {d}
        \\  min_y: {d}
        \\  max_x: {d}
        \\  max_y: {d}
        \\  box_w: {d}
        \\  box_h: {d}
        \\
    , .{ stats.min_x, stats.min_y, stats.max_x, stats.max_y, stats.box_w, stats.box_h });
    endPrint();
}

/// Transform the num with the given edge side.(1000 x 1000)
inline fn transform(stats: BinaryStats, side: EdgeSide, num: usize) usize {
    const real: usize = 1000;
    const side_len = switch (side) {
        .Top, .Bottom => stats.box_w,
        .Left, .Right => stats.box_h,
    };

    return (num * real + side_len / 2) / side_len;
}
