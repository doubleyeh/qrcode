const std = @import("std");
const runner = @import("runner");
const native_sdk = @import("native_sdk");
const qr_lib = @import("qr.zig");

const SW_HIDE: c_int = 0;
const SW_SHOW: c_int = 5;
const SW_RESTORE: c_int = 9;
const KEYEVENTF_KEYUP: u32 = 0x0002;
const VK_CONTROL: u32 = 0x11;
const VK_SHIFT: u32 = 0x10;
const VK_MENU: u32 = 0x12;
const WM_HOTKEY: u32 = 0x0312;
const MOD_ALT: u32 = 0x0001;
const MOD_SHIFT: u32 = 0x0004;
const MOD_NOREPEAT: u32 = 0x4000;
const HOTKEY_ID: c_int = 100;
const GWLP_WNDPROC: c_int = -4;

extern "user32" fn FindWindowA(lpClassName: ?[*:0]const u8, lpWindowName: ?[*:0]const u8) ?*anyopaque;
extern "user32" fn ShowWindow(hWnd: ?*anyopaque, nCmdShow: c_int) c_int;
extern "user32" fn SetForegroundWindow(hWnd: ?*anyopaque) c_int;
extern "user32" fn keybd_event(bVk: u8, bScan: u8, dwFlags: u32, dwExtraInfo: usize) void;
extern "user32" fn RegisterHotKey(hWnd: ?*anyopaque, id: c_int, fsModifiers: u32, vk: u32) c_int;
extern "user32" fn SetWindowLongPtrW(hWnd: ?*anyopaque, nIndex: c_int, dwNewLong: isize) isize;
extern "user32" fn CallWindowProcW(prevWndFunc: ?*anyopaque, hWnd: ?*anyopaque, uMsg: u32, wParam: u64, lParam: i64) isize;
extern "user32" fn GetSystemMetrics(nIndex: c_int) c_int;
extern "user32" fn SetWindowPos(hWnd: ?*anyopaque, hWndInsertAfter: ?*anyopaque, X: c_int, Y: c_int, cx: c_int, cy: c_int, uFlags: u32) c_int;
extern "kernel32" fn FreeConsole() void;
extern "kernel32" fn GetConsoleWindow() ?*anyopaque;
extern "user32" fn LoadImageA(hInst: ?*anyopaque, name: [*:0]const u8, typ: u32, cx: c_int, cy: c_int, fuLoad: u32) ?*anyopaque;
extern "user32" fn SendMessageW(hWnd: ?*anyopaque, msg: u32, wParam: u64, lParam: isize) isize;

const WM_SETICON: u32 = 0x0080;
const ICON_SMALL: u64 = 0;
const ICON_BIG: u64 = 1;
const LR_LOADFROMFILE: u32 = 0x0010;
const IMAGE_ICON: u32 = 1;

var g_orig_wndproc: usize = 0;
var g_hotkey_fired: bool = false;

fn myWndProc(hWnd: ?*anyopaque, uMsg: u32, wParam: u64, lParam: i64) callconv(.winapi) isize {
    if (uMsg == WM_HOTKEY and wParam == HOTKEY_ID) {
        g_hotkey_fired = true;
        return 0;
    }
    return CallWindowProcW(@ptrFromInt(g_orig_wndproc), hWnd, uMsg, wParam, lParam);
}

pub const panic = std.debug.FullPanic(native_sdk.debug.capturePanic);

const canvas = native_sdk.canvas;
const geometry = native_sdk.geometry;

const canvas_label = "main-canvas";
const window_width: f32 = 520;
const window_height: f32 = 640;

