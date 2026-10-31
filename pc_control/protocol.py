"""JDY-23 / Gowin additive-UART 协议 (PC 侧, 标准库实现, 无硬件/GUI 依赖).

数据帧格式 (与 fpga_project3/src/synth_uart_control.v 一致):
    A5 5A CMD DATA0 DATA1 ... DATA7 XOR
    XOR = CMD ^ DATA0 ^ ... ^ DATA7, 共 12 字节, 多字节字段小端。

命令:
    0x10 attack  : DATA0..3 samples(u32 LE), DATA4..7 phase_inc(u32 LE)
    0x11 decay   : 同上
    0x12 sustain : DATA0..1 sustain_q16(u16 LE)
    0x13 release : 同 0x10
    0x40 harmonic amplitude : DATA0 anchor, DATA1 harmonic, DATA2..3 amp_q15(u16 LE)
    0x41 harmonic decay     : DATA0 anchor, DATA1 harmonic, DATA2..4 alpha_q24(u24 LE)
    0x42 end-of-update marker (完成标记; 不是硬件 ACK, 也不是原子提交)
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Any

__all__ = [
    "SAMPLE_RATE",
    "ANCHOR_NAMES",
    "ANCHOR_MIDI_NOTES",
    "HARMONIC_COUNT",
    "ANCHOR_COUNT",
    "PACKET_LENGTH",
    "CMD_ATTACK",
    "CMD_DECAY",
    "CMD_SUSTAIN",
    "CMD_RELEASE",
    "CMD_HARMONIC_AMPLITUDE",
    "CMD_HARMONIC_DECAY",
    "CMD_COMMIT",
    "ProtocolError",
    "make_packet",
    "timing_packet",
    "sustain_packet",
    "amplitude_packet",
    "decay_ms_to_q24",
    "harmonic_decay_packet",
    "commit_packet",
    "validate_preset",
    "preset_packets",
    "load_preset",
    "parse_hex",
    "encode_text",
]

SAMPLE_RATE = 48_828.125
ANCHOR_NAMES = ("C2", "C3", "C4", "C6")
ANCHOR_MIDI_NOTES = (36, 48, 60, 84)
ANCHOR_COUNT = 4
HARMONIC_COUNT = 16
PACKET_LENGTH = 12

CMD_ATTACK = 0x10
CMD_DECAY = 0x11
CMD_SUSTAIN = 0x12
CMD_RELEASE = 0x13
CMD_HARMONIC_AMPLITUDE = 0x40
CMD_HARMONIC_DECAY = 0x41
CMD_COMMIT = 0x42

_HEX_DIGITS = frozenset("0123456789abcdefABCDEF")


class ProtocolError(ValueError):
    """协议参数非法 (协议层数值/结构校验失败)."""


# ---------------------------------------------------------------------------
# 校验辅助
# ---------------------------------------------------------------------------


def _is_int(value: Any) -> bool:
    """真正的整数: 排除 bool (bool 是 int 的子类) 与非整数浮点."""
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value: Any) -> bool:
    """真的数值: 排除 bool / 非数值类型."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _require_command(command: Any) -> int:
    if not _is_int(command):
        raise ProtocolError(f"command 必须是整数, 收到 {type(command).__name__}: {command!r}")
    if not 0 <= command <= 0xFF:
        raise ProtocolError(f"command 必须在 0..255 之间, 收到 {command}")
    return command


def _require_finite(value: Any, name: str) -> float:
    if not _is_number(value):
        raise ProtocolError(f"{name} 必须是数值 (不是 bool/字符串/None), 收到 {type(value).__name__}: {value!r}")
    try:
        number = float(value)
    except OverflowError as error:
        # 超大 Python 整数 (如 10**400) 转 float 会溢出, 统一收敛为 ProtocolError
        raise ProtocolError(f"{name} 数值过大, 无法表示为有限浮点数: {value!r}") from error
    if math.isnan(number) or math.isinf(number):
        raise ProtocolError(f"{name} 必须是有限数值, 收到 {number!r}")
    return number


