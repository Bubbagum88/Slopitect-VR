//! gamecoob: a Godot 4.7 extension for Slopitect. It adds one class,
//! `GameCoob` (a RefCounted), that runs GameCoob-Bios's rebuilt GameCube
//! intro and cube menu from the player's own ipl.bin and hands back each
//! finished picture. gamecube.gd (a live module) shows it in VR.
//!
//! Written straight against Godot's C interface (gdextension_interface.h,
//! 4.7) rather than a binding crate: one class with a handful of methods
//! taking ints, floats and byte arrays needs only a few of its calls.
//!
//! Methods (all called from Godot's main thread):
//!   open(rom: PackedByteArray) -> String   "" when the intro starts, else why not
//!   close()
//!   input(held: int, pressed: int)         pad bits: A 1, B 2, START 4, UP 8, DOWN 16, LEFT 32, RIGHT 64
//!   skip()                                 straight to the cube menu
//!   picture() -> PackedByteArray           the newest picture (RGB8, width x height), empty if none since the last call
//!   width() -> int, height() -> int
//!   state() -> int                         0 closed, 1 intro, 2 menu, 3 stopped (why() says why)
//!   why() -> String
//!   logic_frames() -> int, pictures() -> int, draw_ms() -> float
//!   set_threads(n: int)                    raster threads, 1 to 8 (3 by default)
//!   set_clock(y, mo, d, h, mi, s)          the menu's calendar

extern crate alloc;

#[path = "../GameCoob-Bios/src/ipl/mod.rs"]
#[allow(dead_code)]
mod ipl;

#[path = "../GameCoob-Bios/src/sdk/mod.rs"]
#[allow(dead_code)]
mod sdk;

#[path = "../GameCoob-Bios/src/card/mod.rs"]
#[allow(dead_code)]
mod card;

#[path = "../GameCoob-Bios/src/bs2/mod.rs"]
#[allow(dead_code)]
mod bs2;

mod console;

use console::Console;
use core::ffi::{CStr, c_char, c_void};
use std::sync::OnceLock;

// --- Godot's C interface: the few types and calls used ------------------------

type Ptr = *mut c_void;
type CPtr = *const c_void;

const LEVEL_SCENE: u32 = 2;
const T_NIL: u32 = 0;
const T_BOOL: u32 = 1;
const T_INT: u32 = 2;
const T_FLOAT: u32 = 3;
const T_STRING: u32 = 4;
const T_BYTES: u32 = 29;
const USAGE_DEFAULT: u32 = 6;
const METHOD_NORMAL: u32 = 1;
const CALL_INVALID_ARGUMENT: i32 = 2;
const CALL_TOO_MANY: i32 = 3;
const CALL_TOO_FEW: i32 = 4;

// Sizes of Godot's built-in types on a 64-bit build with 32-bit floats
// (extension_api.json's "float_64"): StringName and String 8, a packed
// array 16, Variant 24.
#[repr(C, align(8))]
struct StringName([u8; 8]);
#[repr(C, align(8))]
struct GString([u8; 8]);
#[repr(C, align(8))]
struct Bytes([u8; 16]);

#[repr(C)]
pub struct Initialization {
    minimum_level: u32,
    userdata: Ptr,
    initialize: unsafe extern "C" fn(Ptr, u32),
    deinitialize: unsafe extern "C" fn(Ptr, u32),
}

#[repr(C)]
struct CallError {
    error: i32,
    argument: i32,
    expected: i32,
}

#[repr(C)]
struct PropertyInfo {
    ty: u32,
    name: *mut StringName,
    class_name: *mut StringName,
    hint: u32,
    hint_string: *mut GString,
    usage: u32,
}

#[repr(C)]
struct MethodInfo {
    name: *mut StringName,
    userdata: Ptr,
    call: unsafe extern "C" fn(Ptr, Ptr, *const CPtr, i64, Ptr, *mut CallError),
    ptrcall: unsafe extern "C" fn(Ptr, Ptr, *const CPtr, Ptr),
    flags: u32,
    has_return: u8,
    return_info: *mut PropertyInfo,
    return_metadata: u32,
    argument_count: u32,
    arguments_info: *mut PropertyInfo,
    arguments_metadata: *mut u32,
    default_argument_count: u32,
    default_arguments: *mut Ptr,
}