const app_permissions = [_][]const u8{ native_sdk.security.permission_command, native_sdk.security.permission_view };
const shell_views = [_]native_sdk.ShellView{
    .{ .label = canvas_label, .kind = .gpu_surface, .fill = true, .role = "QR code canvas", .accessibility_label = "QR Code Generator", .gpu_backend = .software, .gpu_pixel_format = .bgra8_unorm, .gpu_present_mode = .timer, .gpu_alpha_mode = .@"opaque", .gpu_color_space = .srgb, .gpu_vsync = true },
};
const shell_windows = [_]native_sdk.ShellWindow{.{
    .label = "main",
    .title = "QR Code Generator",
    .width = window_width,
    .height = window_height,
    .restore_state = false,
    .views = &shell_views,
}};
const shell_scene: native_sdk.ShellConfig = .{ .windows = &shell_windows };

pub const Msg = union(enum) {
    draft_edit: canvas.TextInputEvent,
    generate,
    save,
    toggle_per_line,
    saved: native_sdk.EffectFileResult,
    captured_clipboard: native_sdk.EffectClipboardResult,
    capture_qr,
    show_window,
    hide_window,
    quit,
    nav_prev,
    nav_next,
    hotkey_tick: native_sdk.EffectTimer,
    read_clipboard: native_sdk.EffectTimer,
    show_main_window: native_sdk.EffectTimer,
};

const Effects = native_sdk.Effects(Msg);

const base_multi_image_id: canvas.ImageId = 10;

pub const Model = struct {
    draft: canvas.TextBuffer(500) = .{},
    qr_image_id: canvas.ImageId = 1,
    has_qr: bool = false,
    per_line: bool = false,
    status: []const u8 = "",
    status_buf: [64]u8 = undefined,
    qr_page: usize = 0,
    qr_page_count: usize = 0,
    qr_pixels: []u8 = &.{},
    qr_img_size: u32 = 0,
    capturing: bool = false,
    current_qr_image_id: canvas.ImageId = 0,
};

