const std = @import("std");
const testing = std.testing;
pub const c = @cImport({
    @cInclude("wasm.h");
    @cInclude("wasmtime.h");
});

pub const Error = error{ EngineInit, StoreInit, ModuleInit, FuncInit, InstanceInit };

pub const Engine = struct {
    engine: *c.wasm_engine_t,

    const Self = @This();

    pub fn init() !Self {
        const engine = c.wasm_engine_new() orelse return Error.EngineInit;
        return Self{
            .engine = engine,
        };
    }

    pub fn deinit(self: Self) void {
        c.wasm_engine_delete(self.engine);
    }
};

pub const Store = struct {
    store: *c.wasm_store_t,

    const Self = @This();

    pub fn init(engine: Engine) !Self {
        const store = c.wasm_store_new(engine.engine) orelse return Error.StoreInit;
        return Self{
            .store = store,
        };
    }

    pub fn deinit(self: Self) void {
        c.wasm_store_delete(self.store);
    }
};

pub const Module = struct {
    module: *c.wasm_module_t,

    const Self = @This();

    pub fn initFromWasm(store: Store, wasm: []const u8) !Self {
        var wasm_bytes: c.wasm_byte_vec_t = undefined;
        c.wasm_byte_vec_new_uninitialized(&wasm_bytes, wasm.len);
        defer c.wasm_byte_vec_delete(&wasm_bytes);

        var i: usize = 0;
        var ptr = wasm_bytes.data;
        while (i < wasm.len) : (i += 1) {
            ptr.* = wasm[i];
            ptr += 1;
        }

        return Self.init(store, &wasm_bytes);
    }

    pub fn initFromWat(store: Store, wat: []const u8) !Self {
        var wat_bytes: c.wasm_byte_vec_t = undefined;
        c.wasm_byte_vec_new_uninitialized(&wat_bytes, wat.len);
        defer c.wasm_byte_vec_delete(&wat_bytes);

        var i: usize = 0;
        var ptr = wat_bytes.data;
        while (i < wat.len) : (i += 1) {
            ptr.* = wat[i];
            ptr += 1;
        }

        var wasm_bytes: c.wasm_byte_vec_t = undefined;
        const err = c.wasmtime_wat2wasm(&wat_bytes, &wasm_bytes);
        errdefer c.wasmtime_error_delete(err.?);
        defer c.wasm_byte_vec_delete(&wasm_bytes);

        if (err) |e| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasmtime_error_message(e, &msg);
            defer c.wasm_byte_vec_delete(&msg);

            // TODO print error message
            std.debug.warn("unexpected error occurred", .{});
            return Error.ModuleInit;
        }

        return Self.init(store, &wasm_bytes);
    }

    fn init(store: Store, wasm_bytes: *c.wasm_byte_vec_t) !Self {
        var module: ?*c.wasm_module_t = null;
        const err = c.wasmtime_module_new(store.store, wasm_bytes, &module);
        errdefer c.wasmtime_error_delete(err.?);

        if (err) |e| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasmtime_error_message(e, &msg);
            defer c.wasm_byte_vec_delete(&msg);

            // TODO print error message
            std.debug.warn("unexpected error occurred", .{});
            return Error.ModuleInit;
        }

        return Self{
            .module = module.?,
        };
    }

    pub fn deinit(self: Self) void {
        c.wasm_module_delete(self.module);
    }
};

pub const Func = struct {
    func: *c.wasm_func_t,

    const Self = @This();

    pub fn init(store: Store, callback: fn (?*const c.wasm_val_t, ?*c.wasm_val_t) callconv(.C) ?*c.wasm_trap_t) !Self {
        // TODO implement creating arbitrary Wasm callbacks from parameter and result
        // lists
        var c_functype: *c.wasm_functype_t = undefined;
        c_functype = c.wasm_functype_new_0_0() orelse return Error.FuncInit;
        defer c.wasm_functype_delete(c_functype);

        var func: *c.wasm_func_t = undefined;
        func = c.wasm_func_new(store.store, c_functype, callback) orelse return Error.FuncInit;

        return Self{
            .func = func,
        };
    }
};

pub const Instance = struct {
    instance: *c.wasm_instance_t,

    const Self = @This();

    // TODO accepts a list of imports
    pub fn init(module: Module, import: Func) !Self {
        var trap: ?*c.wasm_trap_t = null;
        var instance: ?*c.wasm_instance_t = null;
        const imports = [_]?*c.wasm_extern_t{c.wasm_func_as_extern(import.func)};
        const err = c.wasmtime_instance_new(module.module, &imports, 1, &instance, &trap);
        errdefer {
            if (err) |e| {
                c.wasmtime_error_delete(e);
            }
            if (trap) |t| {
                c.wasm_trap_delete(t);
            }
        }

        if (err) |e| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasmtime_error_message(e, &msg);
            defer c.wasm_byte_vec_delete(&msg);

            // TODO print error message
            std.debug.warn("unexpected error occurred", .{});
            return Error.InstanceInit;
        }
        if (trap) |t| {
            // TODO handle trap message
            std.debug.warn("code unexpectedly trapped", .{});
            return Error.InstanceInit;
        }

        return Self{
            .instance = instance.?,
        };
    }

    pub fn getFuncExport(self: Self, name: []const u8) !?Callable {
        var externs: c.wasm_extern_vec_t = undefined;
        c.wasm_instance_exports(self.instance, &externs);
        defer c.wasm_extern_vec_delete(&externs);

        // TODO handle finding the export by name.
        const run_func = c.wasm_extern_as_func(externs.data[0]) orelse return null;
        const owned = c.wasm_func_copy(run_func);
        return Callable{
            .func = owned.?,
        };
    }

    pub fn deinit(self: Self) void {
        c.wasm_instance_delete(self.instance);
    }
};

pub const Callable = struct {
    func: *c.wasm_func_t,

    pub fn call(self: Callable) !void {
        var trap: ?*c.wasm_trap_t = null;
        const err = c.wasmtime_func_call(self.func, null, 0, null, 0, &trap);
        errdefer {
            if (err) |e| {
                c.wasmtime_error_delete(e);
            }
            if (trap) |t| {
                c.wasm_trap_delete(t);
            }
        }

        if (err) |e| {
            var msg: c.wasm_byte_vec_t = undefined;
            c.wasmtime_error_message(e, &msg);
            defer c.wasm_byte_vec_delete(&msg);

            // TODO print error message
            std.debug.warn("unexpected error occurred", .{});
            return Error.InstanceInit;
        }
        if (trap) |t| {
            // TODO handle trap message
            std.debug.warn("code unexpectedly trapped", .{});
            return Error.InstanceInit;
        }
    }
};

test "" {
    _ = Engine;
    _ = Store;
    _ = Module;
}
