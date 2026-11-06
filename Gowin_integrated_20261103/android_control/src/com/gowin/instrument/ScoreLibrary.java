package com.gowin.instrument;

import android.content.Context;
import android.content.SharedPreferences;
import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Names and lists the existing content-addressed private MIDI files. */
public final class ScoreLibrary {
    private static final String NAMES="score-library-v1",RECENT="web_midi_recent";
    private ScoreLibrary(){}

    public static final class Entry {
        public final String token,name;
        public final long size,modified;
        public final boolean unnamedLegacy;
        Entry(String token,String name,long size,long modified,boolean unnamedLegacy){
            this.token=token;this.name=name;this.size=size;this.modified=modified;this.unnamedLegacy=unnamedLegacy;
        }
    }

    private static boolean tokenOk(String token){return token!=null&&token.matches("[0-9a-f]{64}\\.mid");}
    private static File directory(Context c)throws IOException{
        File parent=c.getFilesDir().getCanonicalFile();
        File dir=new File(parent,"web-midi").getCanonicalFile();
        if(!parent.equals(dir.getParentFile()))throw new IOException("曲库目录无效");
        return dir;
    }
    private static File file(Context c,String token)throws IOException{
        if(!tokenOk(token))throw new IOException("曲谱标识无效");
        File dir=directory(c),item=new File(dir,token).getCanonicalFile();
        if(!dir.equals(item.getParentFile()))throw new IOException("曲谱位置无效");
        return item;
    }
    /** Preserve the one title older versions stored before changing that pointer. */
    private static void migrateRecent(Context c)throws IOException{
        SharedPreferences old=c.getSharedPreferences(RECENT,Context.MODE_PRIVATE);
        String token=old.getString("last_token",null),name=old.getString("last_name",null);
        if(!tokenOk(token)||name==null||!file(c,token).isFile())return;
        SharedPreferences names=c.getSharedPreferences(NAMES,Context.MODE_PRIVATE);
        if(!names.contains(token)&&!names.edit().putString(token,WebMidiDownload.displayName(name)).commit())
            throw new IOException("无法保存历史曲谱名称，原文件仍在手机");
    }

    /** Called on a worker thread; original bytes are retained and deduplicated by SHA-256. */
    public static synchronized String save(Context c,byte[] bytes,String name)throws Exception{
        migrateRecent(c);
        String token=WebMidiDownload.cache(c.getFilesDir(),bytes);
        SharedPreferences names=c.getSharedPreferences(NAMES,Context.MODE_PRIVATE);
        SharedPreferences.Editor edit=names.edit().putLong(token+".time",System.currentTimeMillis());
        if(!names.contains(token))edit.putString(token,WebMidiDownload.displayName(name));
        if(!edit.commit())throw new IOException("MIDI已缓存，但曲库名称未能保存");
        return token;
    }

    /** Includes old hash-named downloads, without modifying or deleting them. */
    public static synchronized List<Entry> list(Context c)throws IOException{
        migrateRecent(c);
        File dir=directory(c);File[] files=dir.isDirectory()?dir.listFiles():new File[0];
        if(files==null)throw new IOException("无法读取手机曲库");
        SharedPreferences names=c.getSharedPreferences(NAMES,Context.MODE_PRIVATE);
        List<Entry> result=new ArrayList<>();
        for(File candidate:files){
            String token=candidate.getName();if(!tokenOk(token)||!candidate.isFile()||!file(c,token).equals(candidate.getCanonicalFile()))continue;
            boolean unknown=!names.contains(token);
            String name=unknown?"历史下载-"+token.substring(0,8)+".mid":names.getString(token,"网页下载曲谱.mid");
            long at=names.getLong(token+".time",candidate.lastModified());
            result.add(new Entry(token,name,candidate.length(),at,unknown));
        }
        Collections.sort(result,new Comparator<Entry>(){public int compare(Entry a,Entry b){
            int n=Long.compare(b.modified,a.modified);return n!=0?n:a.token.compareTo(b.token);
        }});
        return result;
    }
    public static synchronized byte[] read(Context c,String token)throws Exception{
        return WebMidiDownload.readCached(c.getFilesDir(),token);
    }
    public static synchronized void rename(Context c,String token,String name)throws IOException{
        if(name==null||name.trim().isEmpty())throw new IOException("请输入曲名");
        if(!file(c,token).isFile())throw new IOException("曲谱不存在");
        String safe=WebMidiDownload.displayName(name);
        if(!c.getSharedPreferences(NAMES,Context.MODE_PRIVATE).edit().putString(token,safe).commit())
            throw new IOException("曲名保存失败，原文件未修改");
        SharedPreferences recent=c.getSharedPreferences(RECENT,Context.MODE_PRIVATE);
        if(token.equals(recent.getString("last_token",null)))recent.edit().putString("last_name",safe).apply();
    }
    public static synchronized void delete(Context c,String token)throws IOException{
        File selected=file(c,token);
        if(!selected.isFile())throw new IOException("曲谱不存在，未删除其他文件");
        if(!selected.delete())throw new IOException("删除失败，曲谱仍在手机");
        c.getSharedPreferences(NAMES,Context.MODE_PRIVATE).edit().remove(token).remove(token+".time").apply();
        SharedPreferences recent=c.getSharedPreferences(RECENT,Context.MODE_PRIVATE);
        if(token.equals(recent.getString("last_token",null)))recent.edit().remove("last_token").remove("last_name").apply();
    }
}
