package com.gowin.instrument;

import java.io.*;
import java.net.*;
import java.util.*;
import java.util.regex.*;

/** Native catalog metadata from Mutopia's bounded HTTPS listings, without executing HTML/scripts. */
public final class ScoreCatalog {
    private ScoreCatalog(){}
    public static final String BASE="https://www.mutopiaproject.org/cgibin/make-table.cgi";
    public static final class Entry {
        public final String name,composer,instrument,license,url,page;
        public Entry(String name,String composer,String instrument,String license,String url,String page){
            this.name=name;this.composer=composer;this.instrument=instrument;this.license=license;this.url=url;this.page=page;
        }
        public String toString(){return name+"\n"+composer+" · "+instrument+"\n"+license;}
    }
    public static final class Page {
        public final List<Entry> entries;public final boolean hasNext;public final int offset;public final String url;
        Page(List<Entry> e,boolean next,int offset,String url){entries=Collections.unmodifiableList(new ArrayList<Entry>(e));hasNext=next;this.offset=offset;this.url=url;}
    }
    private static final Pattern TABLE=Pattern.compile("<table\\b[^>]*class=[\"'][^\"']*result-table[^\"']*[\"'][^>]*>(.*?)</table>",Pattern.CASE_INSENSITIVE|Pattern.DOTALL);
    private static final Pattern CELL=Pattern.compile("<td\\b[^>]*>(.*?)</td>",Pattern.CASE_INSENSITIVE|Pattern.DOTALL);
    private static final Pattern LINK=Pattern.compile("<a\\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",Pattern.CASE_INSENSITIVE|Pattern.DOTALL);
    public static String searchUrl(String keyword,boolean piano,int offset)throws IOException{
        if(offset<0||offset>10000||offset%10!=0)throw new IOException("曲库页码无效");
        String key=keyword==null?"":keyword.trim();if(key.length()>120)throw new IOException("搜索词过长");
        String[] chinese={"致爱丽丝","欢乐颂","绿袖子","小步舞曲","巴赫","贝多芬","莫扎特","卡农"};
        String[] english={"Elise","ode","Greensleeves","Minuet","Bach","Beethoven","Mozart","Canon"};
        for(int i=0;i<chinese.length;i++)if(key.equals(chinese[i])){key=english[i];break;}
        return BASE+"?Instrument="+(piano?"Piano":"")+"&searchingfor="+URLEncoder.encode(key,"UTF-8")+"&startat="+offset;
    }
    public static Page fetch(String keyword,boolean piano,int offset,ScoreDownload.CancelToken cancel)throws IOException{
        String url=searchUrl(keyword,piano,offset);
        byte[] bytes=ScoreDownload.fetchBytes(url,cancel,null);cancel.check();
        return parse(new String(bytes,"UTF-8"),url,offset);
    }
    private static String official(String base,String raw,boolean midi)throws IOException{
        URL url=ScoreDownload.httpsUrl(new URL(new URL(base),entities(raw)).toExternalForm());
        if(!"www.mutopiaproject.org".equalsIgnoreCase(url.getHost())||url.getPort()!=-1)throw new IOException("曲库返回了非官方地址");
        if(midi&&(!url.getPath().startsWith("/ftp/")||!url.getPath().toLowerCase(Locale.US).matches(".*\\.midi?$")))throw new IOException("曲库MIDI链接无效");
        if(!midi&& !url.getPath().equals("/cgibin/piece-info.cgi"))throw new IOException("曲目来源页无效");
        return url.toExternalForm();
    }
    public static Page parse(String html,String url,int offset)throws IOException{
        if(offset<0||offset>10000||offset%10!=0)throw new IOException("曲库页码无效");
        if(html.length()>Score.MAX_BYTES)throw new IOException("曲库页面过大");
        URL listing=ScoreDownload.httpsUrl(url);if(!"www.mutopiaproject.org".equalsIgnoreCase(listing.getHost())||listing.getPort()!=-1||!listing.getPath().equals("/cgibin/make-table.cgi"))throw new IOException("曲库地址无效");
        List<Entry> entries=new ArrayList<Entry>();Set<String> seen=new HashSet<String>();Matcher tables=TABLE.matcher(html);
        int tableCount=0;
        while(tables.find()){
            if(++tableCount>10)throw new IOException("曲库页面条目过多");
            String block=tables.group(1);List<String> cells=new ArrayList<String>();Matcher cm=CELL.matcher(block);while(cm.find())cells.add(text(cm.group(1)));
            if(cells.size()<12)throw new IOException("曲库页面格式已变更，请稍后重试");
            String midi=null,page=null;Matcher lm=LINK.matcher(block);
            while(lm.find()){
                String href=entities(lm.group(1));String label=text(lm.group(2));
                if(label.toLowerCase(Locale.US).matches("\\.midi? file"))midi=official(url,href,true);
                if(label.equalsIgnoreCase("More Information"))page=official(url,href,false);
            }
            String license=cells.get(9);
            if(midi==null||page==null)continue;
            if(!(license.equals("Public Domain")||license.startsWith("Creative Commons ")))continue;
            if(seen.add(page))entries.add(new Entry(cells.get(0),cells.get(1),cells.get(4),license,midi,page));
        }
        if(!html.contains("Music Listing")||(tableCount==0&&!html.contains("no matches were found")))throw new IOException("曲库页面格式已变更，请稍后重试");
        boolean next=false;Matcher links=LINK.matcher(html);while(links.find())if(text(links.group(2)).matches("(?i)Next\\s+10")){
            URL n=ScoreDownload.httpsUrl(new URL(listing,entities(links.group(1))).toExternalForm());
            if(!n.getHost().equalsIgnoreCase(listing.getHost())||n.getPort()!=-1||!n.getPath().equals(listing.getPath()))throw new IOException("曲库分页地址无效");
            next=true;
        }
        return new Page(entries,next,offset,url);
    }
    private static String text(String html){return entities(html.replaceAll("(?is)<script\\b.*?</script>","").replaceAll("(?is)<[^>]+>"," ")).replaceAll("\\s+"," ").trim();}
    private static String entities(String s){
        Matcher m=Pattern.compile("&#(x[0-9a-fA-F]+|[0-9]+);").matcher(s);StringBuffer b=new StringBuffer();
        while(m.find()){try{String n=m.group(1);int cp=Integer.parseInt(n.startsWith("x")?n.substring(1):n,n.startsWith("x")?16:10);m.appendReplacement(b,Matcher.quoteReplacement(Character.isValidCodePoint(cp)?new String(Character.toChars(cp)):"?"));}catch(RuntimeException ex){m.appendReplacement(b,"?");}}
        m.appendTail(b);return b.toString().replace("&nbsp;"," ").replace("&quot;","\"").replace("&#39;","'").replace("&apos;","'").replace("&lt;","<").replace("&gt;",">").replace("&amp;","&");
    }
}
