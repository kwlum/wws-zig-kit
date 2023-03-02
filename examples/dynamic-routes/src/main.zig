const std = @import("std");
const kit = @import("wws-zig-kit");

fn onGet(request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    if (request.params.get("name")) |name| {
        try response.body.print("Product: {s}", .{name});
    } else {
        try response.body.writeAll("Product not found.");
    }
    response.status = std.http.Status.ok;
}

pub fn main() !void {
    const routes = [_]kit.Route{kit.Route.get(onGet)};
    try kit.run(std.heap.c_allocator, 65535, null, &routes);
}
