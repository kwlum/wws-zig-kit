const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const http = std.http;
const json = std.json;
const mem = std.mem;

pub const Error = error{
    RouteNotFound,
};

pub const Params = std.StringHashMap([]const u8);

pub const Request = struct {
    method: http.Method,
    headers: Headers,
    params: Params,
    path: []const u8,
    query: []const u8,
    body: []const u8,
};

pub const Response = struct {
    status: http.Status,
    headers: Headers,
    body: std.ArrayList(u8).Writer,
    allocator: mem.Allocator,
};

pub const Cache = struct {
    store: std.StringHashMap([]const u8),
    allocator: mem.Allocator,

    fn init(allocator: mem.Allocator) Cache {
        return .{
            .allocator = allocator,
            .store = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn get(self: *const Cache, name: []const u8) ?[]const u8 {
        return self.store.get(name);
    }

    /// name and value are copied.
    pub fn put(self: *Cache, name: []const u8, value: []const u8) !void {
        const n = try self.allocator.dupe(u8, name);
        const v = try self.allocator.dupe(u8, value);
        try self.store.put(n, v);
    }
};

pub const Headers = struct {
    store: std.StringHashMap([]const u8),
    allocator: mem.Allocator,

    fn init(allocator: mem.Allocator) Headers {
        return .{
            .allocator = allocator,
            .store = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn get(self: *const Headers, name: []const u8) ?[]const u8 {
        return self.store.get(name);
    }

    /// name and value are copied.
    pub fn put(self: *Headers, name: []const u8, value: []const u8) !void {
        const n = try self.allocator.dupe(u8, name);
        const v = try self.allocator.dupe(u8, value);
        try self.store.put(n, v);
    }
};

pub const Route = union(enum) {
    fn_route: FnRoute,
    custom_route: CustomRoute,
    context_route: ContextFnRoute,

    const RouteType = enum { all, specific };
    const HandleFn = fn (Request, *Response, *Cache) anyerror!void;

    pub fn custom(http_method: http.Method, handler: anytype) Route {
        return .{ .custom_route = CustomRoute.init(.specific, http_method, handler) };
    }

    pub fn allCustom(handler: anytype) Route {
        return .{ .custom_route = CustomRoute.init(.all, .GET, handler) };
    }

    pub fn context(ctx: anytype) ContextRoute(@typeInfo(@TypeOf(ctx)).Pointer.child) {
        const C = @TypeOf(ctx);
        const c_info = @typeInfo(C);

        if (c_info != .Pointer) @compileError("ctx is not Pointer.");

        return ContextRoute(c_info.Pointer.child).init(ctx);
    }

    pub fn on(http_method: http.Method, handle_fn: *const HandleFn) Route {
        return .{ .fn_route = .{
            .route_type = .specific,
            .method_type = http_method,
            .handle_fn = handle_fn,
        } };
    }

    pub fn all(handle_fn: *const HandleFn) Route {
        return .{ .fn_route = .{
            .route_type = .all,
            .method_type = .GET,
            .handle_fn = handle_fn,
        } };
    }

    pub fn get(handle_fn: *const HandleFn) Route {
        return on(.GET, handle_fn);
    }

    pub fn post(handle_fn: *const HandleFn) Route {
        return on(.POST, handle_fn);
    }

    pub fn put(handle_fn: *const HandleFn) Route {
        return on(.PUT, handle_fn);
    }

    pub fn delete(handle_fn: *const HandleFn) Route {
        return on(.DELETE, handle_fn);
    }

    pub fn head(handle_fn: *const HandleFn) Route {
        return on(.HEAD, handle_fn);
    }

    pub fn patch(handle_fn: *const HandleFn) Route {
        return on(.PATCH, handle_fn);
    }

    pub fn connect(handle_fn: *const HandleFn) Route {
        return on(.CONNECT, handle_fn);
    }

    pub fn options(handle_fn: *const HandleFn) Route {
        return on(.OPTIONS, handle_fn);
    }

    pub fn trace(handle_fn: *const HandleFn) Route {
        return on(.TRACE, handle_fn);
    }

    fn method(self: *const Route) http.Method {
        switch (self.*) {
            inline else => |s| return s.method(),
        }
    }

    fn routeType(self: *const Route) RouteType {
        switch (self.*) {
            inline else => |s| return s.routeType(),
        }
    }

    fn handle(
        self: *const Route,
        request: Request,
        response: *Response,
        cache: *Cache,
    ) !void {
        switch (self.*) {
            inline else => |*s| try s.handle(request, response, cache),
        }
    }

    const FnRoute = struct {
        route_type: RouteType,
        method_type: http.Method,
        handle_fn: *const HandleFn,

        fn handle(
            self: *const FnRoute,
            request: Request,
            response: *Response,
            cache: *Cache,
        ) !void {
            try self.handle_fn(request, response, cache);
        }

        fn method(self: *const FnRoute) http.Method {
            return self.method_type;
        }

        fn routeType(self: *const FnRoute) RouteType {
            return self.route_type;
        }
    };

    fn ContextRoute(comptime T: type) type {
        return struct {
            context: *T,

            const Self = @This();
            const ContextHandleFnPtr = *const fn (*T, Request, *Response, *Cache) anyerror!void;

            fn init(ctx: *T) ContextRoute(T) {
                return .{
                    .context = ctx,
                };
            }

            pub fn on(self: Self, http_method: http.Method, handle_fn: ContextHandleFnPtr) Route {
                return .{
                    .context_route = ContextFnRoute.init(T, self.context, .specific, http_method, handle_fn),
                };
            }

            pub fn all(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return .{
                    .context_route = ContextFnRoute.init(T, self.context, .all, .GET, handle_fn),
                };
            }

            pub fn get(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.GET, handle_fn);
            }

            pub fn post(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.POST, handle_fn);
            }

            pub fn put(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.PUT, handle_fn);
            }

            pub fn delete(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.DELETE, handle_fn);
            }

            pub fn head(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.HEAD, handle_fn);
            }

            pub fn patch(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.PATCH, handle_fn);
            }

            pub fn connect(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.CONNECT, handle_fn);
            }

            pub fn options(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.OPTIONS, handle_fn);
            }

            pub fn trace(self: Self, handle_fn: ContextHandleFnPtr) Route {
                return self.on(.TRACE, handle_fn);
            }
        };
    }

    const ContextFnRoute = struct {
        route_type: RouteType,
        method_type: http.Method,
        handle_fn: *const fn (*anyopaque, *const fn () void, Request, *Response, *Cache) anyerror!void,
        context: *anyopaque,
        fn_ptr: *const fn () void,

        fn init(
            comptime T: type,
            ctx: *T,
            route_type: RouteType,
            http_method: http.Method,
            handle_fn: *const fn (*T, Request, *Response, *Cache) anyerror!void,
        ) ContextFnRoute {
            const alignment = @typeInfo(@TypeOf(ctx)).Pointer.alignment;

            const S = struct {
                pub fn handle(
                    ptr: *anyopaque,
                    fn_ptr: *const fn () void,
                    request: Request,
                    response: *Response,
                    cache: *Cache,
                ) !void {
                    const s_ctx = if (alignment >= 1)
                        @ptrCast(*T, @alignCast(alignment, ptr))
                    else
                        @ptrCast(*T, ptr);

                    const handler = @ptrCast(*const fn (*T, Request, *Response, *Cache) anyerror!void, fn_ptr);

                    try @call(.{}, handler, .{ s_ctx, request, response, cache });
                }
            };

            return .{
                .route_type = route_type,
                .method_type = http_method,
                .context = ctx,
                .handle_fn = S.handle,
                .fn_ptr = @ptrCast(*const fn () void, handle_fn),
            };
        }

        fn handle(
            self: *const ContextFnRoute,
            request: Request,
            response: *Response,
            cache: *Cache,
        ) !void {
            try self.handle_fn(self.context, self.fn_ptr, request, response, cache);
        }

        fn method(self: *const ContextFnRoute) http.Method {
            return self.method_type;
        }

        fn routeType(self: *const ContextFnRoute) RouteType {
            return self.route_type;
        }
    };

    const CustomRoute = struct {
        route_type: RouteType,
        method_type: http.Method,
        ptr: *anyopaque,
        handle_fn: *const fn (*anyopaque, Request, *Response, *Cache) anyerror!void,

        fn init(route_type: RouteType, http_method: http.Method, route: anytype) CustomRoute {
            const R = @TypeOf(route);
            const r_info = @typeInfo(R);

            if (r_info != .Pointer) @compileError("route is not pointer.");
            if (r_info.Pointer.size != .One) @compileError("route is not single item pointer.");

            const alignment = r_info.Pointer.alignment;

            const S = struct {
                pub fn handle(
                    ptr: *anyopaque,
                    request: Request,
                    response: *Response,
                    cache: *Cache,
                ) !void {
                    const self = if (alignment >= 1)
                        @ptrCast(R, @alignCast(alignment, ptr))
                    else
                        @ptrCast(R, ptr);

                    try @call(.{}, r_info.Pointer.child.handle, .{
                        self,
                        request,
                        response,
                        cache,
                    });
                }
            };

            return .{
                .route_type = route_type,
                .method_type = http_method,
                .ptr = route,
                .handle_fn = S.handle,
            };
        }

        fn handle(
            self: *const CustomRoute,
            request: Request,
            response: *Response,
            cache: *Cache,
        ) !void {
            try self.handle_fn(self.ptr, request, response, cache);
        }

        fn method(self: *const CustomRoute) http.Method {
            return self.method_type;
        }

        fn routeType(self: *const CustomRoute) RouteType {
            return self.route_type;
        }
    };
};

