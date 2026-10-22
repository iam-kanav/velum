//! C interface to Phonon (https://github.com/gradium-ai/xn-ptts) for Velum's experimental
//! on-device voice. lib/features/tts/data/services/phonon_bindings.dart calls it.
//!
//! Adapted from xn-ptts' own `ptts-ffi` crate (MIT OR Apache-2.0). That crate drives Core ML on
//! Apple platforms; this one runs `ptts::synth::Synth` on the CPU everywhere, with the same
//! checkpoint folder the Android app downloads.
//!
//! `phonon_new` loads a checkpoint folder (the slow call). `phonon_synth` then turns text into
//! one buffer of 24 kHz mono float samples. Calls block: make them from one thread at a time,
//! except `phonon_cancel`, which any thread may call with the handle's `phonon_cancel_token`
//! while `phonon_synth` runs.

use ptts::checkpoint::read_config;
use ptts::preprocess::Normalize;
use ptts::synth::{DeviceKind, Quant, SpeechOptions, Synth, SynthBuilder};
use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

/// Weight files tried in order, with the format each loads as.
const WEIGHTS: [(&str, Quant); 2] =
    [("model.q8.gguf", Quant::Q80), ("model.safetensors", Quant::F32)];

pub struct PhononHandle {
    synth: Synth,
    voice: Option<String>,
    normalize: Normalize,
    /// The voice names as NUL-separated bytes, so `phonon_voices` can hand out a borrowed pointer.
    voice_blob: Vec<u8>,
    /// Its own allocation, so `phonon_cancel` on another thread never touches the handle that
    /// `phonon_synth` is using.
    cancel: *mut AtomicBool,
    last_error: Option<CString>,
}

thread_local! {
    /// The last `phonon_new` failure on this thread.
    static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

fn c_string(e: &str) -> CString {
    CString::new(e.replace('\0', " ")).expect("NULs were replaced")
}

fn str_arg(p: *const c_char) -> String {
    unsafe { CStr::from_ptr(p) }.to_string_lossy().to_string()
}

/// Run `f`, turning a panic into an error: unwinding across the C interface aborts the app.
fn guarded<T>(f: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|p| {
        let msg = p
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| p.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "unknown".into());
        Err(format!("internal error: {msg}"))
    })
}

fn open(dir: &Path, lang: &str) -> Result<PhononHandle, String> {
    let normalize = lang.parse::<Normalize>().map_err(|e| e.to_string())?;
    let cfg = read_config(&dir.join("config.json")).map_err(|e| e.to_string())?;
    let (weights, quant) = WEIGHTS
        .iter()
        .map(|&(name, q)| (dir.join(name), q))
        .find(|(p, _)| p.is_file())
        .ok_or(format!("no weights in {}", dir.display()))?;
    // Normalization is applied in `synth`, so the language could change without a reload.
    let mut builder = SynthBuilder::new(cfg, weights, Normalize::OFF)
        .tokenizer_file(dir.join("tokenizer.json"))
        .device(DeviceKind::Cpu)
        .quant(quant);
    for (name, path) in ptts::loader::checkpoint_voices(dir) {
        builder = builder.add_voice(name, path);
    }
    let synth = builder.build().map_err(|e| e.to_string())?;
    let mut voices = synth.voices();
    voices.sort();
    let mut voice_blob = Vec::new();
    for v in &voices {
        voice_blob.extend_from_slice(v.as_bytes());
        voice_blob.push(0);
    }
    voice_blob.push(0);
    Ok(PhononHandle {
        voice: synth.default_voice(),
        synth,
        normalize,
        voice_blob,
        cancel: Box::into_raw(Box::new(AtomicBool::new(false))),
        last_error: None,
    })
}

/// Load the checkpoint folder `dir`, normalizing text as `lang` (`en`, `fr`, `de`, `es`, `pt` or
/// `none`). `threads` > 0 caps the worker threads; it only takes effect on the first call, before
/// the thread pool starts. Null on failure; then `phonon_last_error(NULL)`, on the same thread,
/// says why.
///
/// # Safety
/// `dir` and `lang` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_new(
    dir: *const c_char,
    lang: *const c_char,
    threads: u32,
) -> *mut PhononHandle {
    if threads > 0 && std::env::var_os("RAYON_NUM_THREADS").is_none() {
        // Phones mix fast and slow cores, so one thread per core is too many.
        unsafe { std::env::set_var("RAYON_NUM_THREADS", threads.to_string()) };
    }
    let (dir, lang) = (str_arg(dir), str_arg(lang));
    match guarded(|| open(Path::new(&dir), &lang)) {
        Ok(h) => Box::into_raw(Box::new(h)),
        Err(e) => {
            LAST_ERROR.with(|l| *l.borrow_mut() = Some(c_string(&e)));
            std::ptr::null_mut()
        }
    }
}