def _require_integer_like(value: Any, name: str, low: int, high: int) -> int:
    """要求有限且为整数值的数值 (3.0 合法, 3.5 非法), 然后做范围校验."""
    number = _require_finite(value, name)
    if number != math.floor(number):
        raise ProtocolError(f"{name} 必须是整数, 收到 {value!r}")
    integer = int(number)
    if not low <= integer <= high:
        raise ProtocolError(f"{name} 必须在 {low}..{high} 之间, 收到 {integer}")
    return integer


def _require_range(value: Any, name: str, low: float, high: float) -> float:
    number = _require_finite(value, name)
    if not low <= number <= high:
        raise ProtocolError(f"{name} 必须在 {low}..{high} 之间, 收到 {number!r}")
    return number


def _require_sequence(value: Any, name: str, length: int) -> list:
    if isinstance(value, (str, bytes, bytearray)) or not isinstance(value, (list, tuple)):
        raise ProtocolError(f"{name} 必须是长度为 {length} 的列表, 收到 {type(value).__name__}")
    if len(value) != length:
        raise ProtocolError(f"{name} 必须恰好包含 {length} 个元素, 实际为 {len(value)} 个")
    return list(value)


# ---------------------------------------------------------------------------
# 帧构造
# ---------------------------------------------------------------------------


def make_packet(command: int, payload: bytes = bytes(8)) -> bytes:
    """组装 12 字节帧: A5 5A CMD DATA0..7 XOR(CMD,DATA0..7)."""
    command = _require_command(command)
    if isinstance(payload, (bytearray, memoryview)):
        payload = bytes(payload)
    if not isinstance(payload, bytes):
        raise ProtocolError(f"payload 必须是 bytes, 收到 {type(payload).__name__}")
    if len(payload) != 8:
        raise ProtocolError(f"payload 必须恰好 8 字节, 实际为 {len(payload)} 字节")
    checksum = command
    for value in payload:
        checksum ^= value
    return bytes((0xA5, 0x5A, command)) + payload + bytes((checksum,))


def timing_packet(command: int, milliseconds: float) -> bytes:
    """ADSR 时间包 (0x10/0x11/0x13): samples+phase_increment 两个 u32 LE."""
    command = _require_command(command)
    milliseconds = _require_range(milliseconds, "ADSR 时间(ms)", 0.1, 60_000.0)
    samples = max(1, round(milliseconds * SAMPLE_RATE / 1000.0))
    phase_increment = 0xFFFFFFFF if samples <= 1 else round(0xFFFFFFFF / (samples - 1))
    return make_packet(command, struct.pack("<II", samples, min(0xFFFFFFFF, phase_increment)))


def sustain_packet(value: float) -> bytes:
    """延音包 (0x12): 0..1 映射到 Q16, 存于 DATA0..1 (u16 LE)."""
    value = _require_range(value, "sustain", 0.0, 1.0)
    return make_packet(CMD_SUSTAIN, struct.pack("<Q", round(value * 65535.0)))


def amplitude_packet(anchor: int, harmonic: int, amplitude: float) -> bytes:
    """谐波幅度包 (0x40): anchor/harmonic 索引 + Q15 幅度."""
    anchor = _require_integer_like(anchor, "anchor 索引", 0, ANCHOR_COUNT - 1)
    harmonic = _require_integer_like(harmonic, "harmonic 索引", 0, HARMONIC_COUNT - 1)
    amplitude = _require_range(amplitude, "amplitude", 0.0, 1.0)
    payload = bytearray(8)
    payload[0] = anchor
    payload[1] = harmonic
    struct.pack_into("<H", payload, 2, round(amplitude * 32767.0))
    return make_packet(CMD_HARMONIC_AMPLITUDE, bytes(payload))


