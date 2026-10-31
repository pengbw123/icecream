package com.gowin.instrument;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;

/** Deterministic HTTP failure/cache tests plus an opt-in real HTTPS catalog check. */
public final class ScoreDownloadTest {
    private static int checks,requests;
    private interface Action {void run() throws Exception;}
    private static void ok(boolean b,String label){checks++;if(!b)throw new AssertionError(label);}
    private static void reject(Action action,String label)throws Exception{
        checks++;try{action.run();}catch(IOException expected){return;}throw new AssertionError(label);
    }
    private static final class Response {
        int code=200;byte[] bytes;String location,encoding;long length=-1;
        Response(byte[] bytes){this.bytes=bytes;}
    }
    private static final Map<String,Response> responses=new HashMap<String,Response>();
    private static void mock(){URL.setURLStreamHandlerFactory(new URLStreamHandlerFactory(){public URLStreamHandler createURLStreamHandler(String protocol){
        if(!"https".equals(protocol))return null;
        return new URLStreamHandler(){protected URLConnection openConnection(URL url)throws IOException{
            requests++;final Response r=responses.get(url.toExternalForm());if(r==null)throw new IOException("Unexpected request "+url);
            return new HttpURLConnection(url){
                public void connect(){}public void disconnect(){}public boolean usingProxy(){return false;}
                public int getResponseCode(){return r.code;}
                public String getHeaderField(String name){if("Location".equals(name))return r.location;if("Content-Length".equals(name))return r.length==-1?null:Long.toString(r.length);return null;}
                public String getContentEncoding(){return r.encoding;}
                public InputStream getInputStream(){return new ByteArrayInputStream(r.bytes);}
            };
        }};
    }});}
    private static ScoreDownload.Result download(String url,File dir,String hash,ScoreDownload.CancelToken token)throws IOException{
        return ScoreDownload.download("test",url,hash,dir,token,null);
    }
    public static void main(String[] args)throws Exception{
        final File dir=new File(args[0]);if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("Test directory");
        final byte[] midi=Files.readAllBytes(Paths.get(args[1]));final String hash=ScoreDownload.sha256(midi);
        if(args.length>2&&"--live".equals(args[2])){
            String[] urls={"https://www.mutopiaproject.org/ftp/BeethovenLv/ode/ode.mid","https://www.mutopiaproject.org/ftp/BeethovenLv/WoO59/fur_Elise_WoO59/fur_Elise_WoO59.mid"};
            String[] hashes={"FB1604C08C865B275B464D74E5A7C526FF1A8ACCCDF9853CB92F0778DAAED14B","1C12C21C7BBF4CF163896732672648A69D497636059837ABD153C71ABE50215A"};
            for(int i=0;i<urls.length;i++){
                ScoreDownload.Result r=download(urls[i],dir,hashes[i],new ScoreDownload.CancelToken());
                ok(ScoreDownload.sha256(r.bytes).equalsIgnoreCase(hashes[i]),"live SHA256");
                ScoreDownload.Result cached=ScoreDownload.loadCached("cached",urls[i],hashes[i],dir);
                ok(Arrays.equals(r.bytes,cached.bytes),"live offline cache roundtrip");
                System.out.println("LIVE_CATALOG_OK events="+r.score.events.size()+" bytes="+r.bytes.length+" SHA256="+hashes[i]);
            }
            System.out.println("LIVE_DOWNLOAD_TEST_OK checks="+checks);return;
        }
        mock();final String url="https://unit.test/score.mid";responses.put(url,new Response(midi));
        ScoreDownload.Result good=download(url,dir,hash,new ScoreDownload.CancelToken());
        ok(good.file.isFile()&&Arrays.equals(good.bytes,midi),"valid MIDI cached");
        int before=requests;ScoreDownload.Result cached=ScoreDownload.loadCached("cache",url,hash,dir);
        ok(requests==before&&Arrays.equals(cached.bytes,midi),"cache is entirely offline");
        responses.put(url,new Response("<html>Not MIDI</html>".getBytes("UTF-8")));
        reject(()->download(url,dir,null,new ScoreDownload.CancelToken()),"reject HTML");
        ok(Arrays.equals(Files.readAllBytes(good.file.toPath()),midi),"invalid refresh preserves old cache");
        responses.put(url,new Response(midi));
        reject(()->download(url,dir,"0000000000000000000000000000000000000000000000000000000000000000",new ScoreDownload.CancelToken()),"hash mismatch");
        Response error=new Response(midi);error.code=503;responses.put(url,error);
        reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"HTTP failure");
        Response truncated=new Response(midi);truncated.length=midi.length+5;responses.put(url,truncated);
        reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"truncated length");
        Response huge=new Response(midi);huge.length=Score.MAX_BYTES+1;responses.put(url,huge);
        reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"oversize advertised");
        responses.put(url,new Response(new byte[Score.MAX_BYTES+1]));
        reject(()->download(url,dir,null,new ScoreDownload.CancelToken()),"oversize streamed");
        Response encoded=new Response(midi);encoded.encoding="gzip";responses.put(url,encoded);
        reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"unexpected compression");
        Response redirect=new Response(new byte[0]);redirect.code=302;redirect.location="https://unit.test/final.mid";
        responses.put(url,redirect);responses.put(redirect.location,new Response(midi));
        ok(Arrays.equals(download(url,dir,hash,new ScoreDownload.CancelToken()).bytes,midi),"HTTPS redirect");
        redirect.location="http://unit.test/final.mid";reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"no HTTPS downgrade");
        redirect.location=url;reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"redirect loop bounded");
        redirect.location=null;reject(()->download(url,dir,hash,new ScoreDownload.CancelToken()),"redirect missing location");
        responses.put(url,new Response(midi));final ScoreDownload.CancelToken cancelled=new ScoreDownload.CancelToken();cancelled.cancel();before=requests;
        reject(()->download(url,dir,hash,cancelled),"cancel before network");ok(requests==before,"cancel opens no connection");
        final ScoreDownload.CancelToken midCancel=new ScoreDownload.CancelToken();
        reject(()->ScoreDownload.download("test",url,hash,dir,midCancel,(received,total)->midCancel.cancel()),"cancel while streaming");
        ok(Arrays.equals(Files.readAllBytes(good.file.toPath()),midi),"cancel preserves previous cache");
        for(final String bad:new String[]{"http://unit.test/a.mid","https://user:pass@unit.test/a.mid","https://unit.test/a.mid#fragment","https://unit.test/a b.mid","nonsense"})
            reject(()->ScoreDownload.httpsUrl(bad),"bad URL");
        reject(()->ScoreDownload.readBounded(new ByteArrayInputStream(midi),-2,new ScoreDownload.CancelToken(),null),"negative declared length");
        reject(()->ScoreDownload.loadCached("missing","https://unit.test/missing.mid",null,dir),"missing cache");
        Files.write(good.file.toPath(),new byte[]{1,2,3});reject(()->ScoreDownload.loadCached("bad",url,hash,dir),"corrupt cache rejected");
        ok(download(url,dir,hash,new ScoreDownload.CancelToken()).score.events.size()>0,"valid redownload repairs corrupt cache");
        ok(dir.listFiles((parent,name)->name.endsWith(".part")||name.endsWith(".bak")).length==0,"no abandoned temp/backup files");
        System.out.println("DOWNLOAD_TEST_OK checks="+checks+" requests="+requests);
    }
}
