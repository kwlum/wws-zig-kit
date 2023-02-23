const std = @import("std");
const fmt = std.fmt;
const http = std.http;
const io = std.io;
const json = std.json;
const mem = std.mem;

const kit = @import("wws-zig-kit");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const ctx: Context = .{ .allocator = allocator };

    try kit.run(Context, ctx, allocator, 65536, handle);
}

fn handle(ctx: Context, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const allocator = ctx.allocator;

    switch (request.method) {
        .GET => {
            // Get a list of todos.
            const todos = try getTodosFromKV(allocator, cache);
            try json.stringify(todos, .{}, response.body);
            try response.headers.put("content-type", "application/json");
            response.status = http.Status.ok;
        },
        .POST => {
            // Create new todo.
            const kv_todos = try getTodosFromKV(allocator, cache);
            const new_todo = try NewTodoBody.fromJsonString(allocator, request.body);
            const new_id = try genNextId(allocator, cache);

            // Append new todo into Output.KV.
            var todos = try allocator.alloc(Todo, kv_todos.len + 1);
            mem.copy(Todo, todos, kv_todos);
            todos[todos.len - 1] = Todo{
                .id = new_id,
                .text = new_todo.text,
                .completed = false,
            };
            try updateTodos(allocator, cache, todos);

            // Write new todo to Output.
            try json.stringify(todos[todos.len - 1], .{}, response.body);
            try response.headers.put("content-type", "application/json");
            response.status = http.Status.created;
        },
        .PUT => {
            // Update a todo.
            const update_todo = try UpdateTodoBody.fromJsonString(allocator, request.body);
            var kv_todos = try getTodosFromKV(allocator, cache);
            for (kv_todos) |*a| {
                if (a.id == update_todo.id) {
                    a.text = update_todo.text;
                    a.completed = update_todo.completed;
                    break;
                }
            }

            try updateTodos(allocator, cache, kv_todos);

            try response.headers.put("content-type", "application/json");
            try response.body.writeAll("{}");
            response.status = http.Status.ok;
        },
        .DELETE => {
            // Delete a todo.
            const delete_todo = try DeleteTodoBody.fromJsonString(allocator, request.body);
            const kv_todos = try getTodosFromKV(allocator, cache);

            var todos = try allocator.alloc(Todo, kv_todos.len);
            var i: u32 = 0;
            for (kv_todos) |a| {
                if (a.id != delete_todo.id) {
                    todos[i] = a;
                    i += 1;
                }
            }

            try updateTodos(allocator, cache, todos[0..i]);

            try response.headers.put("content-type", "application/json");
            try response.body.writeAll("{}");
            response.status = http.Status.ok;
        },
        else => {
            try response.body.writeAll("Bad Request!");
            try response.headers.put("content-type", "text/plain");
            response.status = http.Status.bad_request;
        },
    }
}

const Context = struct {
    allocator: mem.Allocator,
};

const Todo = struct {
    id: u32,
    text: []const u8,
    completed: bool,

    fn writeJson(self: Todo, writer: io.Writer) !void {
        try json.stringify(self, .{}, writer);
    }
};

const NewTodoBody = struct {
    text: []const u8,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !NewTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(NewTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

const UpdateTodoBody = struct {
    id: u32,
    text: []const u8,
    completed: bool,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !UpdateTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(UpdateTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

const DeleteTodoBody = struct {
    id: u32,

    fn fromJsonString(allocator: mem.Allocator, json_string: []const u8) !DeleteTodoBody {
        var todos_token_stream = json.TokenStream.init(json_string);
        return try json.parse(DeleteTodoBody, &todos_token_stream, .{ .allocator = allocator });
    }
};

fn getTodosFromKV(allocator: mem.Allocator, cache: *kit.Cache) ![]Todo {
    const todos_json_string = cache.get("todos") orelse "[]";
    var todos_token_stream = json.TokenStream.init(todos_json_string);
    return try json.parse([]Todo, &todos_token_stream, .{ .allocator = allocator });
}

fn updateTodos(allocator: mem.Allocator, cache: *kit.Cache, todos: []Todo) !void {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    try json.stringify(todos, .{}, buffer.writer());
    try cache.put("todos", buffer.toOwnedSlice());
}

fn genNextId(allocator: mem.Allocator, cache: *kit.Cache) !u32 {
    const next_id_string = cache.get("next_id") orelse "1";
    const next_id = fmt.parseInt(u32, next_id_string, 10) catch 1;

    const out_id_string = try fmt.allocPrint(allocator, "{d}", .{next_id + 1});
    try cache.put("next_id", out_id_string);

    return next_id;
}
