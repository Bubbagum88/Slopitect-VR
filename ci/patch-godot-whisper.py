#!/usr/bin/env python3
"""Fix godot-whisper's build-time patch of whisper.cpp's sgemm.cpp, for the Quest 1.

godot-whisper's SConstruct moves both Arm half-float load() helpers in
ggml/src/ggml-cpu/llamafile/sgemm.cpp under __ARM_FEATURE_FP16_VECTOR_ARITHMETIC
(for arm32). The Quest 1 build is plain armv8.0 without that feature, but
sgemm.cpp's plain-NEON path still uses load<float32x4_t>(const ggml_fp16_t *),
so the library came out with that symbol undefined and the headset refused
to load it:

  dlopen failed: cannot locate symbol
  "_ZN12_GLOBAL__N_14loadI13__Float32x4_ttEET_PKT0_"

Only the float16x8_t helper needs FP16 vector arithmetic; the float32x4_t one
converts with plain NEON. This keeps that one for every Arm build and guards
the other, and leaves no FIXME line, so SConstruct's own patch no longer
applies. Run it from the godot-whisper checkout before scons.
"""
import sys

PATH = "thirdparty/whisper.cpp/ggml/src/ggml-cpu/llamafile/sgemm.cpp"

OLD = """#if !defined(_MSC_VER)
// FIXME: this should check for __ARM_FEATURE_FP16_VECTOR_ARITHMETIC
template <> inline float16x8_t load(const ggml_fp16_t *p) {
    return vld1q_f16((const float16_t *)p);
}
template <> inline float32x4_t load(const ggml_fp16_t *p) {
    return vcvt_f32_f16(vld1_f16((const float16_t *)p));
}
#endif // _MSC_VER
"""

NEW = """#if !defined(_MSC_VER)
template <> inline float32x4_t load(const ggml_fp16_t *p) {
    return vcvt_f32_f16(vld1_f16((const float16_t *)p));
}
#endif // !_MSC_VER
#if defined(__ARM_FEATURE_FP16_VECTOR_ARITHMETIC) && !defined(_MSC_VER)
template <> inline float16x8_t load(const ggml_fp16_t *p) {
    return vld1q_f16((const float16_t *)p);
}
#endif // __ARM_FEATURE_FP16_VECTOR_ARITHMETIC
"""

path = sys.argv[1] if len(sys.argv) > 1 else PATH
with open(path) as f:
    text = f.read()
if text.count(OLD) != 1:
    sys.exit(f"::error::{path} doesn't have the Arm load() block this fix expects; check it against the new whisper.cpp")
with open(path, "w") as f:
    f.write(text.replace(OLD, NEW))
print(f"patched {path}: load<float32x4_t>(const ggml_fp16_t *) kept for every Arm build")
