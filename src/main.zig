const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const App = dvui.App;
const image = @import("image.zig");
const detect = @import("detect.zig");

const max_image_file_size = 64 * 1024 * 1024;
const repo_url = "https://code.kercy666.com/Kercy/notch-detection";

var show_softinfo: bool = false;
var show_license: bool = false;

pub const dvui_app: App = .{
    .config = .{
        .options = .{
            .title = "Notch Detection",
            .size = .{ .w = 900, .h = 600 },
            .min_size = .{ .w = 750, .h = 500 },
        },
    },
    .initFn = appInit,
    .deinitFn = appDeinit,
    .frameFn = appFrame,
};

pub const main = App.main;

pub const panic = App.panic;

pub const std_options: std.Options = .{
    .log_level = .warn,
    .logFn = App.logFn,
};

/// Record the current state of the app.
pub const AppState = struct {
    pub const AppStatus = enum {
        Idle,
        Loaded,
        Detected,
        Exit,
        Error,
    };

    allocator: std.mem.Allocator,
    img_path: ?[:0]const u8 = null,
    img_bytes: ?[]const u8 = null,
    img_prop: ?image.RgbaImgProp = null,
    status: AppStatus = .Idle,

    fn init(allocator: std.mem.Allocator) AppState {
        return .{
            .allocator = allocator,
        };
    }

    fn deinit(self: *AppState) void {
        if (self.img_prop) |*img| {
            img.deinit();
        }

        if (self.img_bytes) |bytes| {
            self.allocator.free(bytes);
        }

        if (self.img_path) |path| {
            self.allocator.free(path);
        }
    }

    /// Replace the old image with the new.
    /// Deinit and free the old to avoid err.
    fn replaceImage(
        self: *AppState,
        img_path: [:0]const u8,
        img_bytes: []const u8,
        img_prop: image.RgbaImgProp,
    ) void {
        if (self.img_prop) |*old_img| {
            old_img.deinit();
        }

        if (self.img_bytes) |old_bytes| {
            self.allocator.free(old_bytes);
        }

        if (self.img_path) |old_path| {
            self.allocator.free(old_path);
        }

        self.img_path = img_path;
        self.img_bytes = img_bytes;
        self.img_prop = img_prop;
        self.status = .Loaded;
    }
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var app_state: AppState = undefined;

/// Init entry of the app.
fn appInit(win: *dvui.Window) !void {
    _ = win;
    app_state = AppState.init(debug_allocator.allocator());
    endPrint();
}

/// Deinit of the app.
fn appDeinit() void {
    app_state.deinit();

    const status = debug_allocator.deinit();
    if (status == .leak) {
        std.log.err("Memory leak detected!", .{});
        endPrint();
    }
}

/// Root frame of the app.
fn appFrame() !App.Result {
    var root = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .both });
    defer root.deinit();

    // It may return ".close" with "Exit" pressed,
    // we need to catch the result,
    // then appFrame would close in loop.
    if (drawTopBar(&app_state)) |result| {
        return result;
    }
    drawMainArea(&app_state);
    drawStatusBar(&app_state);
    drawInfoWindow("Soft Info", @embedFile("softinfo"), &show_softinfo, 1, .{ .w = 300, .h = 200 });
    drawInfoWindow("License", @embedFile("license"), &show_license, 2, .{ .w = 560, .h = 360 });

    return .ok;
}

/// Draw the top bar.
fn drawTopBar(app: *AppState) ?App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .style = .window,
        .background = true,
        .expand = .horizontal,
    });
    defer hbox.deinit();

    {
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
                    endPrint();
                    app.status = .Error;
                };
            }

            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{
                .expand = .horizontal,
            }) != null) {
                std.debug.print("Exited.\n", .{});
                return .close;
            }
        }

        if (dvui.menuItemLabel(@src(), "Help", .{ .submenu = true }, .{})) |r| {
            var popup = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer popup.deinit();

            if (dvui.menuItemLabel(@src(), "Soft Info", .{}, .{
                .expand = .horizontal,
            }) != null) {
                show_softinfo = true;
                menu.close();
            }

            if (dvui.menuItemLabel(@src(), "Go Repo", .{}, .{
                .expand = .horizontal,
            }) != null) {
                openUrl(repo_url) catch |err| {
                    std.log.err("Open repo failed: {}", .{err});
                    endPrint();
                    app.status = .Error;
                };
                menu.close();
            }

            if (dvui.menuItemLabel(@src(), "License", .{}, .{
                .expand = .horizontal,
            }) != null) {
                show_license = true;
                menu.close();
            }
        }
    }

    {
        const v_spring = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer v_spring.deinit();
    }

    _ = dvui.label(@src(), "{d:.1} FPS", .{dvui.FPS()}, .{});

    return null;
}

