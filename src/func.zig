const std = @import("std");

pub const Config = @import("./config.zig").Config;
pub const Error = @import("./error.zig").Error;
pub const Engine = @import("engine.zig").Engine;
pub const Store = @import("./store.zig").Store;
pub const Convert = @import("./utils.zig").Convert;
pub const WasmError = @import("./utils.zig").WasmError;

pub const wasm = @import("wasm");

const log = std.log.scoped(.wasmtime_zig);

pub const ByteVec = wasm.ByteVec;

pub const Func = struct {
    inner: *wasm.Func,

    pub const CallError = wasm.Func.CallError;

    pub fn init(store: *Store, callback: anytype) !Func {
        return Func{
            .inner = try wasm.Func.init(store.inner, callback),
        };
    }

    pub fn deinit(self: Func) void {
        self.inner.deinit();
    }

    //  \brief Call a WebAssembly function.
    //
    //  This function is used to invoke a function defined within a store. For
    //  example this might be used after extracting a function from a
    //  #wasmtime_instance_t.
    //
    //  \param store the store which owns `func`
    //  \param func the function to call
    //  \param args the arguments to the function call
    //  \param nargs the number of arguments provided
    //  \param results where to write the results of the function call
    //  \param nresults the number of results expected
    //  \param trap where to store a trap, if one happens.
    //
    //  There are three possible return states from this function:
    //
    //  1. The returned error is non-null. This means `results`
    //     wasn't written to and `trap` will have `NULL` written to it. This state
    //     means that programmer error happened when calling the function, for
    //     example when the size of the arguments/results was wrong, the types of the
    //     arguments were wrong, or arguments may come from the wrong store.
    //  2. The trap pointer is filled in. This means the returned error is `NULL` and
    //     `results` was not written to. This state means that the function was
    //     executing but hit a wasm trap while executing.
    //  3. The error and trap returned are both `NULL` and `results` are written to.
    //     This means that the function call succeeded and the specified results were
    //     produced.
    //
    //  The `trap` pointer cannot be `NULL`. The `args` and `results` pointers may be
    //  `NULL` if the corresponding length is zero.
    //
    //  Does not take ownership of #wasmtime_val_t arguments. Gives ownership of
    //  #wasmtime_val_t results.
    //
    extern "c" fn wasmtime_func_call(
        *wasm.Store, // wasmtime_context_t *store,
        *wasm.Func, // const wasmtime_func_t *func,
        *const wasm.ValVec, // const wasmtime_val_t *args,
        usize, // size_t nargs,
        *wasm.ValVec, // wasmtime_val_t *results,
        usize, // size_t nresults,
        *wasm.Trap, // wasm_trap_t **trap
    ) ?*WasmError;
};