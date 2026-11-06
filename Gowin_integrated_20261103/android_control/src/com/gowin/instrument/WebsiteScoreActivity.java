package com.gowin.instrument;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.os.*;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import java.io.*;
import java.util.concurrent.*;

/** In-app website browsing; downloads use only the user's normal website session. */
public final class WebsiteScoreActivity extends Activity {
    public static final int REQUEST=1012,EXPORT_MIDI=1013;
    public static final String EXTRA_TOKEN="web_midi_token",EXTRA_NAME="web_midi_name";
    private static final String HOME="https://www.everyonepiano.cn/",PREFS="web_midi_recent";
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private WebView web;private TextView host,status,detail;private ProgressBar progress;
    private Button load,save,recent,cancel;private LinearLayout resultRow;
    private volatile boolean closed;private boolean busy,saving,compatible;private int epoch;
    private WebMidiDownload.Token task;
    private String cachedToken,resultName,saveToken,saveName;
    @Override protected void onCreate(Bundle state){
        super.onCreate(state);setTitle("人人钢琴 · 网页曲库");
        if(state!=null){saveToken=state.getString("saveToken");saveName=state.getString("saveName");saving=saveToken!=null;}
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);
        LinearLayout controls=new LinearLayout(this);controls.setOrientation(LinearLayout.VERTICAL);
        ScrollView top=new ScrollView(this);top.addView(controls);
        root.addView(top,new LinearLayout.LayoutParams(-1,dp(205)));
        TextView title=UiTheme.section(this,"人人钢琴");controls.addView(title);
        controls.addView(UiTheme.caption(this,"登录自己的账号下载 MIDI，曲目会自动加入手机曲库。"));
        LinearLayout nav=row(controls);
        UiTheme.ghost(button(nav,"网站首页",new Runnable(){public void run(){web.loadUrl(HOME);}}));UiTheme.ghost(button(nav,"网页后退",new Runnable(){public void run(){if(web.canGoBack())web.goBack();}}));
        LinearLayout nav2=row(controls);
        UiTheme.ghost(button(nav2,"返回控制页",new Runnable(){public void run(){finish();}}));UiTheme.ghost(button(nav2,"退出网站账号",new Runnable(){public void run(){logout();}}));
        host=UiTheme.caption(this,"");controls.addView(host);
        status=UiTheme.body(this,"请在网页登录后选择MIDI下载。");controls.addView(status);
        detail=UiTheme.caption(this,"");controls.addView(detail);
        LinearLayout tasks=row(controls);
        recent=button(tasks,"读取最近下载",new Runnable(){public void run(){readRecent();}});cancel=button(tasks,"取消下载",new Runnable(){public void run(){cancelTask();}});
        resultRow=row(controls);
        load=button(resultRow,"载入到曲谱区",new Runnable(){public void run(){
            if(!busy&&!saving&&compatible&&cachedToken!=null){
                setResult(RESULT_OK,new Intent().putExtra(EXTRA_TOKEN,cachedToken).putExtra(EXTRA_NAME,resultName));finish();
            }
        }});
        save=button(resultRow,"另存MIDI到手机",new Runnable(){public void run(){save();}});
        progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);UiTheme.progress(progress);root.addView(progress);
        web=new WebView(this);root.addView(web,new LinearLayout.LayoutParams(-1,0,1));setContentView(root);
        UiTheme.button(load,UiTheme.Style.PRIMARY);UiTheme.button(save,UiTheme.Style.SECONDARY);
        UiTheme.button(recent,UiTheme.Style.SECONDARY);UiTheme.ghost(cancel);
        controls.setPadding(dp(12),dp(8),dp(12),dp(8));root.setBackgroundColor(UiTheme.BG);
        UiTheme.systemBars(this);
        // Keep successful download actions visible instead of burying them in the toolbar scroller.
        controls.removeView(resultRow);root.addView(resultRow,1);
        resultRow.setPadding(dp(12),dp(6),dp(12),dp(6));resultRow.setBackgroundColor(UiTheme.PANEL);
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener(){public WindowInsets onApplyWindowInsets(View view,WindowInsets insets){
            int bottom=Build.VERSION.SDK_INT>=30?insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.ime()).bottom:insets.getSystemWindowInsetBottom();
            int topInset=Build.VERSION.SDK_INT>=30?insets.getInsets(WindowInsets.Type.systemBars()).top:insets.getSystemWindowInsetTop();
            view.setPadding(insets.getSystemWindowInsetLeft(),topInset,insets.getSystemWindowInsetRight(),bottom);return insets;
        }});
        configure();refresh();
        boolean restored=state!=null&&web.restoreState(state)!=null;
        if(!restored)web.loadUrl(HOME);
    }
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    private LinearLayout row(LinearLayout parent){LinearLayout r=new LinearLayout(this);parent.addView(r);return r;}
    private Button button(LinearLayout row,String text,final Runnable action){Button b=new Button(this);b.setText(text);b.setTextSize(12);b.setOnClickListener(new View.OnClickListener(){public void onClick(View v){action.run();}});row.addView(b,new LinearLayout.LayoutParams(0,-2,1));return b;}
    private void configure(){
        WebSettings s=web.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setAllowFileAccessFromFileURLs(false);s.setAllowUniversalAccessFromFileURLs(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);s.setGeolocationEnabled(false);
        s.setJavaScriptCanOpenWindowsAutomatically(false);s.setSupportMultipleWindows(false);
        CookieManager.getInstance().setAcceptCookie(true);CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);
        web.setWebChromeClient(new WebChromeClient(){public void onProgressChanged(WebView w,int value){if(!closed){progress.setProgress(value);progress.setVisibility(value<100?View.VISIBLE:View.GONE);}}});
        web.setWebViewClient(new WebViewClient(){
            public boolean shouldOverrideUrlLoading(WebView w,String url){return navigate(url);}
            public boolean shouldOverrideUrlLoading(WebView w,WebResourceRequest request){return request.isForMainFrame()&&navigate(request.getUrl().toString());}
            public void onPageStarted(WebView w,String url,Bitmap icon){if(!closed)host.setText("当前网站："+Uri.parse(url).getHost());}
            public void onReceivedSslError(WebView w,SslErrorHandler handler,SslError error){handler.cancel();if(!closed)status.setText("网页证书校验失败，请检查手机时间与网络。");}
            public void onReceivedError(WebView w,WebResourceRequest r,WebResourceError e){if(!closed&&r.isForMainFrame())status.setText("网页加载失败（"+e.getErrorCode()+"），可点网站首页重试。");}
        });
        web.setDownloadListener(new DownloadListener(){public void onDownloadStart(String url,String agent,String disposition,String mime,long length){download(url,agent,web.getUrl(),web.getTitle());}});
    }
    private boolean navigate(String url){
        if(closed)return true;
        Uri u=Uri.parse(url);String scheme=u.getScheme();
        if("https".equalsIgnoreCase(scheme)&&u.getHost()!=null&&u.getUserInfo()==null)return false;
        if("http".equalsIgnoreCase(scheme)&&u.getHost()!=null&&u.getUserInfo()==null){web.loadUrl(u.buildUpon().scheme("https").build().toString());return true;}
        status.setText("这个链接无法在网页曲库内打开，请使用网站的HTTPS页面。");return true;
    }
    private int begin(){busy=true;compatible=false;cachedToken=resultName=null;task=new WebMidiDownload.Token();detail.setText("");refresh();return ++epoch;}
    private void download(final String url,final String agent,final String referer,final String pageTitle){
        if(closed||busy||saving){status.setText("请等待当前下载或保存结束。");return;}
        final int generation=begin();final WebMidiDownload.Token token=task;status.setText("正在下载MIDI…");
        worker.execute(new Runnable(){public void run(){
            try {
                WebMidiDownload.Cookies cookies=new WebMidiDownload.Cookies(){
                    public String get(String u){return CookieManager.getInstance().getCookie(u);}
                    public void put(String u,String value){if(!token.cancelled)CookieManager.getInstance().setCookie(u,value);}
                };
                WebMidiDownload.Result r=WebMidiDownload.fetch(url,agent,referer,cookies,token);
                if(token.cancelled)return;
                String name=WebMidiDownload.nameForPage(r.name,pageTitle);
                String cache=ScoreLibrary.save(WebsiteScoreActivity.this,r.bytes,name);
                show(generation,token,cache,name,r.bytes,true);
            }catch(Exception e){failed(generation,token,e);}
        }});
    }
    private void readRecent(){
        if(closed||busy||saving)return;
        final String cache=getSharedPreferences(PREFS,0).getString("last_token",null);
        final String name=WebMidiDownload.nameForPage(getSharedPreferences(PREFS,0).getString("last_name","网页下载曲谱"),null);
        if(cache==null){status.setText("尚无下载记录，请先在网页下载MIDI。");return;}
        final int generation=begin();final WebMidiDownload.Token token=task;status.setText("正在读取最近下载…");
        worker.execute(new Runnable(){public void run(){try{show(generation,token,cache,name,WebMidiDownload.readCached(getFilesDir(),cache),false);}catch(Exception e){failed(generation,token,e);}}});
    }
    private void show(final int generation,final WebMidiDownload.Token token,final String cache,final String name,byte[] bytes,final boolean newDownload){
        boolean fits=false;String description;
        try{Score s=Score.fromMidi(name,bytes);fits=true;description=s.events.size()+"事件，"+(s.durationMs/1000.0)+"秒，最大"+s.peakVoices+"复音。";}
        catch(RuntimeException e){description="文件已下载，无法载入曲谱："+safeError(e)+"。可以另存文件。";}
        final boolean valid=fits;final String text=description;
        main.post(new Runnable(){public void run(){if(closed||generation!=epoch||token.cancelled)return;busy=false;task=null;cachedToken=cache;resultName=WebMidiDownload.displayName(name);compatible=valid;
            if(newDownload)getSharedPreferences(PREFS,0).edit().putString("last_token",cache).putString("last_name",resultName).apply();
            status.setText("MIDI已保存到手机曲库："+resultName);detail.setText(text+" 返回曲谱页可在“我的 MIDI 曲库”再次打开。");refresh();
        }});
    }
    private void failed(final int generation,final WebMidiDownload.Token token,Exception e){final String error=safeError(e);main.post(new Runnable(){public void run(){if(closed||generation!=epoch||token.cancelled)return;busy=false;task=null;status.setText("下载/读取失败："+error);refresh();}});}
    private void cancelTask(){epoch++;if(task!=null)task.cancelled=true;task=null;busy=false;status.setText("已取消，最近下载记录保留。");refresh();}
    private void refresh(){boolean idle=!closed&&!busy&&!saving;load.setEnabled(idle&&compatible);save.setEnabled(idle&&cachedToken!=null);recent.setEnabled(idle);cancel.setEnabled(!closed&&busy);resultRow.setVisibility(cachedToken==null?View.GONE:View.VISIBLE);}
    private void save(){
        if(closed||busy||saving||cachedToken==null)return;
        saveToken=cachedToken;saveName=resultName;saving=true;refresh();
        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("audio/midi").addCategory(Intent.CATEGORY_OPENABLE).putExtra(Intent.EXTRA_TITLE,WebMidiDownload.displayName(saveName));
        try{startActivityForResult(intent,EXPORT_MIDI);}catch(RuntimeException e){saving=false;saveToken=saveName=null;status.setText("无法打开系统文件保存器。");refresh();}
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);if(request!=EXPORT_MIDI||closed)return;
        final String token=saveToken;saveToken=saveName=null;
        if(result!=RESULT_OK||data==null||data.getData()==null||token==null){saving=false;status.setText("已取消另存。");refresh();return;}
        final Uri uri=data.getData();status.setText("正在另存MIDI…");
        worker.execute(new Runnable(){public void run(){String error=null;try{
            byte[] bytes=WebMidiDownload.readCached(getFilesDir(),token);
            if(closed||Thread.currentThread().isInterrupted())return;
            try(OutputStream out=getContentResolver().openOutputStream(uri,"wt")){
                if(out==null)throw new IOException("无法打开保存位置");
                for(int at=0;at<bytes.length;at+=4096){if(closed||Thread.currentThread().isInterrupted())throw new IOException("保存已中止");out.write(bytes,at,Math.min(4096,bytes.length-at));}out.flush();
            }
        }catch(Exception e){error=safeError(e);}final String problem=error;main.post(new Runnable(){public void run(){if(closed)return;saving=false;status.setText(problem==null?"已另存MIDI，下载缓存保留。":"另存失败："+problem);refresh();}});}});
    }
    private void logout(){
        if(closed||saving)return;cancelTask();web.stopLoading();
        CookieManager.getInstance().removeAllCookies(new ValueCallback<Boolean>(){public void onReceiveValue(Boolean value){if(closed)return;CookieManager.getInstance().flush();WebStorage.getInstance().deleteAllData();web.clearCache(true);web.clearHistory();web.loadUrl(HOME);status.setText("已退出网站登录，已下载MIDI保留。");}});
    }
    private static String safeError(Exception e){String m=e.getMessage();if(m==null)m=e.getClass().getSimpleName();m=m.replaceAll("https?://\\S+","[下载地址]").replace('\n',' ');return m.length()>250?m.substring(0,250):m;}
    @Override protected void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);web.saveState(state);state.putString("saveToken",saveToken);state.putString("saveName",saveName);}
    @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override protected void onDestroy(){closed=true;epoch++;if(task!=null)task.cancelled=true;worker.shutdownNow();main.removeCallbacksAndMessages(null);
        if(web!=null){web.setDownloadListener(null);web.stopLoading();((ViewGroup)web.getParent()).removeView(web);web.destroy();web=null;}super.onDestroy();}
}