pub fn update(model: *Model, msg: Msg, fx: *Effects) void {
    switch (msg) {
        .draft_edit => |edit| {
            model.draft.apply(edit);
            model.has_qr = false;
            freeQrPages(model, fx);
            model.status = "";
        },
        .generate => {
            generate_qr(model, fx) catch {
                model.status = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe7\x94\x9f\xe6\x88\x90\xe5\xa4\xb1\xe8\xb4\xa5";
            };
        },
        .save => {
            save_qr(model, fx) catch {
                model.status = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe4\xbf\x9d\xe5\xad\x98\xe5\xa4\xb1\xe8\xb4\xa5";
            };
        },
        .toggle_per_line => {
            model.per_line = !model.per_line;
            if (!model.per_line) {
                freeQrPages(model, fx);
                model.status = "\xe5\xb7\xb2\xe5\x85\xb3\xe9\x97\xad\xe9\x80\x90\xe8\xa1\x8c\xe6\xa8\xa1\xe5\xbc\x8f";
            } else {
                generate_qr(model, fx) catch {
                    model.status = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe7\x94\x9f\xe6\x88\x90\xe5\xa4\xb1\xe8\xb4\xa5";
                };
            }
        },
        .saved => |result| {
            if (result.outcome == .ok) {
                model.status = "\xe4\xbf\x9d\xe5\xad\x98\xe6\x88\x90\xe5\x8a\x9f";
            } else {
                model.status = "\xe4\xbf\x9d\xe5\xad\x98\xe5\xa4\xb1\xe8\xb4\xa5";
            }
        },
        .captured_clipboard => |result| {
            model.capturing = false;
            if (result.outcome == .ok and result.text.len > 0) {
                model.draft.apply(.clear);
                model.draft.apply(.{ .insert_text = result.text });
                generate_qr(model, fx) catch {
                    model.status = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe7\x94\x9f\xe6\x88\x90\xe5\xa4\xb1\xe8\xb4\xa5";
                };
                const hwnd = FindWindowA(null, "QR Code Generator");
                if (hwnd != null) {
                    _ = ShowWindow(hwnd, SW_RESTORE);
                    _ = SetForegroundWindow(hwnd);
                }
            } else {
                model.status = "\xe5\x89\xaa\xe8\xb4\xb4\xe6\x9d\xbf\xe4\xb8\xba\xe7\xa9\xba";
            }
        },
        .capture_qr => {
            if (model.capturing) return;
            model.capturing = true;
            model.status = "\xe6\xad\xa3\xe5\x9c\xa8\xe6\x8d\x95\xe8\x8e\xb7\xe6\x96\x87\xe6\x9c\xac...";
            keybd_event(@as(u8, @intCast(VK_CONTROL)), 0, 0, 0);
            keybd_event(0x43, 0, 0, 0);
            keybd_event(0x43, 0, KEYEVENTF_KEYUP, 0);
            keybd_event(@as(u8, @intCast(VK_CONTROL)), 0, KEYEVENTF_KEYUP, 0);
            fx.startTimer(.{
                .key = @as(u64, 3),
                .interval_ms = 200,
                .mode = .one_shot,
                .on_fire = Effects.timerMsg(.read_clipboard),
            });
        },
        .show_window => {
            const hwnd = FindWindowA(null, "QR Code Generator");
            if (hwnd != null) {
                _ = ShowWindow(hwnd, SW_RESTORE);
                _ = SetForegroundWindow(hwnd);
            }
            model.status = "\xe7\xaa\x97\xe5\x8f\xa3\xe5\xb7\xb2\xe6\x98\xbe\xe7\xa4\xba";
        },
        .hide_window => {
            const hwnd = FindWindowA(null, "QR Code Generator");
            if (hwnd != null) {
                _ = ShowWindow(hwnd, SW_HIDE);
            }
            model.status = "\xe7\xaa\x97\xe5\x8f\xa3\xe5\xb7\xb2\xe9\x9a\x90\xe8\x97\x8f\xe5\x88\xb0\xe6\x89\x98\xe7\x9b\x98";
        },
        .quit => {
            fx.closeWindow("main");
        },
        .hotkey_tick => |timer| {
            if (timer.outcome != .fired) return;
            if (!g_hotkey_fired) return;
            g_hotkey_fired = false;
            if (model.capturing) return;
            model.capturing = true;
            model.status = "\xe6\xad\xa3\xe5\x9c\xa8\xe6\x8d\x95\xe8\x8e\xb7\xe6\x96\x87\xe6\x9c\xac...";
            keybd_event(@as(u8, @intCast(VK_SHIFT)), 0, KEYEVENTF_KEYUP, 0);
            keybd_event(@as(u8, @intCast(VK_MENU)), 0, KEYEVENTF_KEYUP, 0);
            keybd_event(@as(u8, @intCast(VK_CONTROL)), 0, 0, 0);
            keybd_event(0x43, 0, 0, 0);
            keybd_event(0x43, 0, KEYEVENTF_KEYUP, 0);
            keybd_event(@as(u8, @intCast(VK_CONTROL)), 0, KEYEVENTF_KEYUP, 0);
            fx.startTimer(.{
                .key = @as(u64, 3),
                .interval_ms = 200,
                .mode = .one_shot,
                .on_fire = Effects.timerMsg(.read_clipboard),
            });
        },
        .read_clipboard => |timer| {
            if (timer.outcome != .fired) return;
            fx.readClipboard(.{
                .key = @as(u64, 2),
                .on_result = Effects.clipboardMsg(.captured_clipboard),
            });
        },
        .nav_prev => {
            if (model.qr_page > 1 and model.qr_page_count > 0) {
                model.qr_page -= 1;
                showQrPage(model, fx);
            }
        },
        .nav_next => {
            if (model.qr_page < model.qr_page_count and model.qr_page_count > 0) {
                model.qr_page += 1;
                showQrPage(model, fx);
            }
        },
        .show_main_window => |timer| {
            if (timer.outcome != .fired) return;
            const hwnd = FindWindowA(null, "QR Code Generator") orelse return;
            _ = ShowWindow(hwnd, SW_SHOW);
            _ = SetForegroundWindow(hwnd);
        },
    }
}

