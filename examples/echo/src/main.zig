const std = @import("std");
const kit = @import("wws-zig-kit");

fn handleEcho(request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
    response.status = std.http.Status.ok;
}

pub fn main() !void {
    var routes = [_]kit.Route{kit.Route.post(handleEcho)};
    try kit.run(std.heap.c_allocator, 65535, null, &routes);
}
