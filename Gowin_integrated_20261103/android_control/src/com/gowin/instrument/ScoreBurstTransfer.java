package com.gowin.instrument;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.zip.CRC32;

/**
 * 有界曲谱窗口传输状态机。
 *
 * 只描述本地 GATT 写完成与板端回复计数，不伪称回复有序号：
 * ackCount 只表示"收到了多少条匹配 cmd 的回复"，回复先后与对应关系无法由此证明；
 * 真正的完整性由板端按 0x51 索引(0,1,2,...)重组后校验最终 0x52 的 CRC32 判定。
 *
 * 分组规则：最多 8 个连续 0x51 事件一组；0x55/0x50/0x52 各自单独一组。
 * 帧格式仍为原 12 字节 A5 5A CMD DATA8 XOR，最终 CRC 封存不改。
 * 不自动重试：任何失败/取消都清空状态，必须重新 start。
 */
public final class ScoreBurstTransfer {
    /** 单个 GATT 负载上限。12 字节原始帧允许跨段，接收端必须按字节精确重组。 */
    public static final int GATT_PAYLOAD = 20;
    /** 事件帧 0x51 每组上限。 */
    public static final int MAX_EVENTS_PER_GROUP = 8;
    /** 单事件最大时间差(毫秒)，与 Score 上限一致。 */
    private static final long MAX_DELTA_MS = 600000L;

    private static final int EVENTS = 0x51, BEGIN = 0x50, SEAL = 0x52, ARM = 0x55;

    private List<byte[]> frames = Collections.emptyList();
    private int[][] groups = new int[0][];
    private int groupIndex, done, total, ackCount;
    private boolean busy, written;

    // ---------------- 传输控制 ----------------

    /**
     * 校验整份上传结构后进入 busy。全部校验通过前不改变任何状态，也不修改入参。
     * @throws IllegalStateException 传输中重复调用
     * @throws IllegalArgumentException 入参为 null 或结构非法
     */
    public void start(List<byte[]> input) {
        start(input,ScoreCapabilities.LEGACY_EVENTS,MAX_EVENTS_PER_GROUP);
    }
    public void start(List<byte[]> input,int capacity,int groupEvents) {
        if (busy) throw new IllegalStateException("曲谱传输已在进行中，需先完成或取消");
        if (input == null) throw new IllegalArgumentException("上传列表不能为 null");
        if(capacity<1||capacity>Score.MAX_EVENTS||groupEvents<1||groupEvents>MAX_EVENTS_PER_GROUP)throw new IllegalArgumentException("曲谱能力越界");
        if(input.size()<4||input.size()>capacity+3)throw new IllegalArgumentException("曲谱上传帧数越界");
        List<byte[]> copy = new ArrayList<byte[]>(input.size());
        for (int i = 0; i < input.size(); i++) {
            byte[] f = input.get(i);
            if (f == null) throw new IllegalArgumentException("第 " + i + " 帧为 null");
            copy.add(f.clone());
        }
        int[][] plan = validate(copy,capacity,groupEvents);
        frames = copy;
        groups = plan;
        total = copy.size();
        done = 0;
        groupIndex = 0;
        ackCount = 0;
        written = false;
        busy = true;
    }

    public boolean busy() { return busy; }

    /** 已完成整组的帧数。即使 busy() 为 false（完成或取消）也返回最后计数，取消后为 0。 */
    public int done() { return done; }

    /** 本次上传总帧数(全部组帧数之和)。 */
    public int total() { return total; }

    /** 当前组核心命令：0x55 / 0x50 / 0x51 / 0x52。 */
    public int command() {
        requireBusy();
        return frames.get(groups[groupIndex][0])[2] & 255;
    }

    /** 当前组帧数(1..8)。 */
    public int groupSize() {
        requireBusy();
        return groups[groupIndex][1] - groups[groupIndex][0];
    }

    /** 已接受的回复条数；只证明数量，不证明对应关系。 */
    public int ackCount() { return ackCount; }
    public boolean isWritten() { return written; }