pub const AppUi = canvas.Ui(Msg);

pub fn view(ui: *AppUi, model: *const Model) AppUi.Node {
    return ui.column(.{ .gap = 12, .padding = 16 }, .{
        ui.row(.{ .gap = 8, .cross = .center }, .{
            ui.text(.{ .size = .heading }, "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe7\x94\x9f\xe6\x88\x90\xe5\x99\xa8"),
        }),
        ui.el(.textarea, .{
            .text = model.draft.text(),
            .placeholder = "Input text, generate QR...",
            .on_input = AppUi.inputMsg(.draft_edit),
            .height = 120,
        }, .{}),
        ui.row(.{ .gap = 8, .cross = .center }, .{
            ui.checkbox(.{ .checked = model.per_line, .text = "\xe6\xaf\x8f\xe8\xa1\x8c\xe4\xb8\x80\xe4\xb8\xaa\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81", .on_toggle = .toggle_per_line }),
            ui.spacer(1.0),
            ui.button(.{ .variant = .primary, .on_press = .generate }, "\xe7\x94\x9f\xe6\x88\x90"),
            ui.button(.{ .on_press = .save, .disabled = !model.has_qr }, "\xe4\xbf\x9d\xe5\xad\x98"),
        }),
        ui.spacer(1.0),
        navRow(ui, model),
        ui.row(.{ .main = .center, .cross = .center }, .{
            if (model.has_qr)
                ui.image(.{ .image = model.current_qr_image_id, .width = 280, .height = 280 })
            else
                ui.el(.stack, .{}, .{}),
        }),
        ui.statusBar(.{}, model.status),
    });
}

fn navRow(ui: *AppUi, model: *const Model) AppUi.Node {
    if (model.qr_page_count <= 1) return ui.el(.stack, .{}, .{});
    return ui.row(.{ .main = .center, .cross = .center, .gap = 8 }, .{
        ui.button(.{ .on_press = .nav_prev, .disabled = model.qr_page <= 1 }, "\xe2\x97\x80"),
        ui.el(.stack, .{ .width = 48, .main = .center, .cross = .center }, .{
            ui.text(.{}, ui.fmt("{d}/{d}", .{ model.qr_page, model.qr_page_count })),
        }),
        ui.button(.{ .on_press = .nav_next, .disabled = model.qr_page >= model.qr_page_count }, "\xe2\x96\xb6"),
    });
}

const QrApp = native_sdk.UiApp(Model, Msg);

pub fn initialModel() Model {
    return .{};
}

fn centerMainWindow() void {
    const hwnd = FindWindowA(null, "QR Code Generator") orelse return;
    const screen_w = GetSystemMetrics(0);
    const screen_h = GetSystemMetrics(1);
    const win_w = @as(c_int, @intFromFloat(window_width));
    const win_h = @as(c_int, @intFromFloat(window_height));
    _ = SetWindowPos(hwnd, null, @divTrunc(screen_w - win_w, 2), @divTrunc(screen_h - win_h, 2), 0, 0, 0x0001 | 0x0004);
}

fn registerGlobalHotkey(model: *Model) void {
    const hwnd = FindWindowA(null, "QR Code Generator") orelse {
        model.status = "\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae: \xe6\x9c\xaa\xe6\x89\xbe\xe5\x88\xb0\xe7\xaa\x97\xe5\x8f\xa3";
        return;
    };
    const my_addr: isize = @as(isize, @bitCast(@intFromPtr(&myWndProc)));
    const prev: isize = SetWindowLongPtrW(hwnd, GWLP_WNDPROC, my_addr);
    g_orig_wndproc = @as(usize, @bitCast(prev));
    const ok = RegisterHotKey(hwnd, HOTKEY_ID, MOD_ALT | MOD_SHIFT, 0x51);
    if (ok != 0) {
        model.status = "\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae: Shift+Alt+Q";
    } else {
        model.status = "\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae: \xe6\xb3\xa8\xe5\x86\x8c\xe5\xa4\xb1\xe8\xb4\xa5";
    }
}

