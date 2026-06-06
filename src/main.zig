const std = @import("std");
const dvui = @import("dvui");
const App = dvui.App;

const max_image_file_size = 64 * 1024 * 1024;

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
    image_bytes: ?[]const u8 = null,
    status: AppStatus = .Idle,

    fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(self: *AppState) void {
        if (self.image_bytes) |bytes| {
            self.allocator.free(bytes);
        }

        if (self.img_path) |path| {
            self.allocator.free(path);
        }
    }

    fn replaceImage(self: *AppState, path: [:0]const u8, image_bytes: []const u8) void {
        if (self.image_bytes) |old_bytes| {
            self.allocator.free(old_bytes);
        }

        if (self.img_path) |old_path| {
            self.allocator.free(old_path);
        }

        self.img_path = path;
        self.image_bytes = image_bytes;
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

    if (app.image_bytes) |bytes| {
        drawImagePreview(app.img_path.?, bytes);
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

    const image_bytes = try std.Io.Dir.cwd().readFileAlloc(
        dvui.io,
        path,
        app.allocator,
        .limited(max_image_file_size),
    );
    errdefer app.allocator.free(image_bytes);

    app.replaceImage(path, image_bytes);

    std.log.info("Loaded image: {s}", .{path});
}

fn drawImagePreview(path: []const u8, image_bytes: []const u8) void {
    const source: dvui.ImageSource = .{
        .imageFile = .{
            .bytes = image_bytes,
            .name = path,
            .interpolation = .linear,
            .invalidation = .ptr,
        },
    };

    const image_size = dvui.imageSize(source) catch {
        dvui.label(@src(), "Unable to decode image", .{}, .{});
        return;
    };

    dvui.label(@src(), "Size: {d:.0} x {d:.0}", .{
        image_size.w,
        image_size.h,
    }, .{});

    const max_w: f32 = 700;
    const max_h: f32 = 450;

    const scale = @min(max_w / image_size.w, max_h / image_size.h);

    _ = dvui.image(@src(), .{ .source = source }, .{
        .min_size_content = .{
            .w = image_size.w * scale,
            .h = image_size.h * scale,
        },
    });
}
