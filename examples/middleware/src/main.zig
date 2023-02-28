const std = @import("std");
const http = std.http;
const time = std.time;

const kit = @import("wws-zig-kit");

const App = kit.App(Context);
const Route = App.Route;

const Context = struct {
    request_time: i64 = 0,
};

const RequestTimeMiddleware = struct {
    pub fn run(
        _: *RequestTimeMiddleware,
        ctx: *Context,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        next: *const App.Next,
    ) anyerror!void {
        ctx.request_time = time.timestamp();
        try next.run(ctx, req, res, cache);
    }
};

const SetCookieMiddleware = struct {
    name: []const u8,

    pub fn run(
        self: *SetCookieMiddleware,
        ctx: *Context,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        next: *const App.Next,
    ) anyerror!void {
        try next.run(ctx, req, res, cache);
        var buf: [128]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{s}={d}", .{ self.name, ctx.request_time });
        try res.headers.put("set-cookie", s);
    }
};

fn handle(ctx: *Context, _: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.print("Request-Time: {d}", .{ctx.request_time});
    response.status = http.Status.ok;
}

pub fn main() !void {
    var request_time_middleware = RequestTimeMiddleware{};
    var set_cookie_middleware = SetCookieMiddleware{ .name = "x-timestamp" };
    var middlewares = [_]App.Middleware{
        App.Middleware.init(&request_time_middleware),
        App.Middleware.init(&set_cookie_middleware),
    };
    const routes = [_]Route{Route.get(handle)};
    var context = Context{};
    try App.run(std.heap.c_allocator, 65535, &context, &middlewares, &routes);
}
