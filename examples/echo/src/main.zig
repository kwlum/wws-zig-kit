const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

fn handle(_: void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    response.status = http.Status.ok;
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
}

pub fn main() !void {
    try kit.run(void, {}, std.heap.c_allocator, 65536, handle);
}
