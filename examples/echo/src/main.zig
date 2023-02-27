const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

const App = kit.DefaultServer(void);

fn handleEcho(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
    response.status = http.Status.ok;
}

pub fn main() !void {
    var app = App.init(std.heap.c_allocator, 65535);
    const handlers = [_]App.Handler{App.post(handleEcho)};
    var no_context = {};
    try app.run(&no_context, &handlers);
}
