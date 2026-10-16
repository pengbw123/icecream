"""Small desktop front end for the DX7 differential-validation CLI.

The generated audio is the *original Dexed/msfa FM core at constant operator
gain*. It is a useful kernel test, not a full DX7 ROM-voice render or RTL sim.
"""

from __future__ import annotations

import json
import math
import sys
import tempfile
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS_DIR))

from cli.fm_dx7_diff import (  # noqa: E402
    _find_dexed_root, _read_wav, _write_wav16, compare_raw_i32,
    compare_wavs, render_msfa_core,
)

try:
    import winsound
except ImportError:  # pragma: no cover - Windows is the target platform
    winsound = None


def waveform_columns(samples: np.ndarray, columns: int) -> tuple[np.ndarray, np.ndarray]:
    """Min/max envelope used by the Canvas; zero-padding is never displayed."""
    if columns <= 0 or samples.size == 0:
        return np.array([]), np.array([])
    edges = np.linspace(0, samples.size, min(columns, samples.size) + 1,
                        dtype=np.int64)
    low = np.array([np.min(samples[edges[i]:edges[i + 1]])
                    for i in range(len(edges) - 1)])
    high = np.array([np.max(samples[edges[i]:edges[i + 1]])
                     for i in range(len(edges) - 1)])
    return low, high


class FmValidationApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        root.title("DX7 / FPGA 音色差分验证")
        root.geometry("1040x690")
        root.minsize(900, 610)
        self.output_dir = Path(tempfile.gettempdir()) / "fpga_fm_validation"
        self.reference_wav: Path | None = None
        self.preview_wav = self.output_dir / "reference_preview.wav"
        self.busy = False

        self.dexed_root = tk.StringVar(value=str(
            Path(r"D:\a_files\dexed-master\dexed-master")))
        self.algorithm = tk.IntVar(value=32)
        self.feedback = tk.IntVar(value=0)
        self.seconds = tk.DoubleVar(value=1.0)
        self.sample_rate = tk.DoubleVar(value=48828.125)
        self.preview_gain = tk.DoubleVar(value=2.0)
        self.output_path = tk.StringVar(value=str(self.output_dir))
        self.preset = tk.StringVar(value="纯正弦：单算子")
        self.frequency = [tk.StringVar(value="440" if i == 0 else "0")
                          for i in range(6)]
        self.gain = [tk.StringVar(value="0.25" if i == 0 else "0")
                     for i in range(6)]
        self.reference_capture = tk.StringVar()
        self.fpga_capture = tk.StringVar()
        self.reference_raw = tk.StringVar()
        self.fpga_raw = tk.StringVar()
        self.reference_offset = tk.IntVar(value=0)
        self.fpga_offset = tk.IntVar(value=0)
        self.hold_ms = tk.IntVar(value=1000)
        self.status = tk.StringVar(value="准备就绪。先生成一个 Dexed 核心参考音频并试听。")

        outer = ttk.Frame(root, padding=10)
        outer.pack(fill="both", expand=True)
        ttk.Label(outer, text="DX7 差分实验台", font=("Microsoft YaHei UI", 16, "bold")
                  ).pack(anchor="w")
        ttk.Label(outer, text=(
            "当前参考音频仅覆盖原版 Dexed/msfa 的 FM 核心（算子增益固定）；"
            "不是完整音色、不是 FPGA RTL 仿真，也尚未证明逐位一致。"),
            foreground="#a54b00", wraplength=970).pack(anchor="w", pady=(2, 8))
        tabs = ttk.Notebook(outer)
        tabs.pack(fill="both", expand=True)
        self.reference_tab = ttk.Frame(tabs, padding=8)
        self.compare_tab = ttk.Frame(tabs, padding=8)
        tabs.add(self.reference_tab, text="① 生成并试听参考音频")
        tabs.add(self.compare_tab, text="② 导入 FPGA 数字音频比较")
        self._build_reference_tab()
        self._build_compare_tab()
        ttk.Label(outer, textvariable=self.status, foreground="#174d82",
                  wraplength=980).pack(anchor="w", pady=(7, 0))

    @staticmethod
    def _path_row(parent: ttk.Frame, row: int, label: str,
                  value: tk.StringVar, browse) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=3)
        ttk.Entry(parent, textvariable=value).grid(row=row, column=1,
                                                     sticky="ew", pady=3)
        ttk.Button(parent, text="浏览…", command=browse, width=9).grid(
            row=row, column=2, padx=(6, 0), pady=3)
        parent.columnconfigure(1, weight=1)

    def _build_reference_tab(self) -> None:
        tab = self.reference_tab
        source = ttk.LabelFrame(tab, text="Dexed 原版核心与输出", padding=7)
        source.pack(fill="x")
        self._path_row(source, 0, "Dexed 源码", self.dexed_root,
                       lambda: self._choose_directory(self.dexed_root))
        self._path_row(source, 1, "输出目录", self.output_path,
                       lambda: self._choose_directory(self.output_path))

        controls = ttk.Frame(tab)
        controls.pack(fill="x", pady=(8, 3))
        for label, var, width in (("算法 1–32", self.algorithm, 5),
                                  ("反馈 0–7", self.feedback, 5),
                                  ("采样率 Hz", self.sample_rate, 10),
                                  ("时长 s", self.seconds, 6),
                                  ("试听倍率", self.preview_gain, 6)):
            cell = ttk.Frame(controls)
            cell.pack(side="left", padx=(0, 16))
            ttk.Label(cell, text=label).pack(anchor="w")
            ttk.Entry(cell, textvariable=var, width=width).pack(anchor="w")

        preset_row = ttk.Frame(tab)
        preset_row.pack(fill="x", pady=(3, 5))
        ttk.Label(preset_row, text="快速配置").pack(side="left", padx=(0, 8))
        preset_box = ttk.Combobox(
            preset_row, textvariable=self.preset, state="readonly", width=23,
            values=("纯正弦：单算子", "简单 FM：两算子", "反馈：单算子"))
        preset_box.pack(side="left")
        preset_box.bind("<<ComboboxSelected>>", lambda _event: self._apply_preset())
        ttk.Label(preset_row, text="算子顺序与 DX7 .syx 一致：OP6 → OP1",
                  foreground="#555").pack(side="right")

        operator_frame = ttk.LabelFrame(tab, text="六算子静态测试参数", padding=5)
        operator_frame.pack(fill="x")
        for index in range(6):
            cell = ttk.Frame(operator_frame)
            cell.grid(row=index // 3, column=index % 3, padx=12, pady=4, sticky="w")
            ttk.Label(cell, text=f"OP{6 - index}").pack(side="left")
            ttk.Label(cell, text="Hz").pack(side="left", padx=(8, 2))
            ttk.Entry(cell, textvariable=self.frequency[index], width=9).pack(side="left")
            ttk.Label(cell, text="增益").pack(side="left", padx=(8, 2))
            ttk.Entry(cell, textvariable=self.gain[index], width=7).pack(side="left")

        actions = ttk.Frame(tab)
        actions.pack(fill="x", pady=8)
        self.render_button = ttk.Button(actions, text="生成参考音频",
                                        command=self._render_reference)
        self.render_button.pack(side="left")
        ttk.Button(actions, text="▶ 试听", command=self._play_reference).pack(
            side="left", padx=8)
        ttk.Button(actions, text="■ 停止", command=self._stop_audio).pack(side="left")
        ttk.Label(actions, text="试听倍率仅改变播放文件，不改原始 .i32le 数据",
                  foreground="#666").pack(side="right")

        self.reference_detail = tk.StringVar(value="尚未生成。")
        ttk.Label(tab, textvariable=self.reference_detail, wraplength=960).pack(
            anchor="w", pady=(0, 5))
        self.reference_canvas = tk.Canvas(tab, height=175, bg="#101522",
                                           highlightthickness=0)
        self.reference_canvas.pack(fill="both", expand=True)
        self.reference_canvas.bind("<Configure>", lambda _e: self._draw_reference())

    def _build_compare_tab(self) -> None:
        tab = self.compare_tab
        wav = ttk.LabelFrame(tab, text="先做可听差异比较（WAV；会对齐并拟合整体增益，不能证明 bit 一致）",
                             padding=7)
        wav.pack(fill="x")
        self._path_row(wav, 0, "Dexed WAV", self.reference_capture,
                       lambda: self._choose_file(self.reference_capture, "WAV 音频", "*.wav"))
        self._path_row(wav, 1, "FPGA WAV", self.fpga_capture,
                       lambda: self._choose_file(self.fpga_capture, "WAV 音频", "*.wav"))
        row = ttk.Frame(wav)
        row.grid(row=2, column=0, columnspan=3, sticky="w", pady=(6, 0))
        ttk.Label(row, text="按键时长 ms").pack(side="left")
        ttk.Entry(row, textvariable=self.hold_ms, width=8).pack(side="left", padx=5)
        ttk.Button(row, text="比较音色 / 包络", command=self._compare_wav).pack(
            side="left", padx=7)
        ttk.Button(row, text="▶ 听 Dexed", command=lambda: self._play_path(
            Path(self.reference_capture.get()))).pack(side="left", padx=4)
        ttk.Button(row, text="▶ 听 FPGA", command=lambda: self._play_path(
            Path(self.fpga_capture.get()))).pack(side="left", padx=4)
        ttk.Button(row, text="■", width=3, command=self._stop_audio).pack(side="left")

        self.wav_result = tk.StringVar(value="选择同音色、同音高、同力度的两份数字 WAV。")
        ttk.Label(tab, textvariable=self.wav_result, wraplength=950,
                  justify="left").pack(anchor="w", pady=8)
        self.compare_canvas = tk.Canvas(tab, height=115, bg="#101522",
                                         highlightthickness=0)
        self.compare_canvas.pack(fill="x", pady=(0, 9))

        raw = ttk.LabelFrame(tab, text="严格逐样点比较（i32le；无归一化、重采样或自动对齐）",
                             padding=7)
        raw.pack(fill="x")
        self._path_row(raw, 0, "Dexed 原始流", self.reference_raw,
                       lambda: self._choose_file(self.reference_raw, "32位原始音频", "*.i32le"))
        self._path_row(raw, 1, "FPGA 原始流", self.fpga_raw,
                       lambda: self._choose_file(self.fpga_raw, "32位原始音频", "*.i32le"))
        offsets = ttk.Frame(raw)
        offsets.grid(row=2, column=0, columnspan=3, sticky="w", pady=(5, 0))
        ttk.Label(offsets, text="Dexed 起点").pack(side="left")
        ttk.Entry(offsets, textvariable=self.reference_offset, width=8).pack(
            side="left", padx=5)
        ttk.Label(offsets, text="FPGA 起点").pack(side="left")
        ttk.Entry(offsets, textvariable=self.fpga_offset, width=8).pack(
            side="left", padx=5)
        ttk.Button(offsets, text="严格比对整数样点", command=self._compare_raw).pack(
            side="left", padx=8)
        self.raw_result = tk.StringVar(value="需板端输出原始数字样点；目前还没有这种采集文件。")
        ttk.Label(tab, textvariable=self.raw_result, wraplength=950,
                  justify="left").pack(anchor="w", pady=7)

    def _choose_directory(self, target: tk.StringVar) -> None:
        path = filedialog.askdirectory(initialdir=target.get() or str(TOOLS_DIR))
        if path:
            target.set(path)

    def _choose_file(self, target: tk.StringVar, description: str,
                     pattern: str) -> None:
        path = filedialog.askopenfilename(
            filetypes=[(description, pattern), ("所有文件", "*.*")])
        if path:
            target.set(path)

    def _apply_preset(self) -> None:
        preset = self.preset.get()
        for item in self.frequency:
            item.set("0")
        for item in self.gain:
            item.set("0")
        self.algorithm.set(5 if preset == "简单 FM：两算子" else 32)
        self.feedback.set(6 if preset == "反馈：单算子" else 0)
        self.frequency[0].set("440")
        self.gain[0].set("0.25")
        if preset == "简单 FM：两算子":
            self.frequency[1].set("440")
            self.gain[1].set("0.4")

    def _run_task(self, description: str, task, on_success) -> None:
        if self.busy:
            return
        self.busy = True
        self.status.set(description)

        def worker() -> None:
            try:
                value = task()
            except Exception as exc:
                self.root.after(0, lambda error=str(exc): self._task_failed(error))
            else:
                self.root.after(0, lambda: self._task_done(value, on_success))

        threading.Thread(target=worker, daemon=True).start()

    def _task_failed(self, message: str) -> None:
        self.busy = False
        self.status.set(f"失败：{message}")
        messagebox.showerror("操作失败", message)

    def _task_done(self, value, on_success) -> None:
        self.busy = False
        on_success(value)

    def _render_reference(self) -> None:
        try:
            root = _find_dexed_root(Path(self.dexed_root.get()))
            algorithm = self.algorithm.get()
            feedback = self.feedback.get()
            rate = self.sample_rate.get()
            seconds = self.seconds.get()
            frequencies = [float(item.get()) for item in self.frequency]
            gains = [float(item.get()) for item in self.gain]
            folder = Path(self.output_path.get())
            if not (1 <= algorithm <= 32 and 0 <= feedback <= 7 and
                    8000 <= rate <= 192000 and 0 < seconds <= 20 and
                    all(math.isfinite(x) and 0 <= x < rate for x in frequencies) and
                    all(math.isfinite(x) and 0 <= x <= 4 for x in gains)):
                raise ValueError("算法/反馈/采样率/时长/算子参数超出范围")
        except (ValueError, FileNotFoundError, tk.TclError) as exc:
            messagebox.showerror("参数错误", str(exc))
            return

        def work():
            internal = render_msfa_core(root, round(rate * seconds), rate,
                                        algorithm, feedback, frequencies, gains)
            folder.mkdir(parents=True, exist_ok=True)
            output = folder / "dexed_core_reference.wav"
            internal.astype("<i4").tofile(output.with_suffix(".i32le"))
            _write_wav16(output, internal.astype(np.float64) / (1 << 24),
                         round(rate))
            metadata = {"scope": "static-gain original Dexed/msfa FM core",
                        "algorithm": algorithm, "feedback": feedback,
                        "sample_rate_exact": rate, "frequencies": frequencies,
                        "gains": gains, "samples": len(internal)}
            output.with_suffix(".json").write_text(
                json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
            return output

        self._run_task("正在编译 Dexed 原版 FM 核心并生成参考音频…", work,
                       self._render_done)

    def _render_done(self, output: Path) -> None:
        self.reference_wav = output
        self.reference_capture.set(str(output))
        self.reference_raw.set(str(output.with_suffix(".i32le")))
        self.reference_detail.set(
            f"已生成：{output.name}（试听），{output.with_suffix('.i32le').name} "
            "（32位数字样点），以及参数 JSON。")
        self.status.set(f"参考音频已保存到 {output.parent}；可以点“▶ 试听”。")
        self._draw_reference()

    def _play_path(self, path: Path) -> None:
        if winsound is None:
            messagebox.showerror("无法播放", "该快捷播放功能需要 Windows 的 winsound。")
            return
        if not path.is_file():
            messagebox.showerror("文件不存在", f"未找到音频：{path}")
            return
        try:
            winsound.PlaySound(str(path), winsound.SND_FILENAME | winsound.SND_ASYNC)
            self.status.set(f"正在播放：{path.name}")
        except RuntimeError as exc:
            messagebox.showerror("播放失败", str(exc))

    def _play_reference(self) -> None:
        if self.reference_wav is None:
            messagebox.showinfo("先生成", "请先点“生成参考音频”。")
            return
        try:
            rate, values = _read_wav(self.reference_wav)
            multiplier = self.preview_gain.get()
            if not (0 < multiplier <= 16):
                raise ValueError("试听倍率应大于0且不超过16")
            self.preview_wav.parent.mkdir(parents=True, exist_ok=True)
            _write_wav16(self.preview_wav, values * multiplier, rate)
        except (ValueError, tk.TclError) as exc:
            messagebox.showerror("无法试听", str(exc))
            return
        self._play_path(self.preview_wav)

    @staticmethod
    def _stop_audio() -> None:
        if winsound is not None:
            winsound.PlaySound(None, winsound.SND_PURGE)

    @staticmethod
    def _paint_wave(canvas: tk.Canvas, waves: list[tuple[np.ndarray, str]]) -> None:
        canvas.delete("all")
        width, height = max(canvas.winfo_width(), 300), max(canvas.winfo_height(), 60)
        mid = height // 2
        canvas.create_line(0, mid, width, mid, fill="#344157")
        for samples, color in waves:
            if samples.size == 0:
                continue
            low, high = waveform_columns(samples, width - 8)
            ceiling = max(0.05, float(np.max(np.abs(samples))))
            scale = (height * 0.43) / ceiling
            for index, (minimum, maximum) in enumerate(zip(low, high)):
                canvas.create_line(index + 4, mid - maximum * scale,
                                   index + 4, mid - minimum * scale, fill=color)

    def _draw_reference(self) -> None:
        if self.reference_wav is None or not self.reference_wav.is_file():
            self._paint_wave(self.reference_canvas, [])
            return
        _rate, samples = _read_wav(self.reference_wav)
        self._paint_wave(self.reference_canvas, [(samples, "#44dccf")])

    def _compare_wav(self) -> None:
        try:
            reference = Path(self.reference_capture.get())
            fpga = Path(self.fpga_capture.get())
            hold = self.hold_ms.get()
            if hold <= 0:
                raise ValueError("按键时长必须大于0")
        except (ValueError, tk.TclError) as exc:
            messagebox.showerror("参数错误", str(exc))
            return
        self._run_task("正在对比音量、包络与频谱…",
                       lambda: compare_wavs(reference, fpga, hold),
                       self._wav_done)

    def _wav_done(self, report: dict) -> None:
        metrics = report["regions"].get("whole", {})
        if metrics:
            self.wav_result.set(
                f"整体：响度差 {metrics['fpga_vs_reference_db']:+.2f} dB；"
                f"去掉整体音量差后的波形相关 {metrics['gain_aligned_correlation']:.4f}；"
                f"残差 {metrics['gain_aligned_residual_rms_percent']:.2f}%；"
                f"频谱误差中位数 {metrics['median_80_8000hz_spectral_error_db']:.2f} dB。\n"
                f"重采样：{'是（不能逐位判断）' if report['resampled_for_diagnostics'] else '否'}。"
                "这是一种听感/频谱诊断，不是 bit 级通过。")
        else:
            self.wav_result.set("未找到足够长的非静音对比片段。")
        try:
            _rate_a, a = _read_wav(Path(report["reference"]))
            _rate_b, b = _read_wav(Path(report["fpga"]))
            self._paint_wave(self.compare_canvas,
                             [(a, "#43d8cc"), (b, "#f5ae4b")])
        except Exception:
            self._paint_wave(self.compare_canvas, [])
        self.status.set("WAV 对比完成：青色为 Dexed，橙色为 FPGA。")

    def _compare_raw(self) -> None:
        try:
            reference = Path(self.reference_raw.get())
            fpga = Path(self.fpga_raw.get())
            offsets = (self.reference_offset.get(), self.fpga_offset.get())
        except tk.TclError as exc:
            messagebox.showerror("参数错误", str(exc))
            return
        self._run_task("正在严格逐样点比较…",
                       lambda: compare_raw_i32(reference, fpga, *offsets),
                       self._raw_done)

    def _raw_done(self, report: dict) -> None:
        if report["exact_match"]:
            self.raw_result.set(
                f"完全一致：共 {report['compared_samples']:,} 个 32 位样点，文件长度也一致。")
        else:
            self.raw_result.set(
                f"尚不一致：{report['unequal_samples']:,} / "
                f"{report['compared_samples']:,} 个样点不同；"
                f"第一个差异在对齐后样点 {report['first_mismatch_index']}；"
                f"最大误差 {report['max_abs_error_lsb']:,} LSB，"
                f"均方根误差 {report['rms_error_lsb']:.2f} LSB；"
                f"长度相同：{'是' if report['lengths_match'] else '否'}。")
        self.status.set("严格数字样点对比完成；不会自动掩盖幅度或相位误差。")


def main() -> None:
    root = tk.Tk()
    FmValidationApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
