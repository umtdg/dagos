const std = @import("std");
const Writer = std.Io.Writer;

const platform = @import("platform.zig");

pub var interface: Writer = .{
    .buffer = &.{},
    .vtable = &.{
        .drain = drain,
    },
};

pub fn writer() *Writer {
    return &interface;
}

fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
    _ = w;

    const uart = platform.console();

    const normal = data[0 .. data.len - 1];
    const pattern = data[data.len - 1];

    var written: usize = 0;

    for (normal) |bytes| {
        uart.write(bytes);
        written += bytes.len;
    }

    for (0..splat) |_| {
        uart.write(pattern);
        written += pattern.len;
    }

    return written;
}

pub fn write(bytes: []const u8) void {
    interface.writeAll(bytes) catch unreachable;
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    interface.print(fmt, args) catch unreachable;
}

pub fn println(comptime fmt: []const u8, args: anytype) void {
    interface.print(fmt ++ "\n", args) catch unreachable;
}
