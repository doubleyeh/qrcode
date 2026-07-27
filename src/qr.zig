const std = @import("std");
const qr_lib = @import("qr/index.zig");

pub const ErrorCorrectionLevel = qr_lib.ErrorCorrectionLevel;
pub const CreateOptions = qr_lib.CreateOptions;
pub const BitMatrix = @import("qr/bit-matrix.zig").BitMatrix;

pub fn create(allocator: std.mem.Allocator, options: CreateOptions) !BitMatrix {
    return qr_lib.create(allocator, options);
}

test {
    _ = @import("qr/index.zig");
}