/// Draw the main area.
fn drawMainArea(app: *AppState) void {
    var main_area = dvui.scrollArea(@src(), .{ .vertical = .auto }, .{
        .expand = .both,
        .max_size_content = .height(0),
        .background = true,
        .corner_radius = dvui.Rect.all(0),
        .color_fill = dvui.Color.fromHex("#202020"),
    });
    defer main_area.deinit();

    if (app.img_bytes != null) {
        drawImagePreview(app);
    } else {
        dvui.label(@src(), "No Image", .{}, .{});
    }
}

/// Draw the status bar.
fn drawStatusBar(app: *AppState) void {
    var status_bar = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .style = .window,
        .background = true,
        .expand = .horizontal,
        .min_size_content = .{ .w = 0, .h = 20 },
    });
    defer status_bar.deinit();

    dvui.label(@src(), "Mode: {s}  ", .{@tagName(app.status)}, .{});

    if (app.img_prop) |img| {
        dvui.label(@src(), "Size: {d} x {d}  ", .{
            img.width,
            img.height,
        }, .{});
    } else {
        dvui.label(@src(), "Size: -  ", .{}, .{});
    }

    if (app.img_path) |path| {
        dvui.label(@src(), "Path: {s}", .{path}, .{});
    } else {
        dvui.label(@src(), "Path: -", .{}, .{});
    }
}

/// Draw the preview of the opened image.
fn drawImagePreview(app: *AppState) void {
    const source: dvui.ImageSource = .{
        .imageFile = .{
            .bytes = app.img_bytes.?,
            .name = app.img_path.?,
            .interpolation = .linear,
            .invalidation = .ptr,
        },
    };

    const image_size = dvui.imageSize(source) catch {
        dvui.label(@src(), "Unable to decode image", .{}, .{});
        return;
    };

    const max_w: f32 = 700;
    const max_h: f32 = 450;

    const scale = @min(max_w / image_size.w, max_h / image_size.h);

    const min_width = image_size.w * scale;
    const min_height = image_size.h * scale;

    {
        const h_spring = dvui.box(@src(), .{ .dir = .vertical }, .{ .min_size_content = .{ .h = 10 } });
        defer h_spring.deinit();
    }

    // Slider area.
    {
        const thresholdSlider = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .min_size_content = .{
                .w = min_width,
                .h = 0,
            },
            .max_size_content = .width(min_width),
        });
        defer thresholdSlider.deinit();

        _ = dvui.label(@src(), "Threshold:", .{}, .{ .gravity_y = 0.5 });

        _ = dvui.slider(@src(), .{
            .fraction = &detect.threshold_fraq,
            .dir = .horizontal,
        }, .{
            .expand = .horizontal,
            .gravity_y = 0.5,
        });

        _ = dvui.label(@src(), "{d}/255", .{detect.threshold()}, .{
            .gravity_y = 0.5,
            .min_size_content = .{
                .w = 60,
                .h = 0,
            },
        });
    }

    // Button Area.
    {
        const buttonArea = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .min_size_content = .{
                .w = min_width,
                .h = 0,
            },
            .max_size_content = .width(min_width),
        });
        defer buttonArea.deinit();

        // Detect Notch.
        if (dvui.button(@src(), "Detect Notch", .{}, .{ .min_size_content = .{ .w = 40 } })) {
            detect.detectImage(app) catch |err| {
                std.log.err("Detect image failed: {}", .{err});
                endPrint();
                app.status = .Error;
            };
        }

        const v_spring = dvui.box(@src(), .{ .dir = .horizontal }, .{ .expand = .horizontal });
        defer v_spring.deinit();
    }

    {
        const h_spring = dvui.box(@src(), .{ .dir = .vertical }, .{ .min_size_content = .{ .h = 10 } });
        defer h_spring.deinit();
    }

    _ = dvui.image(@src(), .{ .source = source }, .{
        .min_size_content = .{
            .w = min_width,
            .h = min_height,
        },
    });
}

