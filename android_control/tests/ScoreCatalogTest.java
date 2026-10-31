package com.gowin.instrument;

import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;

/** Actual listing fixtures plus optional end-to-end real HTTPS search/download/cache. */
public final class ScoreCatalogTest {
    private static int checks;
    private interface Action {void run()throws Exception;}
    private static void ok(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    private static void reject(Action action,String label)throws Exception{
        checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError(label);
    }
    private static String read(Path path)throws IOException{return new String(Files.readAllBytes(path),"UTF-8").replace("\ufeff","");}
    public static void main(String[] args)throws Exception{
        Path fixtures=Paths.get(args[0]);
        String url=ScoreCatalog.searchUrl("",true,0);
        final String html=read(fixtures.resolve("catalog-list.html"));
        final String empty=read(fixtures.resolve("catalog-empty.html"));
        ScoreCatalog.Page first=ScoreCatalog.parse(html,url,0);
        ok(first.entries.size()==10,"real first page has ten entries");
        ok(first.hasNext&&first.offset==0,"real next-page marker");
        ScoreCatalog.Entry entry=first.entries.get(0);
        ok(entry.name.equals("Vocalise № 1"),"unicode title");
        ok(entry.composer.contains("Abt")&&entry.instrument.equals("for Voice, Piano"),"author/instrument");
        ok(entry.license.equals("Public Domain"),"license from listing");
        ok(entry.page.equals("https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=2247"),"relative source URL");
        ok(entry.url.equals("https://www.mutopiaproject.org/ftp/AbtF/Vocalise1/Vocalise1.mid"),"official MIDI URL");
        try{first.entries.clear();throw new AssertionError("modifiable list");}catch(UnsupportedOperationException expected){checks++;}
        ok(!ScoreCatalog.parse(html.replace("Next 10","End"),url,0).hasNext,"full final page does not invent next");
        ok(ScoreCatalog.parse(empty,url,0).entries.isEmpty(),"actual no-match response");
        String next="<a href='make-table.cgi?startat=10&amp;Instrument=Piano'>Next 10</a>";
        ok(ScoreCatalog.parse(empty+next,url,0).hasNext,"empty page can still have next");
        ok(ScoreCatalog.searchUrl("致爱丽丝",true,0).contains("searchingfor=Elise"),"Chinese alias");
        ok(ScoreCatalog.searchUrl("巴赫",false,20).contains("Instrument=&searchingfor=Bach&startat=20"),"all-instruments pagination");
        ok(ScoreCatalog.searchUrl("A&B +",true,0).contains("A%26B+%2B"),"query encoded, not injected");
        reject(()->ScoreCatalog.searchUrl("",true,-10),"negative page");
        reject(()->ScoreCatalog.searchUrl("",true,11),"unaligned page");
        reject(()->ScoreCatalog.searchUrl("",true,10010),"unbounded page");
        reject(()->ScoreCatalog.searchUrl(new String(new char[121]).replace('\0','x'),true,0),"long query");
        reject(()->ScoreCatalog.parse(html,"http://www.mutopiaproject.org/cgibin/make-table.cgi",0),"no HTTP");
        reject(()->ScoreCatalog.parse(html,"https://evil.test/cgibin/make-table.cgi",0),"not other provider");
        reject(()->ScoreCatalog.parse(html,"https://www.mutopiaproject.org:444/cgibin/make-table.cgi",0),"no alternate port");
        reject(()->ScoreCatalog.parse(html,url,1),"parse validates offset");
        reject(()->ScoreCatalog.parse("<html>Music Listing <table class='new-format'>changed</table></html>",url,0),"format drift explicit");
        reject(()->ScoreCatalog.parse("<html>Login required</html>",url,0),"unexpected response");
        reject(()->ScoreCatalog.parse(new String(new char[Score.MAX_BYTES+1]),url,0),"oversized listing");
        Matcher table=Pattern.compile("<table class=\"table-bordered result-table\">.*?</table>",Pattern.DOTALL).matcher(html);
        ok(table.find(),"fixture contains actual table");
        final String block=table.group();
        reject(()->ScoreCatalog.parse("Music Listing <table class='result-table'><td>broken</td></table>",url,0),"incomplete table");
        reject(()->ScoreCatalog.parse("Music Listing "+block.replace("https://www.mutopiaproject.org/ftp/","https://evil.test/ftp/"),url,0),"no external MIDI injected");
        reject(()->ScoreCatalog.parse("Music Listing "+block.replace("https://www.mutopiaproject.org/ftp/","http://www.mutopiaproject.org/ftp/"),url,0),"no MIDI downgrade");
        reject(()->ScoreCatalog.parse(empty+next.replace("make-table.cgi","https://evil.test/make-table.cgi"),url,0),"no external next");
        StringBuilder oversized=new StringBuilder("Music Listing ");for(int i=0;i<11;i++)oversized.append(block);
        reject(()->ScoreCatalog.parse(oversized.toString(),url,0),"table count bounded even duplicates");
        ok(ScoreCatalog.parse("Music Listing "+block+block,url,0).entries.size()==1,"deduplicate source ID");
        ok(ScoreCatalog.parse("Music Listing "+block.replace("Public Domain","Unknown license"),url,0).entries.isEmpty(),"unknown license not offered");
        String cc=block.replace("Public Domain","Creative Commons Attribution-ShareAlike 4.0").replace("Vocalise № 1","A &amp; B &#x2116; &#49;<script>alert(1)</script>");
        ScoreCatalog.Entry ccEntry=ScoreCatalog.parse("Music Listing "+cc,url,0).entries.get(0);
        ok(ccEntry.license.contains("4.0")&&ccEntry.name.equals("A & B № 1"),"CC title entities/scripts");
        System.out.println("CATALOG_TEST_OK checks="+checks);
        if(args.length>1&&"--live".equals(args[1]))live(new File(args[2]));
    }
    private static void live(File cache)throws Exception{
        ScoreCatalog.Page p0=ScoreCatalog.fetch("",true,0,new ScoreDownload.CancelToken());
        ScoreCatalog.Page p1=ScoreCatalog.fetch("",true,10,new ScoreDownload.CancelToken());
        ScoreCatalog.Page elise=ScoreCatalog.fetch("致爱丽丝",true,0,new ScoreDownload.CancelToken());
        ok(p0.entries.size()==10&&p0.hasNext,"live first page");
        ok(p1.entries.size()==10&&!p1.entries.get(0).page.equals(p0.entries.get(0).page),"live next page distinct");
        ok(elise.entries.stream().anyMatch(e->e.page.endsWith("id=931")),"live Chinese alias finds known Elise");
        System.out.println("LIVE_SEARCH_OK first="+p0.entries.size()+" next="+p1.entries.size()+" elise="+elise.entries.size());
        List<ScoreCatalog.Entry> selected=new ArrayList<ScoreCatalog.Entry>();selected.add(p0.entries.get(0));
        for(ScoreCatalog.Entry e:p1.entries)if(e.name.contains("Polonaise")){selected.add(e);break;}
        ok(selected.size()==2,"second new score selected from real page");
        for(ScoreCatalog.Entry e:selected){
            ScoreDownload.Result r=ScoreDownload.download(e.name,e.url,null,cache,new ScoreDownload.CancelToken(),null);
            ScoreDownload.Result offline=ScoreDownload.loadCached(e.name,e.url,null,cache);
            ok(Arrays.equals(r.bytes,offline.bytes),"new catalog song offline roundtrip");
            System.out.println("LIVE_SONG_OK title="+e.name+" source="+e.page+" license="+e.license+" bytes="+r.bytes.length+" events="+r.score.events.size()+" voices="+r.score.peakVoices+" SHA256="+ScoreDownload.sha256(r.bytes));
        }
        System.out.println("LIVE_CATALOG_TEST_OK checks="+checks);
    }
}
