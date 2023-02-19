const std = @import("std");

const kit = @import("wws-zig-kit");

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    // Initialize Input and Output.
    var input = try kit.Input.fromStdIn(allocator, 65536);
    defer input.deinit();
    var output = try kit.Output.init(allocator, input);
    defer output.deinit();

    // Echo
    output.data = input.body;

    // Write output to stdout.
    try output.toStdOut();
}
