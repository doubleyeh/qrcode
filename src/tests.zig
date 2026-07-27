const std = @import("std");
const qr = @import("qr.zig");
const testing = std.testing;

test "model initial state" {
    const main = @import("main.zig");
    const model = main.initialModel();
    try testing.expect(!model.has_qr);
    try testing.expect(!model.per_line);
    try testing.expectEqual(@as(usize, 0), model.draft.text().len);
}

test "qr library generates a matrix" {
    var matrix = try qr.create(testing.allocator, .{ .content = "Hello, QR!" });
    defer matrix.deinit();
    try testing.expect(matrix.size > 0);
}

test "qr library different inputs produce different outputs" {
    var a = try qr.create(testing.allocator, .{ .content = "AAAA" });
    defer a.deinit();
    var b = try qr.create(testing.allocator, .{ .content = "BBBB" });
    defer b.deinit();

    var same = true;
    for (0..a.size) |r| {
        for (0..a.size) |c| {
            if (a.get(r, c) != b.get(r, c)) {
                same = false;
                break;
            }
        }
        if (!same) break;
    }
    try testing.expect(!same);
}

test {
    _ = @import("qr/index.zig");
}
