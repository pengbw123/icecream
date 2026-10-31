package com.gowin.instrument;

public final class Preset {
    public String name="我的音色";
    public double attack=30, decay=500, sustain=0.18, release=800;
    public final double[][] amplitudes=new double[4][16];
    public final double[][] decayMs=new double[4][16];
    public void validate() {
        Protocol.range(attack,0.1,60000,"起音"); Protocol.range(decay,0.1,60000,"衰减");
        Protocol.range(sustain,0,1,"延音"); Protocol.range(release,0.1,60000,"释音");
        for(int a=0;a<4;a++)for(int h=0;h<16;h++) {
            Protocol.range(amplitudes[a][h],0,1,"谐波幅度");
            Protocol.range(decayMs[a][h],0,120000,"谐波衰减");
        }
    }
    public Preset copy() {
        Preset p=new Preset(); p.name=name; p.attack=attack;p.decay=decay;p.sustain=sustain;p.release=release;
        for(int a=0;a<4;a++) {System.arraycopy(amplitudes[a],0,p.amplitudes[a],0,16);System.arraycopy(decayMs[a],0,p.decayMs[a],0,16);}return p;
    }
}