    /**
     * 当前组的 GATT 负载：当前组各帧按原字节顺序连接，再切成每段 {@value #GATT_PAYLOAD} 字节，无 padding。
     * 返回的每个数组都独立于内部状态。仅 busy 时可用。
     */
    public List<byte[]> chunks() {
        requireBusy();
        int[] group = groups[groupIndex];
        int from = group[0], to = group[1];
        int packed = (to - from) * 12;
        byte[] merged = new byte[packed];
        int at = 0;
        for (int i = from; i < to; i++) {
            byte[] f = frames.get(i);
            for (int k = 0; k < 12; k++) merged[at++] = f[k];
        }
        List<byte[]> out = new ArrayList<byte[]>();
        for (int p = 0; p < packed; p += GATT_PAYLOAD) {
            int n = Math.min(GATT_PAYLOAD, packed - p);
            byte[] chunk = new byte[n];
            System.arraycopy(merged, p, chunk, 0, n);
            out.add(chunk);
        }
        return Collections.unmodifiableList(out);
    }

    /** 标记当前组本地 GATT 写入全部完成(必须写完当前组所有分段)。 */
    public void written() {
        requireBusy();
        written = true;
    }

    /**
     * 接受一条板端回复。只做计数与上限检查，不声称回复有编号或顺序。
     * @return true 表示该回复被接受；cmd 不匹配（含非 busy）返回 false，状态不变
     * @throws IllegalArgumentException status 非 0（先清空状态再抛出），或当前组回复数超过 groupSize
     */
    public boolean reply(int cmd, int status) {
        if (!busy || !pipeline()) return false;
        int expected = command();
        if (cmd != expected) return false;
        if (status != 0) {
            cancel();
            throw new IllegalArgumentException("板端拒绝命令0x" + Integer.toHexString(expected)
                    + " 状态" + status + "，传输已取消，不自动重传");
        }
        ackCount++;
        if (ackCount > groupSize()) {
            int n = groupSize();
            cancel();
            throw new IllegalArgumentException("命令0x" + Integer.toHexString(expected)
                    + " 回复数超过本组帧数 " + n + "，传输已取消，不自动重传");
        }
        return true;
    }

    /** 仅当本地整组写完且回复计数恰好等于 groupSize() 时为 true；非 busy 时为 false。 */
    public boolean canAdvance() {
        return busy && pipeline() && written && ackCount == groupSize();
    }

    /**
     * 进入下一组；已是最后一组则结束 busy。
     * @throws IllegalStateException 非 busy，或未同时满足本地写完与回复计数
     */
    public void advance() {
        requireBusy();
        if (!pipeline()) throw new IllegalStateException("没有可推进的曲谱组，需先 start");
        if (!canAdvance()) throw new IllegalStateException("尚未同时满足整组本地写完与回复计数 "
                + ackCount + "/" + groupSize() + "，不能推进");
        done += groupSize();
        groupIndex++;
        written = false;
        ackCount = 0;
        if (groupIndex >= groups.length) {
            groupIndex = 0;
            groups = new int[0][];
            busy = false;
        }
    }

    /** 清空全部状态；之后 advance() 抛 IllegalStateException，晚到 reply 返回 false。 */
    public void cancel() {
        busy = false;
        written = false;
        ackCount = 0;
        groupIndex = 0;
        done = 0;
        total = 0;
        groups = new int[0][];
        frames = Collections.emptyList();
    }

    // ---------------- 内部实现 ----------------

    private void requireBusy() {
        if (!busy) throw new IllegalStateException("当前没有在途曲谱组，需先 start");
    }

    /** 组划分是否仍然有效(未取消、有当前组)。 */
    private boolean pipeline() {
        return groupIndex >= 0 && groupIndex < groups.length;
    }

    private static long le(byte[] f, int at, int n) {
        long v = 0;
        for (int i = 0; i < n; i++) v |= ((long) (f[at + i] & 255)) << (8 * i);
        return v;
    }

    /** 8 个数据字节是否全为零。 */
    private static boolean allZero(byte[] f) {
        for (int i = 3; i < 11; i++) if (f[i] != 0) return false;
        return true;
    }

