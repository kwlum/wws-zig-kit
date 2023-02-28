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

pub fn App(comptime Context: type) type {
    return struct {
        pub const Middleware = struct {
            ptr: *anyopaque,
            run_fn: *const fn (*anyopaque, *Context, *Request, *Response, *Cache, *const Next) anyerror!void,

            pub fn init(middleware: anytype) Middleware {
                const M = @TypeOf(middleware);
                const m_info = @typeInfo(M);

                if (m_info != .Pointer) @compileError("middleware is not pointer.");
                if (m_info.Pointer.size != .One) @compileError("middleware is not single item pointer.");

                const alignment = m_info.Pointer.alignment;

                const S = struct {
                    pub fn run(
                        ptr: *anyopaque,
                        context: *Context,
                        request: *Request,
                        response: *Response,
                        cache: *Cache,
                        next: *const Next,
                    ) !void {
                        const self = if (alignment >= 1)
                            @ptrCast(M, @alignCast(alignment, ptr))
                        else
                            @ptrCast(M, ptr);

                        try @call(.{}, m_info.Pointer.child.run, .{
                            self,
                            context,
                            request,
                            response,
                            cache,
                            next,
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
                context: *Context,
                request: *Request,
                response: *Response,
                cache: *Cache,
                next: *const Next,
            ) !void {
                try self.run_fn(self.ptr, context, request, response, cache, next);
            }
        };

        pub const Route = struct {
            handle_fn: *const HandleFn,
            method: http.Method,
            route_type: enum { all, specific },

            const HandleFn = fn (*Context, Request, *Response, *Cache) anyerror!void;

            pub fn all(handle_fn: *const HandleFn) Route {
                return .{
                    .handle_fn = handle_fn,
                    .method = http.Method.GET,
                    .route_type = .all,
                };
            }

            pub fn onMethod(method: http.Method, handle_fn: *const HandleFn) Route {
                return .{
                    .handle_fn = handle_fn,
                    .method = method,
                    .route_type = .specific,
                };
            }

            pub fn get(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.GET, handle_fn);
            }

            pub fn post(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.POST, handle_fn);
            }

            pub fn put(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.PUT, handle_fn);
            }

            pub fn delete(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.DELETE, handle_fn);
            }

            pub fn head(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.HEAD, handle_fn);
            }

            pub fn patch(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.PATCH, handle_fn);
            }

            pub fn connect(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.CONNECT, handle_fn);
            }

            pub fn options(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.OPTIONS, handle_fn);
            }

            pub fn trace(handle_fn: *const HandleFn) Route {
                return onMethod(http.Method.TRACE, handle_fn);
            }
        };

        pub const Next = union(enum) {
            middleware: MiddlewareNext,
            request_handler: RequestHandlerNext,

            const MiddlewareNext = struct {
                middleware: Middleware,
                next: *const Next,

                pub fn run(
                    self: *const MiddlewareNext,
                    ctx: *Context,
                    request: *Request,
                    response: *Response,
                    cache: *Cache,
                ) !void {
                    try self.middleware.run(ctx, request, response, cache, self.next);
                }
            };

            const RequestHandlerNext = struct {
                routes: []const Route,

                pub fn run(
                    self: *const RequestHandlerNext,
                    ctx: *Context,
                    request: *Request,
                    response: *Response,
                    cache: *Cache,
                ) !void {
                    // Match the request method and invoke specific handler.
                    // Lookup the type all handler.
                    var type_all_route: ?Route = null;
                    for (self.routes) |route| {
                        switch (route.route_type) {
                            .specific => {
                                if (route.method == request.method) {
                                    try @call(.{}, route.handle_fn, .{ ctx, request.*, response, cache });
                                    break;
                                }
                            },
                            .all => type_all_route = route,
                        }
                    } else {
                        // Invoke the type all handler or throw error.
                        if (type_all_route) |route| {
                            try @call(.{}, route.handle_fn, .{ ctx, request.*, response, cache });
                        } else {
                            return Error.RouteNotFound;
                        }
                    }
                }
            };

            pub fn run(
                self: *const Next,
                ctx: *Context,
                request: *Request,
                response: *Response,
                cache: *Cache,
            ) !void {
                switch (self.*) {
                    inline else => |s| try s.run(ctx, request, response, cache),
                }
            }
        };

        pub fn run(
            allocator: mem.Allocator,
            max_request_size: usize,
            context: *Context,
            middlewares: ?[]Middleware,
            routes: []const Route,
        ) !void {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();

            // Create middlewares pipeline if exist.
            const middlewares_len = if (middlewares) |a| a.len else 0;
            var nexts = try arena.allocator().alloc(Next, middlewares_len + 1);
            for (nexts[0 .. nexts.len - 1]) |*a, i| {
                a.* = .{
                    .middleware = .{
                        .middleware = middlewares.?[i],
                        .next = &nexts[i + 1],
                    },
                };
            }

            // The last in the pipeline is always request handler.
            nexts[nexts.len - 1] = .{
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
            try nexts[0].run(context, &input.request, &output.response, &input.cache);

            // Write output to stdout.
            try output.toStdOut(&input.cache);
        }
    };
}

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
            .method = http.Method.GET,
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
            input.request.method = http.Method.GET;
        } else if (mem.eql(u8, method_string, "head")) {
            input.request.method = http.Method.HEAD;
        } else if (mem.eql(u8, method_string, "post")) {
            input.request.method = http.Method.POST;
        } else if (mem.eql(u8, method_string, "put")) {
            input.request.method = http.Method.PUT;
        } else if (mem.eql(u8, method_string, "delete")) {
            input.request.method = http.Method.DELETE;
        } else if (mem.eql(u8, method_string, "connect")) {
            input.request.method = http.Method.CONNECT;
        } else if (mem.eql(u8, method_string, "options")) {
            input.request.method = http.Method.OPTIONS;
        } else if (mem.eql(u8, method_string, "trace")) {
            input.request.method = http.Method.TRACE;
        } else if (mem.eql(u8, method_string, "patch")) {
            input.request.method = http.Method.PATCH;
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