fn setWindowIcon() void {
    const hwnd = FindWindowA(null, "QR Code Generator") orelse return;
    const sm_icon = LoadImageA(null, "icon.ico", IMAGE_ICON, 16, 16, LR_LOADFROMFILE) orelse return;
    const lg_icon = LoadImageA(null, "icon.ico", IMAGE_ICON, 32, 32, LR_LOADFROMFILE) orelse return;
    _ = SendMessageW(hwnd, WM_SETICON, ICON_SMALL, @as(isize, @bitCast(@intFromPtr(sm_icon))));
    _ = SendMessageW(hwnd, WM_SETICON, ICON_BIG, @as(isize, @bitCast(@intFromPtr(lg_icon))));
}

fn initFx(model: *Model, fx: *Effects) void {
    if (FindWindowA(null, "QR Code Generator")) |hwnd| {
        _ = ShowWindow(hwnd, SW_HIDE);
    }
    centerMainWindow();
    setWindowIcon();
    registerGlobalHotkey(model);
    fx.startTimer(.{
        .key = 1,
        .interval_ms = 200,
        .mode = .repeating,
        .on_fire = Effects.timerMsg(.hotkey_tick),
    });
    fx.startTimer(.{
        .key = @as(u64, 10),
        .interval_ms = 100,
        .mode = .one_shot,
        .on_fire = Effects.timerMsg(.show_main_window),
    });
}

fn onCommand(name: []const u8) ?Msg {
    if (std.mem.eql(u8, name, "capture_qr")) return .capture_qr;
    if (std.mem.eql(u8, name, "show_window")) return .show_window;
    if (std.mem.eql(u8, name, "hide_window")) return .hide_window;
    if (std.mem.eql(u8, name, "quit")) return .quit;
    return null;
}

pub fn main(init: std.process.Init) void {
    const has_console = GetConsoleWindow();
    FreeConsole();
    if (has_console != null) {
        _ = ShowWindow(has_console, SW_HIDE);
    }
    const app_state = QrApp.create(std.heap.page_allocator, .{
        .name = "qrcode",
        .scene = shell_scene,
        .canvas_label = canvas_label,
        .update_fx = update,
        .view = view,
        .on_command = onCommand,
        .init_fx = initFx,
        .status_item = .{
            .title = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe5\xb7\xa5\xe5\x85\xb7",
            .items = &.{
                native_sdk.platform.TrayMenuItem{ .id = 1, .label = "\xe6\x8d\x95\xe8\x8e\xb7\xe5\xb9\xb6\xe7\x94\x9f\xe6\x88\x90\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81", .command = "capture_qr" },
                native_sdk.platform.TrayMenuItem{ .id = 2, .separator = true },
                native_sdk.platform.TrayMenuItem{ .id = 3, .label = "\xe6\x98\xbe\xe7\xa4\xba\xe7\xaa\x97\xe5\x8f\xa3", .command = "show_window" },
                native_sdk.platform.TrayMenuItem{ .id = 4, .label = "\xe9\x9a\x90\xe8\x97\x8f\xe7\xaa\x97\xe5\x8f\xa3", .command = "hide_window" },
                native_sdk.platform.TrayMenuItem{ .id = 5, .separator = true },
                native_sdk.platform.TrayMenuItem{ .id = 6, .label = "\xe9\x80\x80\xe5\x87\xba", .command = "quit" },
            },
        },
    }) catch return;
    defer app_state.destroy();
    app_state.model = initialModel();

    runner.runWithOptions(app_state.app(), .{
        .app_name = "qrcode",
        .window_title = "QR Code Generator",
        .bundle_id = "dev.native_sdk.qrcode",
        .icon_path = "assets/icon.ico",
        .default_frame = geometry.RectF.init(0, 0, window_width, window_height),
        .restore_state = false,
        .js_window_api = false,
        .security = .{
            .permissions = &app_permissions,
            .navigation = .{ .allowed_origins = &.{ "zero://inline", "zero://app" } },
        },
        .shortcuts = &.{
            .{ .id = "capture_qr", .key = "q", .modifiers = .{ .control = true, .shift = true } },
        },
    }, init) catch {};
}

