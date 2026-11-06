package com.gowin.instrument;

import java.util.ArrayList;
import java.util.List;

/** Exact mirror of pc_control/protocol.py. Round ties to even, not Math.round. */
public final class Protocol {
    public static final double SAMPLE_RATE = 48828.125;
    public static final String[] ANCHORS = {"C2", "C3", "C4", "C6"};
    public static final int[] MIDI = {36, 48, 60, 84};
    private Protocol() {}
    public static double range(double value, double low, double high, String name) {
        if (Double.isNaN(value) || Double.isInfinite(value) || value < low || value > high)
            throw new IllegalArgumentException(name + " 范围 " + low + ".." + high);
        return value;
    }
    private static void index(int anchor, int harmonic) {
        if (anchor < 0 || anchor > 3 || harmonic < 0 || harmonic > 15)
            throw new IllegalArgumentException("锚点/谐波索引越界");
    }
    private static void le(byte[] data, int offset, long value, int count) {
        for (int i=0; i<count; i++) data[offset+i]=(byte)(value >>> (8*i));
    }
    public static byte[] packet(int command, byte[] data) {
        if (command < 0 || command > 255 || data == null || data.length != 8)
            throw new IllegalArgumentException("非法帧参数");
        byte[] frame = new byte[12]; frame[0]=(byte)0xa5; frame[1]=0x5a;
        frame[2]=(byte)command; int xor=command;
        for (int i=0;i<8;i++) { frame[i+3]=data[i]; xor ^= data[i]&255; }
        frame[11]=(byte)xor; return frame;
    }
    public static byte[] timing(int command, double ms) {
        if (command != 0x10 && command != 0x11 && command != 0x13)
            throw new IllegalArgumentException("非法 ADSR 时间命令");
        range(ms,0.1,60000,"ADSR 毫秒");
        long samples=Math.max(1,(long)Math.rint(ms*SAMPLE_RATE/1000.0));
        long inc=samples<=1 ? 0xffffffffL : (long)Math.rint(0xffffffffL/(double)(samples-1));
        byte[] data=new byte[8]; le(data,0,samples,4); le(data,4,Math.min(0xffffffffL,inc),4);
        return packet(command,data);
    }
    public static byte[] sustain(double value) {
        byte[] data=new byte[8]; le(data,0,(long)Math.rint(range(value,0,1,"延音")*65535),2);
        return packet(0x12,data);
    }
    public static byte[] amplitude(int anchor,int harmonic,double value) {
        index(anchor,harmonic); byte[] data=new byte[8]; data[0]=(byte)anchor; data[1]=(byte)harmonic;
        le(data,2,(long)Math.rint(range(value,0,1,"幅度")*32767),2); return packet(0x40,data);
    }
    public static long decayQ24(double ms) {
        range(ms,0,120000,"谐波衰减毫秒"); if(ms==0) return 0;
        double alpha=1.0-Math.exp(-1.0/(ms*SAMPLE_RATE/1000.0));
        return Math.max(1,Math.min(16777215L,(long)Math.rint(alpha*16777215)));
    }
    public static byte[] harmonicDecay(int anchor,int harmonic,double ms) {
        index(anchor,harmonic); byte[] data=new byte[8]; data[0]=(byte)anchor; data[1]=(byte)harmonic;
        le(data,2,decayQ24(ms),3); return packet(0x41,data);
    }
    public static List<byte[]> frames(Preset preset) {
        preset.validate(); List<byte[]> frames=new ArrayList<>();
        frames.add(timing(0x10,preset.attack)); frames.add(timing(0x11,preset.decay));
        frames.add(sustain(preset.sustain)); frames.add(timing(0x13,preset.release));
        for(int a=0;a<4;a++) {
            for(int h=0;h<16;h++) frames.add(amplitude(a,h,preset.amplitudes[a][h]));
            for(int h=0;h<16;h++) frames.add(harmonicDecay(a,h,preset.decayMs[a][h]));
        }
        frames.add(packet(0x42,new byte[8])); return frames;
    }
    public static String hex(byte[] data) {
        StringBuilder s=new StringBuilder(); for(byte b:data) {
            if(s.length()>0)s.append(' '); s.append(String.format(java.util.Locale.US,"%02X",b&255));
        } return s.toString();
    }
}