def decay_ms_to_q24(decay_ms: float) -> int:
    """衰减时间(ms) -> Q24 alpha 系数, 0 表示不衰减."""
    decay_ms = _require_range(decay_ms, "谐波衰减(ms)", 0.0, 120_000.0)
    if decay_ms == 0:
        return 0
    tau_samples = decay_ms * SAMPLE_RATE / 1000.0
    alpha = 1.0 - math.exp(-1.0 / tau_samples)
    return max(1, min((1 << 24) - 1, round(alpha * ((1 << 24) - 1))))


def harmonic_decay_packet(anchor: int, harmonic: int, decay_ms: float) -> bytes:
    """谐波衰减包 (0x41): anchor/harmonic 索引 + Q24 alpha (DATA2..4, u24 LE)."""
    anchor = _require_integer_like(anchor, "anchor 索引", 0, ANCHOR_COUNT - 1)
    harmonic = _require_integer_like(harmonic, "harmonic 索引", 0, HARMONIC_COUNT - 1)
    payload = bytearray(8)
    payload[0] = anchor
    payload[1] = harmonic
    payload[2:5] = decay_ms_to_q24(decay_ms).to_bytes(3, "little")
    return make_packet(CMD_HARMONIC_DECAY, bytes(payload))


def commit_packet() -> bytes:
    """完成标记 (0x42): 仅表意'本次更新参数发送完毕', 不是硬件 ACK."""
    return make_packet(CMD_COMMIT)


# ---------------------------------------------------------------------------
# 预设
# ---------------------------------------------------------------------------


def validate_preset(preset: dict) -> None:
    """严格校验预设结构 (4 锚点 x 16 谐波 + ADSR), 非法则抛 ProtocolError."""
    if not isinstance(preset, dict):
        raise ProtocolError(f"preset 必须是 JSON 对象, 收到 {type(preset).__name__}")

    anchors = preset.get("anchors")
    if not isinstance(anchors, list):
        raise ProtocolError("preset 缺少 anchors 列表")
    if len(anchors) != ANCHOR_COUNT:
        raise ProtocolError(f"preset 必须包含 {ANCHOR_COUNT} 个 anchors, 实际为 {len(anchors)} 个")

    for expected_name, expected_note, anchor in zip(ANCHOR_NAMES, ANCHOR_MIDI_NOTES, anchors):
        if not isinstance(anchor, dict):
            raise ProtocolError(f"anchor {expected_name} 必须是 JSON 对象")
        if str(anchor.get("name", "")).upper() != expected_name:
            raise ProtocolError(f"anchor {expected_name} 的名称不正确: {anchor.get('name')!r}")
        if "midi_note" not in anchor:
            raise ProtocolError(f"anchor {expected_name} 缺少 midi_note")
        midi_note = _require_integer_like(anchor["midi_note"], f"{expected_name} midi_note", 0, 127)
        if midi_note != expected_note:
            raise ProtocolError(f"anchor {expected_name} 必须使用 MIDI 音符 {expected_note}, 收到 {midi_note}")

        amplitudes = _require_sequence(anchor.get("amplitudes"), f"{expected_name} amplitudes", HARMONIC_COUNT)
        decays = _require_sequence(anchor.get("decay_ms"), f"{expected_name} decay_ms", HARMONIC_COUNT)
        for index, value in enumerate(amplitudes):
            _require_range(value, f"{expected_name} 谐波 {index} 幅度", 0.0, 1.0)
        for index, value in enumerate(decays):
            _require_range(value, f"{expected_name} 谐波 {index} 衰减(ms)", 0.0, 120_000.0)

    adsr = preset.get("adsr")
    if not isinstance(adsr, dict):
        raise ProtocolError("preset 缺少 adsr 对象")
    for name in ("attack_ms", "decay_ms", "release_ms"):
        if name not in adsr:
            raise ProtocolError(f"preset ADSR 缺少 {name}")
        _require_range(adsr[name], f"ADSR {name}", 0.1, 60_000.0)
    if "sustain" not in adsr:
        raise ProtocolError("preset ADSR 缺少 sustain")
    _require_range(adsr["sustain"], "ADSR sustain", 0.0, 1.0)