const module_size: u8 = 8;

fn generate_qr(model: *Model, fx: *Effects) !void {
    const allocator = std.heap.page_allocator;
    const text = model.draft.text();
    if (text.len == 0) return error.EmptyInput;

    if (model.per_line) {
        try generateMultiQr(model, fx, allocator);
        return;
    }

    freeQrPages(model, fx);

    var matrix = try qr_lib.create(allocator, .{ .content = text });
    defer matrix.deinit();

    const img_size = @as(u32, @intCast(matrix.size)) * module_size;
    const pixels = try allocator.alloc(u8, @as(usize, img_size) * img_size * 4);
    defer allocator.free(pixels);

    @memset(pixels, 255);
    render_qr(matrix, img_size, pixels);

    try fx.registerImage(model.qr_image_id, img_size, img_size, pixels);
    model.current_qr_image_id = model.qr_image_id;
    model.has_qr = true;
    model.status = "\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe5\xb7\xb2\xe7\x94\x9f\xe6\x88\x90";
}

fn generateMultiQr(model: *Model, fx: *Effects, allocator: std.mem.Allocator) !void {
    const text = model.draft.text();

    var lines = std.array_list.Managed([]const u8).init(allocator);
    defer lines.deinit();
    var line_iter = std.mem.splitScalar(u8, text, '\n');
    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0) try lines.append(trimmed);
    }
    if (lines.items.len == 0) return;

    var first_matrix = try qr_lib.create(allocator, .{ .content = lines.items[0] });
    defer first_matrix.deinit();

    const img_size = @as(u32, @intCast(first_matrix.size)) * module_size;
    const page_bytes = @as(usize, img_size) * img_size * 4;

    freeQrPages(model, fx);
    model.qr_pixels = try allocator.alloc(u8, lines.items.len * page_bytes);
    model.qr_page_count = lines.items.len;
    model.qr_img_size = img_size;

    @memset(model.qr_pixels[0..page_bytes], 255);
    render_qr(first_matrix, img_size, model.qr_pixels[0..page_bytes]);
    try fx.registerImage(base_multi_image_id, img_size, img_size, model.qr_pixels[0..page_bytes]);

    for (lines.items[1..], 1..) |item, i| {
        var m = try qr_lib.create(allocator, .{ .content = item });
        defer m.deinit();
        const slot = model.qr_pixels[i * page_bytes .. (i + 1) * page_bytes];
        @memset(slot, 255);
        render_qr(m, img_size, slot);
        try fx.registerImage(
            base_multi_image_id + @as(canvas.ImageId, @intCast(i)),
            img_size, img_size, slot,
        );
    }

    model.qr_page = 1;
    model.current_qr_image_id = base_multi_image_id;
    model.has_qr = true;
    model.status = "\xe5\xa4\x9a\xe8\xa1\x8c\xe4\xba\x8c\xe7\xbb\xb4\xe7\xa0\x81\xe5\xb7\xb2\xe7\x94\x9f\xe6\x88\x90";
}

fn showQrPage(model: *Model, fx: *Effects) void {
    _ = fx;
    if (model.qr_page_count == 0 or model.qr_pixels.len == 0) return;
    model.current_qr_image_id = base_multi_image_id + @as(canvas.ImageId, @intCast(model.qr_page - 1));
    model.has_qr = true;
}