pub const Middleware = struct {
    ptr: *anyopaque,
    run_fn: *const fn (*anyopaque, *Request, *Response, *Cache, *const Pipeline) anyerror!void,

    pub fn init(middleware: anytype) Middleware {
        const M = @TypeOf(middleware);
        const m_info = @typeInfo(M);

        if (m_info != .Pointer) @compileError("middleware is not pointer.");
        if (m_info.Pointer.size != .One) @compileError("middleware is not single item pointer.");

        const alignment = m_info.Pointer.alignment;

        const S = struct {
            pub fn run(
                ptr: *anyopaque,
                request: *Request,
                response: *Response,
                cache: *Cache,
                pipeline: *const Pipeline,
            ) !void {
                const self = if (alignment >= 1)
                    @ptrCast(M, @alignCast(alignment, ptr))
                else
                    @ptrCast(M, ptr);

                try @call(.{}, m_info.Pointer.child.run, .{
                    self,
                    request,
                    response,
                    cache,
                    pipeline,
                });
            }
        };

        return .{
            .ptr = middleware,
            .run_fn = S.run,
        };
    }

    pub fn run(
        self: Middleware,
        request: *Request,
        response: *Response,
        cache: *Cache,
        pipeline: *const Pipeline,
    ) !void {
        try self.run_fn(self.ptr, request, response, cache, pipeline);
    }
};

