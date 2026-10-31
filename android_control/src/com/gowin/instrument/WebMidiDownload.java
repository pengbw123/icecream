package com.gowin.instrument;

import java.io.*;
import java.net.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.*;

/** Downloads only a user's normal website download event, with that browser session. */
public final class WebMidiDownload {
    public interface Cookies { String get(String url); void put(String url,String cookie); }
    public interface Connections { HttpURLConnection open(URL url)throws IOException; }
    public static final class Token { public volatile boolean cancelled; }
    public static final class Result {
        public final byte[] bytes; public final String name;
        Result(byte[] bytes,String name){this.bytes=bytes;this.name=name;}
    }
    private static final Connections NETWORK=new Connections(){public HttpURLConnection open(URL u)throws IOException{return (HttpURLConnection)u.openConnection();}};
    private WebMidiDownload(){}
    public static Result fetch(String url,String userAgent,String referer,Cookies cookies,Token token)throws Exception{
        return fetch(url,userAgent,referer,cookies,token,NETWORK);
    }
    public static Result fetch(String url,String userAgent,String referer,Cookies cookies,Token token,Connections network)throws Exception{
        URL current=checked(url);
        for(int redirects=0;redirects<=5;redirects++){
            check(token); HttpURLConnection c=network.open(current);
            try {
                c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(15000);
                c.setRequestProperty("Accept","audio/midi,audio/x-midi,application/octet-stream");
                c.setRequestProperty("Accept-Encoding","identity");
                c.setRequestProperty("User-Agent",header(userAgent,"GowinInstrument/0.3.2"));
                // Re-evaluate cookies for every URL. Never forward one host's
                // cookie or full referring URL to a different origin.
                String cookie=cookies==null?null:cookies.get(current.toExternalForm());
                if(cookie!=null&&!cookie.isEmpty())c.setRequestProperty("Cookie",header(cookie,""));
                if(referer!=null){try{URL page=checked(referer);if(page.getHost().equalsIgnoreCase(current.getHost()))c.setRequestProperty("Referer",page.toExternalForm());}catch(IOException ignored){}}
                int status=c.getResponseCode();check(token);
                if(cookies!=null)for(Map.Entry<String,List<String>> h:c.getHeaderFields().entrySet())
                    if(h.getKey()!=null&&h.getKey().equalsIgnoreCase("Set-Cookie"))for(String value:h.getValue())cookies.put(current.toExternalForm(),value);
                if(status==301||status==302||status==303||status==307||status==308){
                    if(redirects==5)throw new IOException("网站下载重定向次数过多");
                    String location=c.getHeaderField("Location");if(location==null)throw new IOException("网站下载重定向无目标");
                    current=checked(new URL(current,location).toExternalForm());continue;
                }
                if(status!=200)throw new IOException("网站下载未成功（HTTP "+status+"），请确认已登录会员及有该文件下载权限");
                String length=c.getHeaderField("Content-Length");
                if(length!=null)try{if(Long.parseLong(length)>Score.MAX_BYTES)throw new IOException("MIDI文件超过1 MiB");}catch(NumberFormatException ignored){}
                byte[] bytes;
                try(InputStream in=c.getInputStream()){bytes=read(in,token);}
                check(token);checkMidi(bytes);
                return new Result(bytes,name(c.getHeaderField("Content-Disposition"),current));
            } finally {c.disconnect();}
        }
        throw new IOException("网站下载失败");
    }
    private static URL checked(String raw)throws IOException{
        try {
            URI uri=new URI(raw);
            if(!"https".equalsIgnoreCase(uri.getScheme())||uri.getHost()==null||uri.getUserInfo()!=null||
                    (uri.getPort()!=-1&&uri.getPort()!=443))throw new IOException("网页下载只支持普通HTTPS地址");
            // Preserve already escaped paths and signed query strings exactly.
            String clean=uri.toASCIIString();int fragment=clean.indexOf('#');
            if(fragment>=0)clean=clean.substring(0,fragment);
            return new URL(clean);
        } catch(URISyntaxException|IllegalArgumentException ex){throw new IOException("网页下载地址无效");}
    }
    private static String header(String text,String fallback)throws IOException{
        if(text==null||text.isEmpty())return fallback;
        if(text.indexOf('\r')>=0||text.indexOf('\n')>=0)throw new IOException("网站下载请求信息无效");
        return text;
    }
    private static void check(Token token)throws IOException{if(token==null||token.cancelled||Thread.currentThread().isInterrupted())throw new IOException("下载已取消");}
    private static byte[] read(InputStream in,Token token)throws IOException{
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buf=new byte[4096];int n;
        while(true){if(token!=null)check(token);n=in.read(buf);if(n<0)break;if(out.size()+n>Score.MAX_BYTES)throw new IOException("MIDI文件超过1 MiB");out.write(buf,0,n);}
        return out.toByteArray();
    }
    private static void checkMidi(byte[] b)throws IOException{
        if(b.length<26||b[0]!='M'||b[1]!='T'||b[2]!='h'||b[3]!='d')
            throw new IOException("网站返回的不是标准MIDI。请确认会员已登录，并点击MIDI下载；PDF/EOP/EOPN不能直接上传FPGA");
    }
    public static String displayName(String raw){
        String n=raw==null?"":raw.replaceAll("[\\p{Cntrl}\\\\/:*?\"<>|]","_").trim();
        if(n.isEmpty())n="网页下载曲谱.mid";
        if(n.length()>100)n=n.substring(0,100);
        if(!n.toLowerCase(Locale.US).endsWith(".mid")&&!n.toLowerCase(Locale.US).endsWith(".midi"))n+=".mid";
        return n;
    }
    private static String name(String disposition,URL url){
        String n=null;
        if(disposition!=null){
            Matcher ext=Pattern.compile("(?i)filename\\*\\s*=\\s*UTF-8''([^;]+)").matcher(disposition);
            if(ext.find())try{n=URLDecoder.decode(ext.group(1).trim(),"UTF-8");}catch(Exception ignored){}
            if(n==null){Matcher plain=Pattern.compile("(?i)filename\\s*=\\s*(?:\"([^\"]+)\"|([^;]+))").matcher(disposition);if(plain.find())n=plain.group(1)!=null?plain.group(1):plain.group(2).trim();}
        }
        if(n==null){String p=url.getPath();n=p.substring(p.lastIndexOf('/')+1);}
        return displayName(n);
    }
    private static String digest(byte[] bytes)throws Exception{
        byte[] hash=MessageDigest.getInstance("SHA-256").digest(bytes);StringBuilder out=new StringBuilder();for(byte b:hash)out.append(String.format(Locale.US,"%02x",b&255));return out.toString();
    }
    private static File directory(File filesDir)throws IOException{
        File parent=filesDir.getCanonicalFile(),dir=new File(parent,"web-midi").getCanonicalFile();
        if(!dir.getParentFile().equals(parent))throw new IOException("下载缓存目录无效");
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("无法创建下载缓存");return dir;
    }
    public static String cache(File filesDir,byte[] input)throws Exception{
        if(input==null||input.length>Score.MAX_BYTES)throw new IOException("MIDI文件超过1 MiB");
        byte[] bytes=input.clone();checkMidi(bytes);String token=digest(bytes)+".mid";
        File dir=directory(filesDir),dest=new File(dir,token);
        if(!dest.getCanonicalFile().getParentFile().equals(dir))throw new IOException("下载缓存位置无效");
        if(dest.exists()){
            try{readCached(filesDir,token);return token;}
            catch(IOException damaged){/* A newly downloaded verified copy can repair damaged private cache. */}
        }
        File tmp=File.createTempFile("midi-",".tmp",dir);
        try {
            try(FileOutputStream out=new FileOutputStream(tmp)){out.write(bytes);out.getFD().sync();}
            if(dest.exists()&&!dest.delete())throw new IOException("无法替换损坏的MIDI缓存");
            if(!tmp.renameTo(dest))throw new IOException("无法完成MIDI缓存保存");return token;
        } finally {if(tmp.exists())tmp.delete();}
    }
    public static byte[] readCached(File filesDir,String token)throws Exception{
        if(token==null||!token.matches("[0-9a-f]{64}\\.mid"))throw new IOException("下载缓存标识无效");
        File dir=directory(filesDir),file=new File(dir,token).getCanonicalFile();
        if(!file.getParentFile().equals(dir)||!file.isFile())throw new IOException("已下载MIDI不存在，请重新下载");
        byte[] bytes;try(InputStream in=new FileInputStream(file)){bytes=read(in,null);}
        if(!token.equals(digest(bytes)+".mid"))throw new IOException("MIDI缓存校验失败，请重新下载");
        checkMidi(bytes);return bytes;
    }
}