/// Draw a text info floating window.
fn drawInfoWindow(
    title: []const u8,
    text: []const u8,
    open_flag: *bool,
    id_extra: usize,
    size: dvui.Size,
) void {
    if (!open_flag.*) return;

    var win = dvui.floatingWindow(@src(), .{
        .open_flag = open_flag,
        .resize = .none,
    }, .{
        .id_extra = id_extra,
        .min_size_content = size,
        .max_size_content = .{ .w = size.w, .h = size.h },
    });
    defer win.deinit();

    drawInfoWindowHeader(title, open_flag, id_extra);
    win.dragAreaSet(.{ .x = -1, .y = -1, .w = 0, .h = 0 });

    var content = dvui.box(@src(), .{}, .{
        .id_extra = id_extra,
        .expand = .both,
        .padding = dvui.Rect.all(10),
    });
    defer content.deinit();

    var scroll = dvui.scrollArea(@src(), .{ .vertical = .auto }, .{
        .id_extra = id_extra,
        .expand = .both,
        .background = false,
        .corner_radius = dvui.Rect.all(0),
    });
    defer scroll.deinit();

    var tl = dvui.textLayout(@src(), .{}, .{
        .id_extra = id_extra,
        .expand = .horizontal,
        .background = false,
    });
    defer tl.deinit();
    tl.addText(text, .{});
}

/// Draw a info window title bar.
fn drawInfoWindowHeader(title: []const u8, open_flag: *bool, id_extra: usize) void {
    var header = dvui.box(@src(), .{ .dir = .horizontal }, .{
        .id_extra = id_extra,
        .expand = .horizontal,
        .background = true,
        .color_fill = dvui.Color.fromHex("#2b2b2b"),
        .border = .{ .h = 1 },
        .padding = dvui.Rect.all(4),
    });
    defer header.deinit();

    dvui.labelNoFmt(@src(), title, .{}, .{
        .id_extra = id_extra,
        .expand = .horizontal,
        .gravity_y = 0.5,
        .font = .theme(.heading),
    });

    if (dvui.buttonIcon(@src(), "close_info_window", dvui.entypo.cross, .{}, .{}, .{
        .id_extra = id_extra,
        .min_size_content = .all(20),
        .max_size_content = .width(20),
        .padding = dvui.Rect.all(2),
        .gravity_y = 0.5,
    })) {
        open_flag.* = false;
    }
}

/// Open a URL with the platform default browser.
fn openUrl(url: []const u8) !void {
    const argv = switch (builtin.os.tag) {
        .windows => &[_][]const u8{ "rundll32", "url.dll,FileProtocolHandler", url },
        .macos => &[_][]const u8{ "open", url },
        else => &[_][]const u8{ "xdg-open", url },
    };

    var child = try std.process.spawn(dvui.io, .{ .argv = argv });
    const term = try child.wait(dvui.io);
    switch (term) {
        .exited => |code| if (code != 0) return error.OpenUrlFailed,
        else => return error.OpenUrlFailed,
    }
}

/// Open system dialog to choose the image.
fn openImageDialog(app: *AppState) !void {
    const path_opt = try dvui.dialogNativeFileOpen(app.allocator, .{
        .title = "Open Image",
        .filters = &.{ "*.png", "*.jpg", "*.jpeg", "*.bmp" },
        .filter_description = "Image files",
    });

    const path = path_opt orelse {
        std.debug.print("Open image cancelled.\n", .{});
        endPrint();
        return;
    };
    errdefer app.allocator.free(path);

    // Get the img_bytes of the given image.
    const img_bytes = try std.Io.Dir.cwd().readFileAlloc(
        dvui.io,
        path,
        app.allocator,
        .limited(max_image_file_size),
    );
    errdefer app.allocator.free(img_bytes);

    // Get the img_prop of the given image.
    const img_prop = try image.imgBytesToRgba(img_bytes);
    errdefer {
        var tmp = img_prop;
        tmp.deinit();
    }

    // Use the image when "No image",
    // or replace the old when exists.
    app.replaceImage(path, img_bytes, img_prop);

    std.debug.print("Loaded image.\n", .{});
    endPrint();
}

/// Use it when print-block ends,
/// because I have a compulsion for alignment.
pub inline fn endPrint() void {
    std.debug.print("───────────────\n", .{});
}
