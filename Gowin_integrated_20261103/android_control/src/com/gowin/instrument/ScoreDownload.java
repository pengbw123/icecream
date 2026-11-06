package com.gowin.instrument;

import java.io.*;
import java.net.*;
import java.security.MessageDigest;

/** HTTPS bytes -> validated score -> durable private MIDI cache. No Bluetooth actions. */
public final class ScoreDownload {
    private ScoreDownload() {}
    public interface Progress { void update(int received,long total); }
    public static final class CancelToken {
        private volatile boolean cancelled;
        private volatile HttpURLConnection connection;
        public void cancel(){cancelled=true;HttpURLConnection c=connection;if(c!=null)c.disconnect();}
        public void check() throws IOException {if(cancelled||Thread.currentThread().isInterrupted())throw new IOException("已取消下载");}
        private void attach(HttpURLConnection c)throws IOException{connection=c;check();}
    }
    public static final class Result {
        public final File file;public final Score score;public final byte[] bytes;
        Result(File file,Score score,byte[] bytes){this.file=file;this.score=score;this.bytes=bytes.clone();}
    }
    public static URL httpsUrl(String text)throws IOException{
        try{URL u=new URI(text.trim()).toURL();if(!"https".equalsIgnoreCase(u.getProtocol())||u.getHost().isEmpty()||u.getUserInfo()!=null||u.getRef()!=null)throw new IOException("请使用HTTPS MIDI文件直链，不要填写网页或登录凭据");return u;}
        catch(URISyntaxException|IllegalArgumentException|MalformedURLException|NullPointerException ex){throw new IOException("MIDI网址无效",ex);}
    }
    public static byte[] readBounded(InputStream in,long advertised,CancelToken cancel,Progress progress)throws IOException{
        cancel.check();if(advertised < -1)throw new IOException("下载长度无效");
        if(advertised>Score.MAX_BYTES)throw new IOException("MIDI文件超过1 MiB");
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buf=new byte[4096];int n;
        while((n=in.read(buf))!=-1){cancel.check();if(n==0)continue;if(n>Score.MAX_BYTES-out.size())throw new IOException("MIDI文件超过1 MiB");out.write(buf,0,n);if(progress!=null)progress.update(out.size(),advertised);}
        cancel.check();if(advertised>=0&&out.size()!=advertised)throw new IOException("下载被截断或长度不符");return out.toByteArray();
    }
    public static String sha256(byte[] bytes)throws IOException{
        try{byte[] digest=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder s=new StringBuilder(64);for(byte b:digest){int v=b&255;s.append(Character.forDigit(v>>>4,16)).append(Character.forDigit(v&15,16));}return s.toString();}
        catch(Exception ex){throw new IOException("无法检查文件摘要",ex);}
    }
    public static Score validate(String name,byte[] bytes,String expected)throws IOException{
        if(expected!=null&&!expected.isEmpty()&&(!expected.matches("(?i)[0-9a-f]{64}")||!sha256(bytes).equalsIgnoreCase(expected)))throw new IOException("下载内容与曲库摘要不符，请稍后重试");
        try{return Score.fromMidi(name,bytes);}catch(IllegalArgumentException ex){throw new IOException("此文件不能用于当前FPGA："+ex.getMessage(),ex);}
    }
    private static File cacheFile(File dir,URL url)throws IOException{return new File(dir,sha256(url.toExternalForm().getBytes("UTF-8"))+".mid");}
    public static Result loadCached(String name,String url,String expected,File dir)throws IOException{
        File f=cacheFile(dir,httpsUrl(url));if(!f.isFile())throw new IOException("尚未下载这首曲目，请先联网下载");
        byte[] data;try(InputStream in=new FileInputStream(f)){data=readBounded(in,f.length(),new CancelToken(),null);}return new Result(f,validate(name,data,expected),data);
    }
    public static byte[] fetchBytes(String url,CancelToken cancel,Progress progress)throws IOException{return fetch(httpsUrl(url),cancel,progress);}
    private static byte[] fetch(URL url,CancelToken cancel,Progress progress)throws IOException{
        URL current=url;
        for(int redirects=0;redirects<=5;redirects++){
            cancel.check();HttpURLConnection c=(HttpURLConnection)current.openConnection();
            try{
                cancel.attach(c);c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(15000);c.setUseCaches(false);
                c.setRequestProperty("Accept","audio/midi,audio/x-midi,application/octet-stream,text/html");c.setRequestProperty("Accept-Encoding","identity");c.setRequestProperty("User-Agent","GowinInstrument/0.3.2");
                int code=c.getResponseCode();
                if(code==301||code==302||code==303||code==307||code==308){String location=c.getHeaderField("Location");if(location==null)throw new IOException("下载重定向缺少地址");current=httpsUrl(new URL(current,location).toExternalForm());continue;}
                if(code!=200)throw new IOException("下载失败：HTTP "+code);
                String encoding=c.getContentEncoding();if(encoding!=null&&!"identity".equalsIgnoreCase(encoding))throw new IOException("下载编码不支持，请使用MIDI直链");
                long length=-1;String value=c.getHeaderField("Content-Length");if(value!=null)try{length=Long.parseLong(value);}catch(NumberFormatException ex){throw new IOException("下载长度无效");}
                try(InputStream in=c.getInputStream()){return readBounded(in,length,cancel,progress);}
            }finally{cancel.connection=null;c.disconnect();}
        }
        throw new IOException("下载重定向次数过多");
    }
    public static Result download(String name,String url,String expected,File dir,CancelToken cancel,Progress progress)throws IOException{
        URL source=httpsUrl(url);byte[] data=fetch(source,cancel,progress);cancel.check();Score score=validate(name,data,expected);
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法建立手机曲谱目录");
        File target=cacheFile(dir,source),temp=File.createTempFile("midi-",".part",dir);File backup=new File(target.getPath()+".bak");boolean committed=false;
        try{
            try(FileOutputStream out=new FileOutputStream(temp)){out.write(data);out.getFD().sync();}cancel.check();
            // File.renameTo replaces an existing file on Android. Backup also supports desktop tests.
            if(target.exists()){
                if(backup.exists()&&!backup.delete())throw new IOException("无法更新旧曲谱缓存");
                if(!target.renameTo(backup))throw new IOException("无法保存旧曲谱缓存");
            }
            if(!temp.renameTo(target)){if(backup.exists())backup.renameTo(target);throw new IOException("无法保存新曲谱");}
            committed=true;if(backup.exists())backup.delete();return new Result(target,score,data);
        }finally{if(!committed){temp.delete();if(backup.exists()&&!target.exists())backup.renameTo(target);}}
    }
}