/// The audio's sample rate (24 kHz for the Phonon models).
///
/// # Safety
/// `h` must come from `phonon_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_sample_rate(h: *const PhononHandle) -> u32 {
    unsafe { (*h).synth.sample_rate() }
}

/// Voice names, sorted, as one NUL-separated block ending in a second NUL. Borrowed.
///
/// # Safety
/// `h` must come from `phonon_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_voices(h: *const PhononHandle) -> *const c_char {
    unsafe { (*h).voice_blob.as_ptr() as *const c_char }
}

/// Speak in one of `phonon_voices` from now on. False if there is no such voice.
///
/// # Safety
/// `h` must come from `phonon_new`; `name` must be NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_set_voice(h: *mut PhononHandle, name: *const c_char) -> bool {
    let h = unsafe { &mut *h };
    let name = str_arg(name);
    if !h.synth.voices().contains(&name) {
        h.last_error = Some(c_string(&format!("no voice named {name:?}")));
        return false;
    }
    h.voice = Some(name);
    true
}

/// Turn `text` into speech: a buffer of mono float samples in [-1, 1], its length in `*len`.
/// Free it with `phonon_free_pcm`. Null with `*len` 0 when cancelled or on failure; after a
/// failure `phonon_last_error(h)` says why, and after a cancel it is null.
///
/// # Safety
/// `h` must come from `phonon_new`; `text` must be NUL-terminated UTF-8; `len` must be writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_synth(
    h: *mut PhononHandle,
    text: *const c_char,
    len: *mut usize,
) -> *mut f32 {
    let h = unsafe { &mut *h };
    unsafe { *len = 0 };
    h.last_error = None;
    let cancel = unsafe { &*h.cancel };
    cancel.store(false, Ordering::SeqCst);
    let text = str_arg(text);
    let result = guarded(|| {
        let opts = SpeechOptions { voice: h.voice.clone(), ..Default::default() };
        let text = h.normalize.apply(&text);
        let stream = h.synth.stream_with(&text, &opts).map_err(|e| e.to_string())?;
        let mut pcm = Vec::new();
        // Dropping the stream on an early return stops generation.
        for chunk in stream {
            if cancel.load(Ordering::SeqCst) {
                return Ok(None);
            }
            pcm.extend_from_slice(&chunk.map_err(|e| e.to_string())?);
        }
        Ok(Some(pcm))
    });
    match result {
        Ok(Some(pcm)) => {
            let mut pcm = pcm.into_boxed_slice();
            unsafe { *len = pcm.len() };
            let ptr = pcm.as_mut_ptr();
            std::mem::forget(pcm);
            ptr
        }
        Ok(None) => std::ptr::null_mut(),
        Err(e) => {
            h.last_error = Some(c_string(&e));
            std::ptr::null_mut()
        }
    }
}

/// Free a buffer from `phonon_synth`.
///
/// # Safety
/// `pcm` and `len` must come from one `phonon_synth` call, and `pcm` must not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_free_pcm(pcm: *mut f32, len: usize) {
    if !pcm.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(pcm, len)) });
    }
}

/// The token `phonon_cancel` takes for `h`, valid until `phonon_free(h)`.
///
/// # Safety
/// `h` must come from `phonon_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_cancel_token(h: *const PhononHandle) -> *const AtomicBool {
    unsafe { (*h).cancel }
}

/// Make the `phonon_synth` running on the handle `token` belongs to return early, after the
/// frame it is decoding. Safe to call from any thread.
///
/// # Safety
/// `token` must come from `phonon_cancel_token` of a handle not yet freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_cancel(token: *const AtomicBool) {
    unsafe { (*token).store(true, Ordering::SeqCst) };
}

/// The last error on `h`, or, when `h` is null, the last `phonon_new` failure on this thread.
/// Null if there was none. Borrowed until the next call.
///
/// # Safety
/// `h` must be null or come from `phonon_new`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_last_error(h: *const PhononHandle) -> *const c_char {
    if h.is_null() {
        return LAST_ERROR.with(|l| l.borrow().as_ref().map_or(std::ptr::null(), |c| c.as_ptr()));
    }
    unsafe { (*h).last_error.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()) }
}

/// # Safety
/// `h` must come from `phonon_new` and must not be used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn phonon_free(h: *mut PhononHandle) {
    if !h.is_null() {
        let h = unsafe { Box::from_raw(h) };
        drop(unsafe { Box::from_raw(h.cancel) });
    }
}
