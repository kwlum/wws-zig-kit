const std = @import("std");
const fmt = std.fmt;
const http = std.http;
const io = std.io;
const json = std.json;
const mem = std.mem;

const kit = @import("wws-zig-kit");

const App = kit.DefaultServer(Context);

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

fn listTodos(ctx: *Context, _: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const todos = try getTodosFromKV(ctx.allocator, cache);
    try json.stringify(todos, .{}, response.body);
    try response.headers.put("content-type", "application/json");
    response.status = http.Status.ok;
}

fn createTodo(ctx: *Context, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const kv_todos = try getTodosFromKV(ctx.allocator, cache);
    const new_todo = try NewTodoBody.fromJsonString(ctx.allocator, request.body);
    const new_id = try genNextId(ctx.allocator, cache);

    // Append new todo into Output.KV.
    var todos = try ctx.allocator.alloc(Todo, kv_todos.len + 1);
    mem.copy(Todo, todos, kv_todos);
    todos[todos.len - 1] = Todo{
        .id = new_id,
        .text = new_todo.text,
        .completed = false,
    };
    try updateTodos(ctx.allocator, cache, todos);

    // Write new todo to Output.
    try json.stringify(todos[todos.len - 1], .{}, response.body);
    try response.headers.put("content-type", "application/json");
    response.status = http.Status.created;
}

fn updateTodo(ctx: *Context, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const update_todo = try UpdateTodoBody.fromJsonString(ctx.allocator, request.body);
    var kv_todos = try getTodosFromKV(ctx.allocator, cache);
    for (kv_todos) |*a| {
        if (a.id == update_todo.id) {
            a.text = update_todo.text;
            a.completed = update_todo.completed;
            break;
        }
    }

    try updateTodos(ctx.allocator, cache, kv_todos);

    try response.headers.put("content-type", "application/json");
    try response.body.writeAll("{}");
    response.status = http.Status.ok;
}

fn deleteTodo(ctx: *Context, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const delete_todo = try DeleteTodoBody.fromJsonString(ctx.allocator, request.body);
    const kv_todos = try getTodosFromKV(ctx.allocator, cache);

    var todos = try ctx.allocator.alloc(Todo, kv_todos.len);
    var i: u32 = 0;
    for (kv_todos) |a| {
        if (a.id != delete_todo.id) {
            todos[i] = a;
            i += 1;
        }
    }

    try updateTodos(ctx.allocator, cache, todos[0..i]);

    try response.headers.put("content-type", "application/json");
    try response.body.writeAll("{}");
    response.status = http.Status.ok;
}

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

pub fn main() !void {
    const app = App.init(std.heap.c_allocator, 65535);
    const handlers = [_]App.Handler{
        App.get(listTodos),
        App.post(createTodo),
        App.put(updateTodo),
        App.delete(deleteTodo),
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ctx: Context = .{ .allocator = allocator };

    try app.run(&ctx, &handlers);
}