#[repr(C)]
struct ClassCreationInfo6 {
    is_virtual: u8,
    is_abstract: u8,
    is_exposed: u8,
    is_runtime: u8,
    icon_path: CPtr,
    set_func: CPtr,
    get_func: CPtr,
    get_property_list_func: CPtr,
    free_property_list_func: CPtr,
    property_can_revert_func: CPtr,
    property_get_revert_func: CPtr,
    validate_property_func: CPtr,
    notification_func: CPtr,
    to_string_func: CPtr,
    reference_func: CPtr,
    unreference_func: CPtr,
    create_instance_func: unsafe extern "C" fn(Ptr, u8) -> Ptr,
    free_instance_func: unsafe extern "C" fn(Ptr, Ptr),
    recreate_instance_func: CPtr,
    get_virtual_func: CPtr,
    get_virtual_call_data_func: CPtr,
    call_virtual_with_data_func: CPtr,
    class_userdata: Ptr,
}

type GetProc = unsafe extern "C" fn(*const c_char) -> CPtr;
type PtrBuiltin = unsafe extern "C" fn(Ptr, *const CPtr, Ptr, i32);
type PtrConstructor = unsafe extern "C" fn(Ptr, *const CPtr);
type PtrDestructor = unsafe extern "C" fn(Ptr);
type FromVariant = unsafe extern "C" fn(Ptr, Ptr);
type ToVariant = unsafe extern "C" fn(Ptr, Ptr);

struct Api {
    library: usize,
    register_class: unsafe extern "C" fn(Ptr, CPtr, CPtr, *const ClassCreationInfo6),
    register_method: unsafe extern "C" fn(Ptr, CPtr, *const MethodInfo),
    unregister_class: unsafe extern "C" fn(Ptr, CPtr),
    construct_object: unsafe extern "C" fn(CPtr) -> Ptr,
    set_instance: unsafe extern "C" fn(Ptr, CPtr, Ptr),
    string_name_new: unsafe extern "C" fn(Ptr, *const c_char, u8),
    string_new: unsafe extern "C" fn(Ptr, *const c_char, i64) -> i64,
    string_destroy: PtrDestructor,
    variant_type: unsafe extern "C" fn(CPtr) -> u32,
    bytes_new: PtrConstructor,
    bytes_destroy: PtrDestructor,
    bytes_size: PtrBuiltin,
    bytes_resize: PtrBuiltin,
    bytes_at: unsafe extern "C" fn(Ptr, i64) -> *mut u8,
    bytes_at_const: unsafe extern "C" fn(CPtr, i64) -> *const u8,
    from_variant: [FromVariant; 4],  // int, float, bool, packed bytes
    to_variant: [ToVariant; 3],      // int, float, string
    bytes_to_variant: ToVariant,
}

static API: OnceLock<Api> = OnceLock::new();

fn api() -> &'static Api {
    API.get().expect("gamecoob: Godot's interface was never loaded")
}

struct Names {
    class: StringName,
    parent: StringName,
}

static NAMES: OnceLock<Names> = OnceLock::new();

