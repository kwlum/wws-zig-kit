const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

fn handle(request: kit.Request, response: *kit.Response) !void {
    response.status = http.Status.ok;
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);    
}

pub fn main() !void {
    var allocator = std.heap.page_allocator;

    // Initialize Input and Output.
    var input = try kit.Input.fromStdIn(allocator, 65536);
    defer input.deinit();
    var output = try kit.Output.init(allocator);
    defer output.deinit();

    // Echo
    try handle(input.request.*, output.response);

    // Write output to stdout.
    try output.toStdOut(input.kv);
}
