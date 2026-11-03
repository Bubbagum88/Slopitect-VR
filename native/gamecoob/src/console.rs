//! The console: GameCoob's intro and cube menu running on a thread of their
//! own at 60 logic frames a second, as `boot_intro.rs` runs them on a PC.
//! Godot's frame never waits for the software renderer: the module asks for
//! the latest finished picture and gets nothing when there's no new one.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use crate::bs2;
use crate::bs2::bs2main::{Bs2Main, FrameInput};
use crate::bs2::menu::backend::{FakeCards, FakeDrive};
use crate::bs2::menu::volumes::{Entry, Volume, Volumes};
use crate::bs2::menu::{MenuAssets, SysInfo};
use crate::bs2::pad;
use crate::ipl;

pub const WIDTH: usize = bs2::render::EFB_W;
pub const HEIGHT: usize = bs2::render::EFB_H;

/// Pad bits, as gamecube.gd sends them.
pub const A: u32 = 1;
pub const B: u32 = 2;
pub const START: u32 = 4;
pub const UP: u32 = 8;
pub const DOWN: u32 = 16;
pub const LEFT: u32 = 32;
pub const RIGHT: u32 = 64;

/// What `state()` reports.
pub const CLOSED: i64 = 0;
pub const INTRO: i64 = 1;
pub const MENU: i64 = 2;
pub const STOPPED: i64 = 3;

/// Logic frames caught up before a picture is drawn, at most: past this a
/// slow renderer slows the intro down instead of skipping through it.
const MAX_CATCH_UP: u64 = 4;

#[derive(Default)]
struct Shared {
    stop: AtomicBool,
    skip: AtomicBool,
    held: AtomicU32,
    /// Presses since the last logic frame (latched, as `boot_intro.rs` does).
    pressed: AtomicU32,
    threads: AtomicU32,
    state: AtomicU32,
    logic_frames: AtomicU32,
    pictures: AtomicU32,
    /// Microseconds the last picture took to draw.
    draw_us: AtomicU32,
    clock: Mutex<[i32; 6]>,
    /// The latest picture, RGB8, taken by `take_picture`.
    picture: Mutex<Option<Vec<u8>>>,
    /// Why the console stopped by itself (a panic in the renderer).
    why: Mutex<String>,
}

pub struct Console {
    shared: Arc<Shared>,
    worker: Option<JoinHandle<()>>,
}

impl Console {
    pub fn new() -> Console {
        let shared = Shared::default();
        shared.threads.store(3, Ordering::Relaxed);
        Console { shared: Arc::new(shared), worker: None }
    }

    /// Reads the dump and starts the intro; an empty string when it runs.
    pub fn open(&mut self, rom: Vec<u8>) -> String {
        self.close();
        let threads = self.shared.threads.load(Ordering::Relaxed);
        let clock = *self.shared.clock.lock().unwrap();
        let shared = Arc::new(Shared::default());
        shared.threads.store(threads, Ordering::Relaxed);
        *shared.clock.lock().unwrap() = clock;
        self.shared = shared.clone();
        let (tx, rx) = mpsc::channel::<String>();
        let worker = std::thread::Builder::new().name("gamecoob".into()).spawn(move || {
            let run = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(rom, &shared, &tx)));
            if let Err(e) = run {
                let what = e.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| e.downcast_ref::<String>().cloned()).unwrap_or_default();
                *shared.why.lock().unwrap() = format!("the renderer stopped: {what}");
                let _ = tx.send(format!("the renderer stopped while loading: {what}"));
            }
            shared.state.store(STOPPED as u32, Ordering::Release);
        });
        let worker = match worker {
            Ok(w) => w,
            Err(e) => return format!("couldn't start a thread: {e}"),
        };
        self.worker = Some(worker);
        match rx.recv() {
            Ok(problem) if problem.is_empty() => String::new(),
            Ok(problem) => {
                self.close();
                problem
            }
            Err(_) => "the renderer stopped while loading".into(),
        }
    }

    pub fn close(&mut self) {
        self.shared.stop.store(true, Ordering::Release);
        if let Some(w) = self.worker.take() {
            let _ = w.join();
        }
        self.shared.state.store(CLOSED as u32, Ordering::Release);
    }

    pub fn input(&self, held: u32, pressed: u32) {
        self.shared.held.store(held, Ordering::Relaxed);
        self.shared.pressed.fetch_or(pressed, Ordering::AcqRel);
    }

    pub fn skip(&self) {
        self.shared.skip.store(true, Ordering::Release);
    }

    pub fn set_threads(&self, n: u32) {
        self.shared.threads.store(n.clamp(1, 8), Ordering::Relaxed);
    }

    pub fn set_clock(&self, t: [i32; 6]) {
        *self.shared.clock.lock().unwrap() = t;
    }

    pub fn state(&self) -> i64 {
        if self.worker.is_none() {
            return CLOSED;
        }
        self.shared.state.load(Ordering::Acquire) as i64
    }

    pub fn why(&self) -> String {
        self.shared.why.lock().unwrap().clone()
    }

    pub fn logic_frames(&self) -> i64 {
        self.shared.logic_frames.load(Ordering::Relaxed) as i64
    }

    pub fn pictures(&self) -> i64 {
        self.shared.pictures.load(Ordering::Relaxed) as i64
    }

    pub fn draw_ms(&self) -> f64 {
        self.shared.draw_us.load(Ordering::Relaxed) as f64 / 1000.0
    }

    /// The newest picture since the last call (RGB8, WIDTH x HEIGHT), if any.
    pub fn take_picture(&self) -> Option<Vec<u8>> {
        self.shared.picture.lock().unwrap().take()
    }
}

