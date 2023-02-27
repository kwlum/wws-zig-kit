const std = @import("std");
const http = std.http;
const time = std.time;

const kit = @import("wws-zig-kit");

const App = kit.Server(Context, Middleware);

const Context = struct {
    request_time: i64 = 0,
};

const Middleware = union(enum) {
    request_time: RequestTimeMiddleware,
    set_cookie: SetCookieMiddleware,

    pub fn run(
        self: *Middleware,
        ctx: *Context,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        next: *const App.Next,
    ) !void {
        switch (self.*) {
            inline else => |*s| try s.run(ctx, req, res, cache, next),
        }
    }
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
    pub fn run(
        _: *SetCookieMiddleware,
        ctx: *Context,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        next: *const App.Next,
    ) anyerror!void {
        try next.run(ctx, req, res, cache);
        var buf: [128]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "server-timestamp={d}", .{ctx.request_time});
        try res.headers.put("set-cookie", s);
    }
};

fn handle(ctx: *Context, _: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.print("Request-Time: {d}", .{ctx.request_time});
    response.status = http.Status.ok;
}

pub fn main() !void {
    var app = App.init(std.heap.c_allocator, 65535);
    var request_time_middleware = Middleware{ .request_time = RequestTimeMiddleware{} };
    var set_cookie_middleware = Middleware{ .request_time = RequestTimeMiddleware{} };
    var middlewares = [_]*Middleware{
        &request_time_middleware,
        &set_cookie_middleware,
    };
    app.middlewares = &middlewares;
    const handlers = [_]App.Handler{App.get(handle)};
    var context = Context{};
    try app.run(&context, &handlers);
}