pub const Pipeline = union(enum) {
    middleware: MiddlewareNode,
    request_handler: RequestHandlerNode,

    const MiddlewareNode = struct {
        middleware: Middleware,
        pipeline: *const Pipeline,

        pub fn run(
            self: *const MiddlewareNode,
            request: *Request,
            response: *Response,
            cache: *Cache,
        ) !void {
            try self.middleware.run(request, response, cache, self.pipeline);
        }
    };

    const RequestHandlerNode = struct {
        routes: []const Route,

        pub fn run(
            self: *const RequestHandlerNode,
            request: *Request,
            response: *Response,
            cache: *Cache,
        ) !void {
            // Match the request method and invoke specific handler.
            // Lookup the type all handler.
            var type_all_route: ?*const Route = null;
            for (self.routes) |*route| {
                switch (route.routeType()) {
                    .specific => {
                        if (route.method() == request.method) {
                            try route.handle(request.*, response, cache);
                            break;
                        }
                    },
                    .all => type_all_route = route,
                }
            } else {
                // Invoke the type all handler or throw error.
                if (type_all_route) |route| {
                    try route.handle(request.*, response, cache);
                } else {
                    return Error.RouteNotFound;
                }
            }
        }
    };

    pub fn next(
        self: *const Pipeline,
        request: *Request,
        response: *Response,
        cache: *Cache,
    ) !void {
        switch (self.*) {
            inline else => |s| try s.run(request, response, cache),
        }
    }
};

pub fn run(
    allocator: mem.Allocator,
    max_request_size: usize,
    middlewares: ?[]Middleware,
    routes: []const Route,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Create middlewares pipeline if exist.
    const middlewares_len = if (middlewares) |a| a.len else 0;
    var pipeline = try arena.allocator().alloc(Pipeline, middlewares_len + 1);
    for (pipeline[0 .. pipeline.len - 1]) |*a, i| {
        a.* = .{
            .middleware = .{
                .middleware = middlewares.?[i],
                .pipeline = &pipeline[i + 1],
            },
        };
    }

    // The last in the pipeline is always request handler.
    pipeline[pipeline.len - 1] = .{
        .request_handler = .{
            .routes = routes,
        },
    };

    // Initialize Input and Output.
    var input: Input = undefined;
    var output: Output = undefined;
    try Input.fromStdIn(arena.allocator(), max_request_size, &input);
    try Output.init(arena.allocator(), &output);

    // Run the pipeline.
    try pipeline[0].next(&input.request, &output.response, &input.cache);

    // Write output to stdout.
    try output.toStdOut(&input.cache);
}