unsafe fn load(get: GetProc, library: Ptr) -> Option<Api> {
    unsafe {
        let f = |name: &CStr| -> Option<CPtr> {
            let p = get(name.as_ptr());
            if p.is_null() { None } else { Some(p) }
        };
        macro_rules! proc_ {
            ($name:literal) => {
                core::mem::transmute(f($name)?)
            };
        }
        let get_builtin: unsafe extern "C" fn(u32, CPtr, i64) -> CPtr = proc_!(c"variant_get_ptr_builtin_method");
        let get_constructor: unsafe extern "C" fn(u32, i32) -> CPtr = proc_!(c"variant_get_ptr_constructor");
        let get_destructor: unsafe extern "C" fn(u32) -> CPtr = proc_!(c"variant_get_ptr_destructor");
        let to_type: unsafe extern "C" fn(u32) -> CPtr = proc_!(c"get_variant_to_type_constructor");
        let from_type: unsafe extern "C" fn(u32) -> CPtr = proc_!(c"get_variant_from_type_constructor");
        let string_name_new: unsafe extern "C" fn(Ptr, *const c_char, u8) = proc_!(c"string_name_new_with_latin1_chars");
        let builtin = |name: &'static CStr, hash: i64| -> Option<PtrBuiltin> {
            let mut sn = StringName([0; 8]);
            string_name_new(&mut sn as *mut _ as Ptr, name.as_ptr(), 1);
            let p = get_builtin(T_BYTES, &sn as *const _ as CPtr, hash);
            if p.is_null() { None } else { Some(core::mem::transmute::<CPtr, PtrBuiltin>(p)) }
        };
        let nn = |p: CPtr| if p.is_null() { None } else { Some(p) };
        Some(Api {
            library: library as usize,
            register_class: proc_!(c"classdb_register_extension_class6"),
            register_method: proc_!(c"classdb_register_extension_class_method"),
            unregister_class: proc_!(c"classdb_unregister_extension_class"),
            construct_object: proc_!(c"classdb_construct_object3"),
            set_instance: proc_!(c"object_set_instance"),
            string_name_new,
            string_new: proc_!(c"string_new_with_utf8_chars_and_len2"),
            string_destroy: core::mem::transmute(nn(get_destructor(T_STRING))?),
            variant_type: proc_!(c"variant_get_type"),
            bytes_new: core::mem::transmute(nn(get_constructor(T_BYTES, 0))?),
            bytes_destroy: core::mem::transmute(nn(get_destructor(T_BYTES))?),
            // Hashes from Godot 4.7.2's extension_api.json.
            bytes_size: builtin(c"size", 3173160232)?,
            bytes_resize: builtin(c"resize", 848867239)?,
            bytes_at: proc_!(c"packed_byte_array_operator_index"),
            bytes_at_const: proc_!(c"packed_byte_array_operator_index_const"),
            from_variant: [
                core::mem::transmute(nn(to_type(T_INT))?),
                core::mem::transmute(nn(to_type(T_FLOAT))?),
                core::mem::transmute(nn(to_type(T_BOOL))?),
                core::mem::transmute(nn(to_type(T_BYTES))?),
            ],
            to_variant: [
                core::mem::transmute(nn(from_type(T_INT))?),
                core::mem::transmute(nn(from_type(T_FLOAT))?),
                core::mem::transmute(nn(from_type(T_STRING))?),
            ],
            bytes_to_variant: core::mem::transmute(nn(from_type(T_BYTES))?),
        })
    }
}

fn string_name(s: &'static CStr) -> StringName {
    let mut sn = StringName([0; 8]);
    unsafe { (api().string_name_new)(&mut sn as *mut _ as Ptr, s.as_ptr(), 1) };
    sn
}

fn gstring(s: &str) -> GString {
    let mut g = GString([0; 8]);
    unsafe { (api().string_new)(&mut g as *mut _ as Ptr, s.as_ptr() as *const c_char, s.len() as i64) };
    g
}

/// A packed byte array (already made) as a Vec.
unsafe fn bytes_read(b: CPtr) -> Vec<u8> {
    unsafe {
        let mut n: i64 = 0;
        (api().bytes_size)(b as Ptr, core::ptr::null(), &mut n as *mut _ as Ptr, 0);
        if n <= 0 {
            return Vec::new();
        }
        core::slice::from_raw_parts((api().bytes_at_const)(b, 0), n as usize).to_vec()
    }
}

/// Makes a new packed byte array at `dest` holding `data`.
unsafe fn bytes_write(dest: Ptr, data: &[u8]) {
    unsafe {
        (api().bytes_new)(dest, core::ptr::null());
        if data.is_empty() {
            return;
        }
        let n = data.len() as i64;
        let args = [&n as *const i64 as CPtr];
        let mut ret: i64 = 0;
        (api().bytes_resize)(dest, args.as_ptr(), &mut ret as *mut _ as Ptr, 1);
        core::ptr::copy_nonoverlapping(data.as_ptr(), (api().bytes_at)(dest, 0), data.len());
    }
}

