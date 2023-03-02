# WWS kit in Zig
An experimental [WWS](https://github.com/vmware-labs/wasm-workers-server) kit written in zig.


# Usage Examples

## Hello World

```zig
const std = @import("std");
const kit = @import("wws-zig-kit");

fn handle(request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    try response.headers.put("content-type", "text/plain");
    try response.body.writeAll("Hello World!");
    response.status = std.http.Status.ok;
}

pub fn main() !void {
    const routes = [_]kit.Route{kit.Route.get(handle)};    
    try kit.run(std.heap.c_allocator, 65535, null, &routes);
}
```


## Cache (Key/Value Store)

ex: [counter](examples/counter/src/main.zig)
```zig
fn handle(_: *void, request: kit.Request, response: *kit.Response, cache: *kit.Cache) !void {
    const counter_str = cache.get("counter") orelse "0";
    const counter = std.fmt.parseInt(u32, counter_str, 10) catch 0;

    var buf: [16]u8 = undefined;
    const counter_buf = try std.fmt.bufPrint(&buf, "{d}", .{counter + 1});
    try cache.put("counter", counter_buf);

    try response.body.print("Counter: {d}", .{counter});
    response.status = std.http.Status.ok;
}
```


## Dynamic routes

ex: [dynamic-routes](examples/dynamic-routes/src/main.zig)
```zig
fn handle(_: *void, request: kit.Request, response: *kit.Response, _: *kit.Cache) !void {    
    if (request.params.get("id")) |id| {
        try response.body.print("Product Id: {s}", .{id});
    } else {
        try response.body.writeAll("Product not found.");
    }

    try response.headers.put("content-type", "text/plain");
    response.status = http.Status.ok;
}
```


## Environment variables

```zig
fn handle(_: kit.Request, response: *kit.Response, _: *kit.Cache) !void {
    response.status = std.http.Status.ok;

    const msg = std.os.getenv("message") orelse "";
    try response.body.writeAll(msg);
}
```


# Build and Run
Build the echo example, require zig-0.10.1 installed:

    zig build 

Run WWS inside workers directory, require WWS installed.

    wws www

Call the http endpoint with:

    curl -d "Hello World!" http://localhost:8080/echo