// Internal IO structures.
const Input = struct {
    request: Request,
    cache: Cache,

    fn fromStdIn(allocator: mem.Allocator, max_size: usize, input: *Input) !void {
        // Parse Input json string from stdin.
        const stdin = std.io.getStdIn().reader();
        const input_string = try stdin.readAllAlloc(allocator, max_size);
        var json_parser = json.Parser.init(allocator, false);
        const json_tree = try json_parser.parse(input_string);

        // Populate cache.
        input.cache = Cache.init(allocator);
        const tree_kv = json_tree.root.Object.get("kv").?.Object;
        const tree_kv_keys = tree_kv.keys();
        for (tree_kv_keys) |kv_key| {
            try input.cache.store.put(kv_key, tree_kv.get(kv_key).?.String);
        }

        // Construct Request.
        const request_path = if (json_tree.root.Object.get("url")) |a| a.String else "/";
        const request_body = if (json_tree.root.Object.get("body")) |a| a.String else "";
        input.request = .{
            .method = .GET,
            .headers = Headers.init(allocator),
            .params = Params.init(allocator),
            .path = request_path,
            .query = "",
            .body = request_body,
        };

        // Populate request params.
        if (json_tree.root.Object.get("params")) |a| {
            const params_tree = a.Object;
            const params_tree_keys = params_tree.keys();
            for (params_tree_keys) |key| {
                try input.request.params.put(key, params_tree.get(key).?.String);
            }
        }

        // Populate Request Headers.
        const tree_headers = json_tree.root.Object.get("headers").?.Object;
        const tree_headers_keys = tree_headers.keys();
        for (tree_headers_keys) |header_key| {
            try input.request.headers.store.put(header_key, tree_headers.get(header_key).?.String);
        }

        // Determine Request Method.
        var method_buffer: [16]u8 = undefined;
        const method_string = if (json_tree.root.Object.get("method")) |a|
            ascii.lowerString(&method_buffer, a.String)
        else
            "get";

        if (mem.eql(u8, method_string, "get")) {
            input.request.method = .GET;
        } else if (mem.eql(u8, method_string, "head")) {
            input.request.method = .HEAD;
        } else if (mem.eql(u8, method_string, "post")) {
            input.request.method = .POST;
        } else if (mem.eql(u8, method_string, "put")) {
            input.request.method = .PUT;
        } else if (mem.eql(u8, method_string, "delete")) {
            input.request.method = .DELETE;
        } else if (mem.eql(u8, method_string, "connect")) {
            input.request.method = .CONNECT;
        } else if (mem.eql(u8, method_string, "options")) {
            input.request.method = .OPTIONS;
        } else if (mem.eql(u8, method_string, "trace")) {
            input.request.method = .TRACE;
        } else if (mem.eql(u8, method_string, "patch")) {
            input.request.method = .PATCH;
        }
    }
};

const Output = struct {
    data: std.ArrayList(u8),
    response: Response,
    base64: bool = false,

    fn init(allocator: mem.Allocator, output: *Output) !void {
        output.base64 = false;
        output.data = std.ArrayList(u8).init(allocator);
        output.response.status = http.Status.ok;
        output.response.headers = Headers.init(allocator);
        output.response.body = output.data.writer();
        output.response.allocator = allocator;
    }

    fn toStdOut(self: *Output, cache: *const Cache) !void {
        const stdout_writer = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout_writer);
        const stdout = buffered_writer.writer();

        // Write base64 and status.
        try stdout.print("{{\"status\":{d},\"base64\":{},", .{ @enumToInt(self.response.status), self.base64 });

        // Write headers.
        const headers_len = self.response.headers.store.count();
        var i: usize = 0;
        var headers_entry_itr = self.response.headers.store.iterator();
        _ = try stdout.write("\"headers\":{");
        while (headers_entry_itr.next()) |entry| {
            try json.encodeJsonString(entry.key_ptr.*, .{}, stdout);
            _ = try stdout.write(":");
            try json.encodeJsonString(entry.value_ptr.*, .{}, stdout);

            if (i < headers_len - 1) {
                _ = try stdout.write(",");
            }

            i += 1;
        }
        _ = try stdout.write("},");

        // Write KV.
        i = 0;
        const cache_len = cache.store.count();
        var cache_entry_itr = cache.store.iterator();
        _ = try stdout.write("\"kv\":{");
        while (cache_entry_itr.next()) |entry| {
            try json.encodeJsonString(entry.key_ptr.*, .{}, stdout);
            _ = try stdout.write(":");
            try json.encodeJsonString(entry.value_ptr.*, .{}, stdout);

            if (i < cache_len - 1) {
                _ = try stdout.write(",");
            }

            i += 1;
        }
        _ = try stdout.write("},");

        // Write data.
        _ = try stdout.write("\"data\":");
        try json.encodeJsonString(self.data.items, .{}, stdout);
        _ = try stdout.write("}");

        try buffered_writer.flush();
    }
};