// --- The class ----------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Ty {
    Nil,
    Int,
    Float,
    Str,
    Bytes,
}

enum Arg {
    Int(i64),
    Bytes(Vec<u8>),
}

impl Arg {
    fn int(&self) -> i64 {
        match self {
            Arg::Int(i) => *i,
            Arg::Bytes(_) => 0,
        }
    }
}

enum Ret {
    Nil,
    Int(i64),
    Float(f64),
    Str(String),
    Bytes(Vec<u8>),
}

struct Method {
    name: &'static CStr,
    args: &'static [(&'static CStr, Ty)],
    ret: Ty,
    run: fn(&mut Console, Vec<Arg>) -> Ret,
}

const METHODS: &[Method] = &[
    Method { name: c"open", args: &[(c"rom", Ty::Bytes)], ret: Ty::Str, run: |c, mut a| {
        let Arg::Bytes(rom) = a.remove(0) else { return Ret::Str("rom must be a PackedByteArray".into()) };
        Ret::Str(c.open(rom))
    } },
    Method { name: c"close", args: &[], ret: Ty::Nil, run: |c, _| {
        c.close();
        Ret::Nil
    } },
    Method { name: c"input", args: &[(c"held", Ty::Int), (c"pressed", Ty::Int)], ret: Ty::Nil, run: |c, a| {
        c.input(a[0].int() as u32, a[1].int() as u32);
        Ret::Nil
    } },
    Method { name: c"skip", args: &[], ret: Ty::Nil, run: |c, _| {
        c.skip();
        Ret::Nil
    } },
    Method { name: c"picture", args: &[], ret: Ty::Bytes, run: |c, _| Ret::Bytes(c.take_picture().unwrap_or_default()) },
    Method { name: c"width", args: &[], ret: Ty::Int, run: |_, _| Ret::Int(console::WIDTH as i64) },
    Method { name: c"height", args: &[], ret: Ty::Int, run: |_, _| Ret::Int(console::HEIGHT as i64) },
    Method { name: c"state", args: &[], ret: Ty::Int, run: |c, _| Ret::Int(c.state()) },
    Method { name: c"why", args: &[], ret: Ty::Str, run: |c, _| Ret::Str(c.why()) },
    Method { name: c"logic_frames", args: &[], ret: Ty::Int, run: |c, _| Ret::Int(c.logic_frames()) },
    Method { name: c"pictures", args: &[], ret: Ty::Int, run: |c, _| Ret::Int(c.pictures()) },
    Method { name: c"draw_ms", args: &[], ret: Ty::Float, run: |c, _| Ret::Float(c.draw_ms()) },
    Method { name: c"set_threads", args: &[(c"n", Ty::Int)], ret: Ty::Nil, run: |c, a| {
        c.set_threads(a[0].int().clamp(1, 8) as u32);
        Ret::Nil
    } },
    Method {
        name: c"set_clock",
        args: &[(c"year", Ty::Int), (c"month", Ty::Int), (c"day", Ty::Int), (c"hour", Ty::Int), (c"minute", Ty::Int), (c"second", Ty::Int)],
        ret: Ty::Nil,
        run: |c, a| {
            let mut t = [0i32; 6];
            for (i, v) in a.iter().enumerate() {
                t[i] = v.int() as i32;
            }
            c.set_clock(t);
            Ret::Nil
        },
    },
];

fn variant_type_of(t: Ty) -> u32 {
    match t {
        Ty::Nil => T_NIL,
        Ty::Int => T_INT,
        Ty::Float => T_FLOAT,
        Ty::Str => T_STRING,
        Ty::Bytes => T_BYTES,
    }
}

fn guarded(m: &Method, c: &mut Console, args: Vec<Arg>) -> Ret {
    // A panic must not cross into Godot; the method then returns nothing.
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| (m.run)(c, args))).unwrap_or(match m.ret {
        Ty::Str => Ret::Str("gamecoob: the call failed".into()),
        Ty::Bytes => Ret::Bytes(Vec::new()),
        Ty::Int => Ret::Int(0),
        Ty::Float => Ret::Float(0.0),
        Ty::Nil => Ret::Nil,
    })
}