def preset_packets(preset: dict) -> list[bytes]:
    """把预设展开为发送序列: 4 ADSR + 4x16 幅度 + 4x16 衰减 + 1 完成标记 = 133 包."""
    validate_preset(preset)
    adsr = preset["adsr"]
    packets = [
        timing_packet(CMD_ATTACK, float(adsr["attack_ms"])),
        timing_packet(CMD_DECAY, float(adsr["decay_ms"])),
        sustain_packet(float(adsr["sustain"])),
        timing_packet(CMD_RELEASE, float(adsr["release_ms"])),
    ]
    for anchor_index, anchor in enumerate(preset["anchors"]):
        for harmonic_index, value in enumerate(anchor["amplitudes"]):
            packets.append(amplitude_packet(anchor_index, harmonic_index, float(value)))
        for harmonic_index, value in enumerate(anchor["decay_ms"]):
            packets.append(harmonic_decay_packet(anchor_index, harmonic_index, float(value)))
    packets.append(commit_packet())
    return packets


def load_preset(path: Path | str) -> dict:
    """读取 JSON 预设并校验; JSON 结构/数值非法时抛出异常 (不静默降级).

    utf-8-sig 同时接受带 BOM (Windows 常见) 与不带 BOM 的 UTF-8; 非法 UTF-8 报 ProtocolError.
    """
    try:
        raw = Path(path).read_text(encoding="utf-8-sig")
    except UnicodeDecodeError as error:
        raise ProtocolError(f"预设文件不是合法 UTF-8 ({path}): {error}") from error
    except OSError as error:
        raise ProtocolError(f"无法读取预设文件 {path}: {error}") from error
    try:
        preset = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ProtocolError(f"预设文件不是合法 JSON ({path}): {error}") from error
    validate_preset(preset)
    return preset


# ---------------------------------------------------------------------------
# 十六进制 / 文本工具
# ---------------------------------------------------------------------------


def parse_hex(text: str) -> bytes:
    """严格解析十六进制字符串.

    支持空白分隔 (``A5 5A`` / ``A5\\n5A``) 或连续十六进制 (``a55a``, 大小写均可)。
    不允许 0x 前缀、逗号等分隔符, 也不允许删除非法字符; 奇数个有效半字节报错。
    """
    if isinstance(text, (bytes, bytearray)):
        try:
            text = bytes(text).decode("ascii")
        except UnicodeDecodeError as error:
            raise ProtocolError("hex 文本不是 ASCII") from error
    if not isinstance(text, str):
        raise ProtocolError(f"hex 文本必须是 str, 收到 {type(text).__name__}")

    compact_parts = []
    for character in text:
        if character.isspace():
            compact_parts.append(" ")
            continue
        if character not in _HEX_DIGITS:
            raise ProtocolError(f"hex 文本中出现非法字符 {character!r} (不允许静默忽略)")
        compact_parts.append(character)
    compact = "".join(compact_parts).strip()

    if not compact:
        return b""
    # split() 无参数会合并连续空白, 因此 groups 中没有空串
    groups = compact.split()
    if len(groups) > 1:
        for group in groups:
            if len(group) % 2 != 0:
                raise ProtocolError(f"hex 分组 {group!r} 含奇数个十六进制字符")
        nibbles = "".join(groups)
    else:
        if len(compact) % 2 != 0:
            raise ProtocolError(f"hex 文本含奇数个十六进制字符 ({len(compact)} 个)")
        nibbles = compact
    return bytes.fromhex(nibbles)


def encode_text(text: str, append_crlf: bool = False) -> bytes:
    """把文本编码为 UTF-8 字节用于 UART 透传; append_crlf=True 时追加 CRLF."""
    if not isinstance(text, str):
        raise ProtocolError(f"text 必须是 str, 收到 {type(text).__name__}")
    data = text.encode("utf-8")
    if append_crlf:
        data += b"\r\n"
    return data
