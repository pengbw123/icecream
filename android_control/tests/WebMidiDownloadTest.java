package com.gowin.instrument;
import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;

/** Behavioral checks for authenticated downloads; no account or paid website required. */
public final class WebMidiDownloadTest {
    static int checks;
    static void ok(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    interface Work{void run()throws Exception;}
    static void reject(Work w,String label)throws Exception{checks++;try{w.run();}catch(IOException e){return;}throw new AssertionError(label);}
    static final class Response extends HttpURLConnection {
        final byte[] bytes;final int code;final Map<String,List<String>> headers=new HashMap<String,List<String>>();
        final Map<String,String> request=new HashMap<String,String>();boolean disconnected;
        Response(String url,int code,byte[] bytes)throws Exception{super(new URL(url));this.code=code;this.bytes=bytes;}
        Response header(String key,String value){headers.put(key,Collections.singletonList(value));return this;}
        public void disconnect(){disconnected=true;}public boolean usingProxy(){return false;}public void connect(){}
        public int getResponseCode(){return code;}public InputStream getInputStream(){return new ByteArrayInputStream(bytes);}
        public Map<String,List<String>> getHeaderFields(){return headers;}public String getHeaderField(String key){List<String> v=headers.get(key);return v==null?null:v.get(0);}
        public void setRequestProperty(String key,String value){request.put(key,value);}
    }
    static final class Network implements WebMidiDownload.Connections {
        final List<Response> responses=new ArrayList<Response>();final List<String> urls=new ArrayList<String>();
        Network add(Response response){responses.add(response);return this;}
        public HttpURLConnection open(URL url)throws IOException{urls.add(url.toString());if(urls.size()>responses.size())throw new IOException("unexpected connection");return responses.get(urls.size()-1);}
    }
    static WebMidiDownload.Result fetch(Network n,WebMidiDownload.Cookies cookies,WebMidiDownload.Token token)throws Exception{
        return WebMidiDownload.fetch("https://site.example/download?key=a%2Fb%3D#player","TestPhone","https://site.example/Midi-3.html",cookies,token,n);
    }
    public static void main(String[] args)throws Exception{
        final byte[] midi=Files.readAllBytes(Paths.get(args[1]));final File dir=new File(args[0]);dir.mkdirs();
        final List<String> got=new ArrayList<String>(),put=new ArrayList<String>();
        WebMidiDownload.Cookies cookies=new WebMidiDownload.Cookies(){
            public String get(String url){got.add(url);return url.contains("site.example")?"session=own":"cdn=download";}
            public void put(String url,String cookie){put.add(url+"|"+cookie);}
        };
        Response first=new Response("https://site.example/download",302,new byte[0]).header("Location","https://cdn.example/files/score.mid?sig=x%2Fy").header("Set-Cookie","token=ready; Secure");
        Response last=new Response("https://cdn.example/files/score.mid",200,midi).header("Content-Disposition","attachment; filename*=UTF-8''%E6%9B%B2%E8%B0%B1.mid");
        Network n=new Network().add(first).add(last);WebMidiDownload.Result r=fetch(n,cookies,new WebMidiDownload.Token());
        ok(Arrays.equals(midi,r.bytes),"download bytes");ok(r.name.equals("曲谱.mid"),"UTF8 file name");
        ok(n.urls.get(0).equals("https://site.example/download?key=a%2Fb%3D"),"preserve signed query and strip fragment");
        ok(n.urls.get(1).endsWith("?sig=x%2Fy"),"preserve redirected signature");
        ok(first.request.get("Cookie").equals("session=own")&&last.request.get("Cookie").equals("cdn=download"),"cookies evaluated per host");
        ok(first.request.containsKey("Referer")&&!last.request.containsKey("Referer"),"no cross-origin referer forwarding");
        ok(got.size()==2&&put.size()==1,"browser cookie roundtrip");ok(first.disconnected&&last.disconnected,"disconnect every hop");
        final Network none=new Network();
        reject(new Work(){public void run()throws Exception{WebMidiDownload.fetch("http://site.example/file.mid",null,null,null,new WebMidiDownload.Token(),none);}},"reject HTTP");
        reject(new Work(){public void run()throws Exception{WebMidiDownload.fetch("https://user:pass@site.example/file.mid",null,null,null,new WebMidiDownload.Token(),none);}},"reject embedded credentials");
        reject(new Work(){public void run()throws Exception{WebMidiDownload.fetch("https://site.example:444/file.mid",null,null,null,new WebMidiDownload.Token(),none);}},"reject unsupported port");
        final WebMidiDownload.Token cancelled=new WebMidiDownload.Token();cancelled.cancelled=true;
        reject(new Work(){public void run()throws Exception{fetch(none,null,cancelled);}},"cancel before request");ok(none.urls.isEmpty(),"no network on invalid/cancelled input");
        final Network forbidden=new Network().add(new Response("https://site.example/x",403,new byte[0]));
        reject(new Work(){public void run()throws Exception{fetch(forbidden,null,new WebMidiDownload.Token());}},"VIP not logged in HTTP403");
        final Network html=new Network().add(new Response("https://site.example/x",200,"<html>please login to download MIDI</html>".getBytes("UTF-8")));
        reject(new Work(){public void run()throws Exception{fetch(html,null,new WebMidiDownload.Token());}},"login HTML rejected");
        final Network bigHeader=new Network().add(new Response("https://site.example/x",200,midi).header("Content-Length","1048577"));
        reject(new Work(){public void run()throws Exception{fetch(bigHeader,null,new WebMidiDownload.Token());}},"size header bound");
        final Network bigBody=new Network().add(new Response("https://site.example/x",200,new byte[Score.MAX_BYTES+1]));
        reject(new Work(){public void run()throws Exception{fetch(bigBody,null,new WebMidiDownload.Token());}},"stream size bound");
        final Network downgrade=new Network().add(new Response("https://site.example/x",302,new byte[0]).header("Location","http://cdn.example/file.mid"));
        reject(new Work(){public void run()throws Exception{fetch(downgrade,null,new WebMidiDownload.Token());}},"reject HTTPS downgrade");
        final Network loop=new Network();for(int i=0;i<6;i++)loop.add(new Response("https://site.example/x",302,new byte[0]).header("Location","/again"));
        reject(new Work(){public void run()throws Exception{fetch(loop,null,new WebMidiDownload.Token());}},"bounded redirects");ok(loop.urls.size()==6,"redirect bound count");
        final Network injection=new Network().add(new Response("https://site.example/x",200,midi));
        reject(new Work(){public void run()throws Exception{WebMidiDownload.fetch("https://site.example/x","bad\r\nCookie: leak",null,null,new WebMidiDownload.Token(),injection);}},"request header injection");
        final String token=WebMidiDownload.cache(dir,midi);ok(Arrays.equals(midi,WebMidiDownload.readCached(dir,token)),"persisted exact MIDI");
        ok(WebMidiDownload.cache(dir,midi).equals(token),"idempotent cache");
        reject(new Work(){public void run()throws Exception{WebMidiDownload.readCached(dir,"../../secret.mid");}},"no arbitrary file path");
        byte[] damaged=midi.clone();damaged[damaged.length-1]^=1;Files.write(new File(new File(dir,"web-midi"),token).toPath(),damaged);
        reject(new Work(){public void run()throws Exception{WebMidiDownload.readCached(dir,token);}},"cache tamper detected");
        ok(WebMidiDownload.cache(dir,midi).equals(token)&&Arrays.equals(midi,WebMidiDownload.readCached(dir,token)),"redownload repairs damaged private cache");
        ok(WebMidiDownload.displayName("../evil/name\n.mid").indexOf('/')<0,"safe display name");
        System.out.println("WEB_MIDI_TEST_PASS "+checks+" checks");
    }
}
