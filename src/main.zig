const std = @import("std");
const dvui = @import("dvui");
const App = dvui.App;
const zigimg = @import("zigimg");

pub const dvui_app: App = .{
    .config = .{
        .options = .{
            .title = "DVUI Test",
            .size = .{ .w = 900, .h = 600 },
            .min_size = .{ .w = 600, .h = 400 },
        },
    },
    .initFn = appInit,
    .deinitFn = appDeinit,
    .frameFn = appFrame,
};

pub const main = App.main;

pub const panic = App.panic;

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = App.logFn,
};

const AppState = struct {
    const AppStatus = enum {
        Idle,
        OpenImg,
        LoadedImg,
        Calculate,
        Exit,
        Error,
    };

    allocator: std.mem.Allocator,
    img_path: ?[:0]const u8 = null,
    image: ?zigimg.Image = null,
    status: AppStatus = .Idle,

    fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(self: *AppState) void {
        if (self.image) |*img| {
            img.deinit(self.allocator);
        }

        if (self.img_path) |path| {
            self.allocator.free(path);
        }
    }

    fn replaceImage(self: *AppState, path: [:0]const u8, image: zigimg.Image) void {
        if (self.image) |*old_img| {
            old_img.deinit(self.allocator);
        }

        if (self.img_path) |old_path| {
            self.allocator.free(old_path);
        }

        self.img_path = path;
        self.image = image;
        self.status = .LoadedImg;
    }

    fn getStatusName(self: AppState) []const u8 {
        return switch (self.status) {
            .Idle => "Idle",
            .OpenImg => "Open image",
            .LoadedImg => "Loaded image",
            .Calculate => "Calculate",
            .Exit => "Exit",
            .Error => "Error",
        };
    }
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var app_state: AppState = undefined;

pub fn appInit(win: *dvui.Window) !void {
    _ = win;
    app_state = AppState.init(debug_allocator.allocator());
}

pub fn appDeinit() void {
    app_state.deinit();

    const status = debug_allocator.deinit();
    if (status == .leak) {
        std.log.err("Memory leak detected!", .{});
    }
}

pub fn appFrame() !App.Result {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer root.deinit();

    if (drawTopBar(&app_state)) |result| {
        return result;
    }
    drawMainArea(&app_state);

    return .ok;
}

fn drawTopBar(app: *AppState) ?App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .style = .window,
        .background = true,
        .expand = .horizontal,
    });
    defer hbox.deinit();

    var menu = dvui.menu(@src(), .horizontal, .{});
    defer menu.deinit();

    if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
        var popup = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer popup.deinit();

        if (dvui.menuItemLabel(@src(), "Open Image", .{}, .{
            .expand = .horizontal,
        }) != null) {
            menu.close();

            openImageDialog(app) catch |err| {
                std.log.err("Open image failed: {}", .{err});
                app.status = .Error;
            };
        }

        if (dvui.menuItemLabel(@src(), "Exit", .{}, .{
            .expand = .horizontal,
        }) != null) {
            return .close;
        }
    }

    if (dvui.menuItemLabel(@src(), "Help", .{ .submenu = true }, .{})) |r| {
        var popup = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer popup.deinit();

        if (dvui.menuItemLabel(@src(), "Team Info", .{}, .{
            .expand = .horizontal,
        }) != null) {
            std.log.info("Team info.", .{});
            menu.close();
        }
    }

    return null;
}

fn drawMainArea(app: *AppState) void {
    var main_area = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer main_area.deinit();

    dvui.label(@src(), "Mode: {s}", .{app.getStatusName()}, .{});

    if (app.img_path) |path| {
        dvui.label(@src(), "Image Path: {s}", .{path}, .{});
    } else {
        dvui.label(@src(), "No Image", .{}, .{});
    }

    if (app.image) |*img| {
        dvui.label(@src(), "Size: {d} x {d}", .{
            img.width,
            img.height,
        }, .{});
        drawImagePreview(img);
    }
}

fn openImageDialog(app: *AppState) !void {
    app.status = .OpenImg;

    const path_opt = try dvui.dialogNativeFileOpen(app.allocator, .{
        .title = "Open Image",
        .filters = &.{ "*.png", "*.jpg", "*.jpeg", "*.bmp" },
        .filter_description = "Image files",
    });

    const path = path_opt orelse {
        app.status = .Idle;
        std.log.info("Open image cancelled.", .{});
        return;
    };
    errdefer app.allocator.free(path);

    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    var image = try zigimg.Image.fromFilePath(
        app.allocator,
        dvui.io,
        path,
        read_buffer[0..],
    );
    errdefer image.deinit(app.allocator);

    try image.convert(app.allocator, .rgba32);

    app.replaceImage(path, image);

    std.log.info("Loaded image: {s}", .{path});
}

fn drawImagePreview(img: *zigimg.Image) void {
    const pixels = img.pixels.rgba32;

    const source: dvui.ImageSource = .{
        .pixels = .{
            .rgba = std.mem.sliceAsBytes(pixels),
            .width = @intCast(img.width),
            .height = @intCast(img.height),
            .interpolation = .linear,
            .invalidation = .ptr,
        },
    };

    const max_w: f32 = 700;
    const max_h: f32 = 450;

    const iw: f32 = @floatFromInt(img.width);
    const ih: f32 = @floatFromInt(img.height);

    const scale = @min(max_w / iw, max_h / ih);

    _ = dvui.image(@src(), .{ .source = source }, .{
        .min_size_content = .{
            .w = iw * scale,
            .h = ih * scale,
        },
    });
}
