const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

const App = kit.App(void);
const Route = App.Route;

fn handle(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    if (request.params.get("name")) |name| {
        try response.body.print("Product: {s}", .{name});
    } else {
        try response.body.writeAll("Product not found.");
    }
    response.status = http.Status.ok;
}

pub fn main() !void {
    const routes = [_]Route{Route.get(handle)};
    var no_context = {};
    try App.run(std.heap.c_allocator, 65535, &no_context, null, &routes);
}
