const std = @import("std");
const http = std.http;
const time = std.time;

const kit = @import("wws-zig-kit");

const Context = struct {
    request_time: i64 = 0,
};

const RequestTimeMiddleware = struct {
    context: *Context,

    pub fn run(
        self: *RequestTimeMiddleware,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        pipeline: *const kit.Pipeline,
    ) anyerror!void {
        self.context.request_time = time.timestamp();
        try pipeline.next(req, res, cache);
    }
};

const SetCookieMiddleware = struct {
    context: *Context,
    name: []const u8,

    pub fn run(
        self: *SetCookieMiddleware,
        req: *kit.Request,
        res: *kit.Response,
        cache: *kit.Cache,
        pipeline: *const kit.Pipeline,
    ) anyerror!void {
        try pipeline.next(req, res, cache);
        var buf: [128]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "{s}={d}", .{ self.name, self.context.request_time });
        try res.headers.put("set-cookie", s);
    }
};

const GetHandler = struct {
    context: *Context,

    pub fn handle(
        self: *GetHandler,
        _: kit.Request,
        response: *kit.Response,
        _: *kit.Cache,
    ) !void {
        try response.headers.put("content-type", "text/plain");
        try response.body.print("Request-Time: {d}", .{self.context.request_time});
        response.status = http.Status.ok;
    }
};

pub fn handle(
    context: *Context,
    _: kit.Request,
    response: *kit.Response,
    _: *kit.Cache,
) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.print("The Request-Time: {d}", .{context.request_time});
    response.status = http.Status.ok;
}

pub fn main() !void {
    var context: Context = .{};
    var request_time_middleware: RequestTimeMiddleware = .{
        .context = &context,
    };
    var set_cookie_middleware: SetCookieMiddleware = .{
        .context = &context,
        .name = "x-timestamp",
    };
    var middlewares = [_]kit.Middleware{
        kit.Middleware.init(&request_time_middleware),
        kit.Middleware.init(&set_cookie_middleware),
    };

    const routes = [_]kit.Route{
        kit.Route.context(&context).get(handle),
    };
    try kit.run(std.heap.c_allocator, 65535, &middlewares, &routes);
}