    /** 严格校验帧头、XOR、0x55/0x50/0x51/0x52 结构及最终 CRC32。 */
    private static int[][] validate(List<byte[]> in,int capacity,int groupEvents) {
        final int n = in.size();
        if (n < 3) throw new IllegalArgumentException("上传至少需要 0x55+0x50+0x52 三帧，当前 " + n);

        for (int i = 0; i < n; i++) {
            byte[] f = in.get(i);
            if (f.length != 12) throw new IllegalArgumentException("第 " + i + " 帧长度 " + f.length + "，必须为12字节");
            if ((f[0] & 255) != 0xa5 || (f[1] & 255) != 0x5a)
                throw new IllegalArgumentException("第 " + i + " 帧头不是 A5 5A");
            int xor = f[2] & 255;
            for (int k = 3; k < 11; k++) xor ^= f[k] & 255;
            if (xor != (f[11] & 255)) throw new IllegalArgumentException("第 " + i + " 帧 XOR 校验失败");
        }

        if ((in.get(0)[2] & 255) != ARM || !allZero(in.get(0)))
            throw new IllegalArgumentException("第 0 帧必须为 0x55 且 8 字节数据全 0");

        byte[] begin = in.get(1);
        if ((begin[2] & 255) != BEGIN)
            throw new IllegalArgumentException("第 1 帧必须为 0x50 起始帧");
        long count = le(begin, 3, 2);
        if (count < 1 || count > capacity)
            throw new IllegalArgumentException("0x50 事件数必须为 1.."+capacity+"，当前 " + count);
        int version=begin[5]&255;
        if (version!=1&&version!=2) throw new IllegalArgumentException("0x50 曲谱版本错误");
        if(version==2&&(begin[6]&255)>103)throw new IllegalArgumentException("映射的最低实体键越界");
        for (int k = version==1?6:7; k <= 10; k++)
            if (begin[k] != 0) throw new IllegalArgumentException("0x50 保留字段必须为 0");

        if ((in.get(n - 1)[2] & 255) != SEAL)
            throw new IllegalArgumentException("最后一帧必须为 0x52 封存帧");

        if (n != count + 3)
            throw new IllegalArgumentException("帧数与 0x50 声明的事件数 " + count
                    + " 不符：当前 " + n + " 帧（应为 count+3）");

        CRC32 crc = new CRC32();
        for (int i = 2; i < n - 1; i++) {
            byte[] f = in.get(i);
            if ((f[2] & 255) != EVENTS)
                throw new IllegalArgumentException("第 " + i + " 帧必须为 0x51 事件帧，命令0x"
                        + Integer.toHexString(f[2] & 255));
            if (le(f, 3, 2) != i - 2)
                throw new IllegalArgumentException("第 " + i + " 帧事件索引应为 " + (i - 2) + "，实际 " + le(f, 3, 2));
            long packed = le(f, 5, 4);
            if(version==2&&((packed>>>25)!=0||((packed>>>20)&31)>24))throw new IllegalArgumentException("映射实体键编号越界");
            long delta = version==2?(packed&0xfffff):packed;
            if (delta > MAX_DELTA_MS)
                throw new IllegalArgumentException("第 " + i + " 帧时间差 " + delta + " 超过 " + MAX_DELTA_MS + "ms");
            if ((f[9] & 255) > 127 || (f[10] & 255) > 127)
                throw new IllegalArgumentException("第 " + i + " 帧音符/力度必须为 0..127");
            crc.update(f, 5, 6);
        }

        byte[] seal = in.get(n - 1);
        if (le(seal, 3, 4) != crc.getValue())
            throw new IllegalArgumentException("0x52 CRC32 与事件 D2..D7 串联结果不符");
        if (le(seal, 7, 2) != count)
            throw new IllegalArgumentException("0x52 D4..D5 事件数应为 " + count + "，实际 " + le(seal, 7, 2));
        if ((seal[9] & 255) != version) throw new IllegalArgumentException("0x52 曲谱版本不一致");
        if (seal[10] != 0) throw new IllegalArgumentException("0x52 D7 必须为 0");

        List<int[]> groups = new ArrayList<int[]>();
        int at = 0;
        while (at < n) {
            int cmd = in.get(at)[2] & 255;
            int end;
            if (cmd == EVENTS) {
                end = at;
                while (end < n && (in.get(end)[2] & 255) == EVENTS && end - at < groupEvents) end++;
            } else {
                end = at + 1;
            }
            if (end - at > 1 && cmd != EVENTS)
                throw new IllegalArgumentException("0x" + Integer.toHexString(cmd) + " 必须单独成组，不允许与其他帧合组");
            groups.add(new int[]{at, end});
            at = end;
        }
        return groups.toArray(new int[groups.size()][]);
    }
}
