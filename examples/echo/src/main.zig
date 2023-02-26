const std = @import("std");
const http = std.http;

const kit = @import("wws-zig-kit");

const EchoRoute = kit.Route(void, NoMiddleware);

const NoMiddleware = struct {
    pub fn run(
        _: *const NoMiddleware,
        _: *void,
        _: *kit.Request,
        _: *kit.Response,
        _: *kit.Cache,
        _: *const EchoRoute.Next,
    ) !void {}
};

fn handleEcho(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll(request.body);
    response.status = http.Status.ok;
}

pub fn main() !void {
    var route = EchoRoute.init(std.heap.c_allocator, 65535);
    const handlers = [_]EchoRoute.Handler{EchoRoute.post(handleEcho)};
    route.middlewares = &[_]NoMiddleware{};
    var no_context: void = {};
    route.context = &no_context;
    try route.run(&handlers);
}