unsafe extern "C" fn method_call(userdata: Ptr, instance: Ptr, args: *const CPtr, count: i64, ret: Ptr, error: *mut CallError) {
    unsafe {
        let m = &*(userdata as *const Method);
        let error = &mut *error;
        let want = m.args.len() as i64;
        if count != want {
            error.error = if count > want { CALL_TOO_MANY } else { CALL_TOO_FEW };
            error.expected = want as i32;
            return;
        }
        let a = api();
        let mut out = Vec::with_capacity(m.args.len());
        for (i, (_, ty)) in m.args.iter().enumerate() {
            let v = *args.add(i) as Ptr;
            let got = (a.variant_type)(v);
            match ty {
                Ty::Int if got == T_INT || got == T_FLOAT || got == T_BOOL => {
                    let n = match got {
                        T_INT => {
                            let mut n: i64 = 0;
                            (a.from_variant[0])(&mut n as *mut _ as Ptr, v);
                            n
                        }
                        T_FLOAT => {
                            let mut f: f64 = 0.0;
                            (a.from_variant[1])(&mut f as *mut _ as Ptr, v);
                            f as i64
                        }
                        _ => {
                            let mut b: u8 = 0;
                            (a.from_variant[2])(&mut b as *mut _ as Ptr, v);
                            b as i64
                        }
                    };
                    out.push(Arg::Int(n));
                }
                Ty::Bytes if got == T_BYTES => {
                    let mut b = Bytes([0; 16]);
                    (a.from_variant[3])(&mut b as *mut _ as Ptr, v);
                    out.push(Arg::Bytes(bytes_read(&b as *const _ as CPtr)));
                    (a.bytes_destroy)(&mut b as *mut _ as Ptr);
                }
                _ => {
                    error.error = CALL_INVALID_ARGUMENT;
                    error.argument = i as i32;
                    error.expected = variant_type_of(*ty) as i32;
                    return;
                }
            }
        }
        match guarded(m, &mut *(instance as *mut Console), out) {
            Ret::Nil => {}
            Ret::Int(n) => (a.to_variant[0])(ret, &n as *const _ as Ptr),
            Ret::Float(f) => (a.to_variant[1])(ret, &f as *const _ as Ptr),
            Ret::Str(s) => {
                let mut g = gstring(&s);
                (a.to_variant[2])(ret, &mut g as *mut _ as Ptr);
                (a.string_destroy)(&mut g as *mut _ as Ptr);
            }
            Ret::Bytes(data) => {
                let mut b = Bytes([0; 16]);
                bytes_write(&mut b as *mut _ as Ptr, &data);
                (a.bytes_to_variant)(ret, &mut b as *mut _ as Ptr);
                (a.bytes_destroy)(&mut b as *mut _ as Ptr);
            }
        }
    }
}

unsafe extern "C" fn method_ptrcall(userdata: Ptr, instance: Ptr, args: *const CPtr, ret: Ptr) {
    unsafe {
        let m = &*(userdata as *const Method);
        let a = api();
        let mut out = Vec::with_capacity(m.args.len());
        for (i, (_, ty)) in m.args.iter().enumerate() {
            let p = *args.add(i);
            out.push(match ty {
                Ty::Bytes => Arg::Bytes(bytes_read(p)),
                _ => Arg::Int(*(p as *const i64)),
            });
        }
        // `ret` already holds a value of the return type: replace it.
        match guarded(m, &mut *(instance as *mut Console), out) {
            Ret::Nil => {}
            Ret::Int(n) => *(ret as *mut i64) = n,
            Ret::Float(f) => *(ret as *mut f64) = f,
            Ret::Str(s) => {
                (a.string_destroy)(ret);
                (a.string_new)(ret, s.as_ptr() as *const c_char, s.len() as i64);
            }
            Ret::Bytes(data) => {
                (a.bytes_destroy)(ret);
                bytes_write(ret, &data);
            }
        }
    }
}

