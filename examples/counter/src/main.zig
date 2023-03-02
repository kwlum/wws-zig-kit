const std = @import("std");
const kit = @import("wws-zig-kit");

fn handle(_: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const counter_str = cache.get("counter") orelse "0";
    const counter = std.fmt.parseInt(u32, counter_str, 10) catch 0;

    var buf: [16]u8 = undefined;
    const counter_buf = try std.fmt.bufPrint(&buf, "{d}", .{counter + 1});
    try cache.put("counter", counter_buf);

    try response.body.print("Counter: {d}", .{counter});
    response.status = std.http.Status.ok;
}

pub fn main() !void {
    var routes = [_]kit.Route{kit.Route.get(handle)};
    try kit.run(std.heap.c_allocator, 65535, null, &routes);
}
