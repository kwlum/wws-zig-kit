const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

const App = kit.App(void);
const Route = App.Route;

fn handleEcho(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
    response.status = http.Status.ok;
}

pub fn main() !void {
    const routes = [_]Route{Route.post(handleEcho)};
    var no_context = {};
    try App.run(std.heap.c_allocator, 65535, &no_context, null, &routes);
}