unsafe extern "C" fn create_instance(_class: Ptr, _notify_postinitialize: u8) -> Ptr {
    unsafe {
        let names = NAMES.get().unwrap();
        let object = (api().construct_object)(&names.parent as *const _ as CPtr);
        let console = Box::into_raw(Box::new(Console::new()));
        (api().set_instance)(object, &names.class as *const _ as CPtr, console as Ptr);
        object
    }
}

unsafe extern "C" fn free_instance(_class: Ptr, instance: Ptr) {
    if !instance.is_null() {
        drop(unsafe { Box::from_raw(instance as *mut Console) });
    }
}

fn leak<T>(t: T) -> *mut T {
    Box::into_raw(Box::new(t))
}

fn property(ty: Ty, name: &'static CStr) -> PropertyInfo {
    PropertyInfo {
        ty: variant_type_of(ty),
        name: leak(string_name(name)),
        class_name: leak(string_name(c"")),
        hint: 0,
        hint_string: leak(gstring("")),
        usage: USAGE_DEFAULT,
    }
}

unsafe extern "C" fn initialize(_userdata: Ptr, level: u32) {
    if level != LEVEL_SCENE {
        return;
    }
    let a = api();
    let names = NAMES.get_or_init(|| Names { class: string_name(c"GameCoob"), parent: string_name(c"RefCounted") });
    let info = ClassCreationInfo6 {
        is_virtual: 0,
        is_abstract: 0,
        is_exposed: 1,
        is_runtime: 0,
        icon_path: core::ptr::null(),
        set_func: core::ptr::null(),
        get_func: core::ptr::null(),
        get_property_list_func: core::ptr::null(),
        free_property_list_func: core::ptr::null(),
        property_can_revert_func: core::ptr::null(),
        property_get_revert_func: core::ptr::null(),
        validate_property_func: core::ptr::null(),
        notification_func: core::ptr::null(),
        to_string_func: core::ptr::null(),
        reference_func: core::ptr::null(),
        unreference_func: core::ptr::null(),
        create_instance_func: create_instance,
        free_instance_func: free_instance,
        recreate_instance_func: core::ptr::null(),
        get_virtual_func: core::ptr::null(),
        get_virtual_call_data_func: core::ptr::null(),
        call_virtual_with_data_func: core::ptr::null(),
        class_userdata: core::ptr::null_mut(),
    };
    let library = a.library as Ptr;
    unsafe {
        (a.register_class)(library, &names.class as *const _ as CPtr, &names.parent as *const _ as CPtr, &info);
        for m in METHODS {
            let args: Vec<PropertyInfo> = m.args.iter().map(|(n, t)| property(*t, n)).collect();
            let mut metadata = vec![0u32; m.args.len()];
            let mut ret = property(m.ret, c"");
            let info = MethodInfo {
                name: leak(string_name(m.name)),
                userdata: m as *const Method as Ptr,
                call: method_call,
                ptrcall: method_ptrcall,
                flags: METHOD_NORMAL,
                has_return: (m.ret != Ty::Nil) as u8,
                return_info: &mut ret,
                return_metadata: 0,
                argument_count: args.len() as u32,
                arguments_info: args.as_ptr() as *mut PropertyInfo,
                arguments_metadata: metadata.as_mut_ptr(),
                default_argument_count: 0,
                default_arguments: core::ptr::null_mut(),
            };
            (a.register_method)(library, &names.class as *const _ as CPtr, &info);
        }
    }
}

unsafe extern "C" fn deinitialize(_userdata: Ptr, level: u32) {
    if level != LEVEL_SCENE {
        return;
    }
    if let (Some(a), Some(names)) = (API.get(), NAMES.get()) {
        unsafe { (a.unregister_class)(a.library as Ptr, &names.class as *const _ as CPtr) };
    }
}

/// The entry point named in gamecoob.gdextension.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn gamecoob_init(get_proc: GetProc, library: Ptr, init: *mut Initialization) -> u8 {
    let Some(loaded) = (unsafe { load(get_proc, library) }) else {
        return 0;
    };
    let _ = API.set(loaded);
    unsafe {
        *init = Initialization { minimum_level: LEVEL_SCENE, userdata: core::ptr::null_mut(), initialize, deinitialize };
    }
    1
}
