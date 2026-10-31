package com.gowin.instrument;

import org.json.JSONArray;
import org.json.JSONObject;

public final class PresetJson {
    private PresetJson() {}
    private static double number(Object obj,String name) {
        if(!(obj instanceof Number))throw new IllegalArgumentException(name+" 必须是数字");
        double value=((Number)obj).doubleValue();
        if(Double.isNaN(value)||Double.isInfinite(value))throw new IllegalArgumentException(name+" 必须是有限数字");
        return value;
    }
    public static Preset parse(String text) throws Exception {
        if(text.startsWith("\ufeff"))text=text.substring(1);
        JSONObject root=new JSONObject(text);
        if(root.has("format")&&!"gowin-additive-tone-v1".equals(root.getString("format")))
            throw new IllegalArgumentException("不支持的预设格式");
        if(root.has("sample_rate_hz")&&number(root.get("sample_rate_hz"),"采样率")!=Protocol.SAMPLE_RATE)
            throw new IllegalArgumentException("采样率与当前 FPGA 不符");
        Preset p=new Preset();p.name=root.optString("name","导入音色");
        JSONObject adsr=root.getJSONObject("adsr");
        p.attack=number(adsr.get("attack_ms"),"attack_ms");p.decay=number(adsr.get("decay_ms"),"decay_ms");
        p.sustain=number(adsr.get("sustain"),"sustain");p.release=number(adsr.get("release_ms"),"release_ms");
        JSONArray anchors=root.getJSONArray("anchors");if(anchors.length()!=4)throw new IllegalArgumentException("必须有四个锚点");
        for(int a=0;a<4;a++) {
            JSONObject item=anchors.getJSONObject(a);
            if(!Protocol.ANCHORS[a].equalsIgnoreCase(item.getString("name"))||number(item.get("midi_note"),"音符")!=Protocol.MIDI[a])
                throw new IllegalArgumentException("锚点顺序必须为 C2/C3/C4/C6");
            JSONArray amp=item.getJSONArray("amplitudes"),dec=item.getJSONArray("decay_ms");
            if(amp.length()!=16||dec.length()!=16)throw new IllegalArgumentException("每个锚点必须有 16 路谐波");
            for(int h=0;h<16;h++){p.amplitudes[a][h]=number(amp.get(h),"幅度");p.decayMs[a][h]=number(dec.get(h),"衰减");}
        }p.validate();return p;
    }
    public static String stringify(Preset p) throws Exception {
        p.validate();JSONObject root=new JSONObject();root.put("format","gowin-additive-tone-v1");root.put("name",p.name);
        root.put("sample_rate_hz",Protocol.SAMPLE_RATE);JSONObject adsr=new JSONObject();
        adsr.put("attack_ms",p.attack);adsr.put("decay_ms",p.decay);adsr.put("sustain",p.sustain);adsr.put("release_ms",p.release);
        root.put("adsr",adsr);JSONArray anchors=new JSONArray();
        for(int a=0;a<4;a++) {JSONObject item=new JSONObject();item.put("name",Protocol.ANCHORS[a]);item.put("midi_note",Protocol.MIDI[a]);
            JSONArray amp=new JSONArray(),dec=new JSONArray();for(int h=0;h<16;h++){amp.put(p.amplitudes[a][h]);dec.put(p.decayMs[a][h]);}
            item.put("amplitudes",amp);item.put("decay_ms",dec);anchors.put(item);
        }root.put("anchors",anchors);return root.toString(2);
    }
}