impl Drop for Console {
    fn drop(&mut self) {
        self.close();
    }
}

fn sys_info(time: [i32; 6]) -> SysInfo {
    // Game Play lists nothing to boot; Options and the calendar change
    // nothing outside the console (their actions are dropped).
    SysInfo { time, entries: Vec::new(), timeout: 5, vendor: "Slopitect".into(), fw_ui: false }
}

/// No disks to browse: the Memory Card screen's file side lists nothing.
struct NoVolumes;

impl Volumes for NoVolumes {
    fn volumes(&mut self) -> Vec<Volume> {
        Vec::new()
    }
    fn list(&mut self, _id: &str, _path: &str) -> Result<Vec<Entry>, String> {
        Err("no volumes in Slopitect".into())
    }
    fn read(&mut self, _id: &str, _path: &str) -> Result<Vec<u8>, String> {
        Err("no volumes in Slopitect".into())
    }
    fn write(&mut self, _id: &str, _path: &str, _bytes: &[u8]) -> Result<(), String> {
        Err("no volumes in Slopitect".into())
    }
    fn mkdir(&mut self, _id: &str, _path: &str) -> Result<(), String> {
        Err("no volumes in Slopitect".into())
    }
}

/// gamecube.gd's pad bits as the GameCube pad's buttons.
fn pad_buttons(bits: u32) -> u16 {
    let mut out = 0;
    for (bit, button) in [
        (A, pad::PAD_BUTTON_A),
        (B, pad::PAD_BUTTON_B),
        (START, pad::PAD_BUTTON_START),
        (UP, pad::PAD_BUTTON_UP),
        (DOWN, pad::PAD_BUTTON_DOWN),
        (LEFT, pad::PAD_BUTTON_LEFT),
        (RIGHT, pad::PAD_BUTTON_RIGHT),
    ] {
        if bits & bit != 0 {
            out |= button;
        }
    }
    out
}

/// The worker: load, then logic at 60 Hz (BS2Main's loop, which reads the
/// pad and finds new presses itself) and a picture after each catch-up.
fn run(rom: Vec<u8>, shared: &Shared, ready: &mpsc::Sender<String>) {
    let parsed = ipl::Ipl::parse(&rom);
    let ipl = match parsed {
        Ok(ipl) => ipl,
        Err(e) => {
            let _ = ready.send(format!("not a GameCube IPL dump this can read ({e:?})"));
            return;
        }
    };
    let Some(assets) = bs2::Assets::load(&ipl) else {
        let _ = ready.send("the dump's intro models didn't load".into());
        return;
    };
    let Some(ma) = MenuAssets::load(&ipl) else {
        let _ = ready.send("the dump's menu models didn't load".into());
        return;
    };
    drop(ipl);
    drop(rom);
    let mut bs = Bs2Main::new(&assets, Box::new(FakeDrive::new()), Box::new(FakeCards::new()), Box::new(NoVolumes));
    let mut target = bs2::raster::Target::new(WIDTH, HEIGHT);
    shared.state.store(INTRO as u32, Ordering::Release);
    let _ = ready.send(String::new());

    let t0 = Instant::now();
    let mut done = 0u64;
    while !shared.stop.load(Ordering::Acquire) {
        let due = (t0.elapsed().as_secs_f64() * 60.0) as u64;
        if due <= done {
            let next = Duration::from_secs_f64((done + 1) as f64 / 60.0);
            std::thread::sleep(next.saturating_sub(t0.elapsed()).max(Duration::from_micros(500)));
            continue;
        }
        done = done.max(due.saturating_sub(MAX_CATCH_UP));
        if shared.skip.swap(false, Ordering::AcqRel) && bs.menu.is_none() {
            bs.skip_intro();
        }
        // A press shorter than a logic frame still counts: it's held for
        // the first frame of this catch-up.
        let mut pressed = shared.pressed.swap(0, Ordering::AcqRel);
        while done < due {
            done += 1;
            shared.logic_frames.fetch_add(1, Ordering::Relaxed);
            let mut input = FrameInput::default();
            input.pads[0].button = pad_buttons(shared.held.load(Ordering::Relaxed) | pressed);
            pressed = 0;
            if let Some(m) = &mut bs.menu {
                m.info.time = *shared.clock.lock().unwrap();
            }
            let _ = bs.update(&assets, &ma, &input, || sys_info(*shared.clock.lock().unwrap()));
            let state = if bs.menu.is_some() { MENU } else { INTRO };
            shared.state.store(state as u32, Ordering::Release);
        }
        let d0 = Instant::now();
        let threads = shared.threads.load(Ordering::Relaxed) as usize;
        bs.render(&mut target, &assets, &ma, &|job| {
            std::thread::scope(|sc| {
                for _ in 1..threads {
                    sc.spawn(|| job.work());
                }
                job.work();
            });
        });
        let mut rgb = Vec::with_capacity(WIDTH * HEIGHT * 3);
        for c in &target.color {
            for x in c {
                rgb.push((x.clamp(0.0, 1.0) * 255.0 + 0.5) as u8);
            }
        }
        shared.draw_us.store(d0.elapsed().as_micros() as u32, Ordering::Relaxed);
        *shared.picture.lock().unwrap() = Some(rgb);
        shared.pictures.fetch_add(1, Ordering::Relaxed);
    }
}
