const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

fn handle(_: void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
    response.status = http.Status.ok;
}

pub fn main() !void {
    const EchoRoute = kit.Route(void);
    const route = EchoRoute.init(std.heap.c_allocator, 65535);
    const methods = .{EchoRoute.post(handle)};
    try route.run({}, methods);
}