fn freeQrPages(model: *Model, fx: *Effects) void {
    const old_count = model.qr_page_count;
    if (model.qr_pixels.len > 0) {
        std.heap.page_allocator.free(model.qr_pixels);
    }
    for (0..old_count) |i| {
        _ = fx.unregisterImage(base_multi_image_id + @as(canvas.ImageId, @intCast(i)));
    }
    model.qr_pixels = &.{};
    model.qr_page_count = 0;
    model.qr_img_size = 0;
    model.qr_page = 0;
    model.current_qr_image_id = 0;
}

fn save_qr(model: *Model, fx: *Effects) !void {
    const text = model.draft.text();
    if (text.len == 0) return error.EmptyInput;

    if (model.per_line) {
        try save_per_line(model, text);
        return;
    }

    const tmp_path = makeFilename(text, ".bmp");
    const len = std.mem.indexOfScalar(u8, &tmp_path, @as(u8, 0)) orelse tmp_path.len;
    const path = tmp_path[0..len];
    saveBmp(text, path, model, fx) catch {
        model.status = "\xe4\xbf\x9d\xe5\xad\x98\xe5\xa4\xb1\xe8\xb4\xa5";
        return;
    };
    const prefix = "\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98: ";
    var si: usize = 0;
    @memcpy(model.status_buf[0..prefix.len], prefix);
    si += prefix.len;
    for (path) |ch| {
        if (si >= model.status_buf.len) break;
        model.status_buf[si] = ch;
        si += 1;
    }
    model.status = model.status_buf[0..si];
}

fn saveBmp(text: []const u8, path: []const u8, model: *Model, fx: *Effects) !void {
    _ = model;
    _ = fx;
    const allocator = std.heap.page_allocator;
    var matrix = try qr_lib.create(allocator, .{ .content = text });
    defer matrix.deinit();
    const img_size = @as(u32, @intCast(matrix.size)) * module_size;
    const pixels = try allocator.alloc(u8, @as(usize, img_size) * img_size * 4);
    defer allocator.free(pixels);
    @memset(pixels, 255);
    render_qr(matrix, img_size, pixels);
    const bmp_bytes = try encodeBmp(allocator, img_size, img_size, pixels);
    defer allocator.free(bmp_bytes);
    try syncWriteFile(path, bmp_bytes);
}

fn save_per_line(model: *Model, text: []const u8) !void {
    const allocator = std.heap.page_allocator;
    if (text.len == 0) return;

    var lines = std.mem.splitScalar(u8, text, '\n');
    var index: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        index += 1;

        var matrix = try qr_lib.create(allocator, .{ .content = trimmed });
        defer matrix.deinit();

        const img_size = @as(u32, @intCast(matrix.size)) * module_size;
        const pixels = try allocator.alloc(u8, @as(usize, img_size) * img_size * 4);
        defer allocator.free(pixels);

        @memset(pixels, 255);
        render_qr(matrix, img_size, pixels);

        const bmp_bytes = try encodeBmp(allocator, img_size, img_size, pixels);
        defer allocator.free(bmp_bytes);

        const tmp_name = makeFilename(trimmed, ".bmp");
        const name_len = std.mem.indexOfScalar(u8, &tmp_name, @as(u8, 0)) orelse tmp_name.len;
        try syncWriteFile(tmp_name[0..name_len], bmp_bytes);
    }

    if (index > 0) {
        const prefix = "\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98 ";
        var si: usize = 0;
        @memcpy(model.status_buf[0..prefix.len], prefix);
        si += prefix.len;
        const idx_str = std.fmt.bufPrint(model.status_buf[si..], "{d}", .{index}) catch return;
        si += idx_str.len;
        const suffix = " \xe4\xb8\xaa\xe6\x96\x87\xe4\xbb\xb6";
        @memcpy(model.status_buf[si..][0..suffix.len], suffix);
        si += suffix.len;
        model.status = model.status_buf[0..si];
        model.has_qr = false;
    }
}

