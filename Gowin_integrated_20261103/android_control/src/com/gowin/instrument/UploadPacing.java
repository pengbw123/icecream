package com.gowin.instrument;

/** Called only after both GATT completion and FPGA ACK; clock is monotonic. */
public final class UploadPacing {
    public static final long FAST_START_SPACING_MS=30, COMPAT_AFTER_ACK_MS=40;
    public static final long HIGH_BAUD_START_SPACING_MS=5;
    private UploadPacing() {}
    public static long delayAfterReady(boolean fast,long sentAtMs,long nowMs){
        if(!fast)return COMPAT_AFTER_ACK_MS;
        long elapsed=Math.max(0,nowMs-sentAtMs);
        return Math.max(0,FAST_START_SPACING_MS-elapsed);
    }
    /** Mode 2 requires both JDY-23 and FPGA UART to be configured for 115200. */
    public static long delayAfterReady(int mode,long sentAtMs,long nowMs){
        if(mode==1)return COMPAT_AFTER_ACK_MS;
        if(mode!=0&&mode!=2)throw new IllegalArgumentException("上传模式无效");
        long spacing=mode==2?HIGH_BAUD_START_SPACING_MS:FAST_START_SPACING_MS;
        return Math.max(0,spacing-Math.max(0,nowMs-sentAtMs));
    }
}