fn render_qr(matrix: anytype, img_size: u32, pixels: []u8) void {
    for (0..matrix.size) |r| {
        for (0..matrix.size) |c| {
            if (matrix.get(r, c) == 1) {
                const base_row = r * module_size;
                const base_col = c * module_size;
                var dr: u8 = 0;
                while (dr < module_size) : (dr += 1) {
                    var dc: u8 = 0;
                    while (dc < module_size) : (dc += 1) {
                        const px = ((base_row + dr) * img_size + (base_col + dc)) * 4;
                        pixels[px] = 0;
                        pixels[px + 1] = 0;
                        pixels[px + 2] = 0;
                        pixels[px + 3] = 255;
                    }
                }
            }
        }
    }
}

fn encodeBmp(allocator: std.mem.Allocator, width: u32, height: u32, rgba: []const u8) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const w = @as(usize, width);
    const h = @as(usize, height);
    const row_size = w * 4;
    const pixel_data_size = row_size * h;
    const data_offset: u32 = 14 + 40;
    const file_size: u32 = data_offset + @as(u32, @intCast(pixel_data_size));

    try buf.appendSlice("BM");
    try appendU32Le(&buf, file_size);
    try buf.appendSlice(&[_]u8{ 0, 0, 0, 0 });
    try appendU32Le(&buf, data_offset);

    try appendU32Le(&buf, 40);
    try appendU32Le(&buf, width);
    try appendU32Le(&buf, height);
    try appendU16Le(&buf, 1);
    try appendU16Le(&buf, 32);
    try appendU32Le(&buf, 0);
    try appendU32Le(&buf, @as(u32, @intCast(pixel_data_size)));
    try appendU32Le(&buf, 2835);
    try appendU32Le(&buf, 2835);
    try appendU32Le(&buf, 0);
    try appendU32Le(&buf, 0);

    var y: usize = h;
    while (y > 0) {
        y -= 1;
        const row = rgba[y * row_size .. (y + 1) * row_size];
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const offset = x * 4;
            try buf.append(row[offset + 2]);
            try buf.append(row[offset + 1]);
            try buf.append(row[offset + 0]);
            try buf.append(row[offset + 3]);
        }
    }

    return try buf.toOwnedSlice();
}

fn appendU32Le(list: *std.array_list.Managed(u8), value: u32) !void {
    try list.appendSlice(&[_]u8{
        @as(u8, @intCast(value & 0xFF)),
        @as(u8, @intCast((value >> 8) & 0xFF)),
        @as(u8, @intCast((value >> 16) & 0xFF)),
        @as(u8, @intCast((value >> 24) & 0xFF)),
    });
}

fn appendU16Le(list: *std.array_list.Managed(u8), value: u16) !void {
    try list.appendSlice(&[_]u8{
        @as(u8, @intCast(value & 0xFF)),
        @as(u8, @intCast((value >> 8) & 0xFF)),
    });
}

fn makeFilename(text: []const u8, ext: []const u8) [64]u8 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    for (text) |ch| {
        if (i >= 24) break;
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') {
            buf[i] = ch;
            i += 1;
        } else if (ch == ' ') {
            buf[i] = '_';
            i += 1;
        }
    }
    if (i == 0) {
        @memcpy(buf[0..6], "qrcode");
        i = 6;
    }
    const ext_slice = ext;
    @memcpy(buf[i..][0..ext_slice.len], ext_slice);
    return buf;
}

fn syncWriteFile(sub_path: []const u8, data: []const u8) !void {
    var threaded = std.Io.Threaded.init_single_threaded;
    const io = threaded.io();
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = sub_path,
        .data = data,
    });
}

test {
    _ = @import("tests.zig");
}
