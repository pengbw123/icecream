package com.gowin.instrument;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.DialogInterface;
import android.net.Uri;
import android.os.Bundle;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import java.io.IOException;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Offline access to previously downloaded or imported MIDI files. */
public final class ScoreLibraryActivity extends Activity {
    public static final int REQUEST=1014;
    private static final int EXPORT=1015;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final List<ScoreLibrary.Entry> entries=new ArrayList<>();
    private ListView list;private TextView status;private BaseAdapter adapter;
    private boolean busy;private volatile boolean closed;private int generation;
    private String exportToken,exportName;

    @Override protected void onCreate(Bundle state){
        super.onCreate(state);
        if(state!=null){exportToken=state.getString("exportToken");exportName=state.getString("exportName");}
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(UiTheme.dp(this,16),UiTheme.dp(this,12),UiTheme.dp(this,16),UiTheme.dp(this,12));
        root.setBackgroundColor(UiTheme.BG);
        UiTheme.systemBars(this);root.addView(UiTheme.eyebrow(this,"你的音乐收藏"));UiTheme.space(root,6);
        TextView title=UiTheme.heading(this,"我的曲库");title.setTextSize(26);root.addView(title);
        root.addView(UiTheme.caption(this,"点一首曲目，开始练习或管理文件。"));
        status=UiTheme.caption(this,"正在读取曲库…");root.addView(status);UiTheme.space(root,12);
        list=new ListView(this);list.setDivider(new android.graphics.drawable.ColorDrawable(UiTheme.BG));list.setDividerHeight(UiTheme.dp(this,8));list.setVerticalScrollBarEnabled(false);
        adapter=new BaseAdapter(){
            public int getCount(){return entries.size();}
            public Object getItem(int position){return entries.get(position);}
            public long getItemId(int position){return position;}
            public View getView(int position,View convertView,ViewGroup parent){
                ScoreLibrary.Entry e=entries.get(position);
                LinearLayout row=UiTheme.row(ScoreLibraryActivity.this);row.setBackground(UiTheme.round(row,UiTheme.PANEL,16));row.setPadding(UiTheme.dp(row,14),UiTheme.dp(row,16),UiTheme.dp(row,14),UiTheme.dp(row,16));
                InstrumentGraphics.Icon icon=new InstrumentGraphics.Icon(ScoreLibraryActivity.this,1);icon.color(UiTheme.PRIMARY);icon.setBackground(UiTheme.round(icon,UiTheme.HERO,12));
                row.addView(icon,new LinearLayout.LayoutParams(UiTheme.dp(row,44),UiTheme.dp(row,44)));
                LinearLayout text=new LinearLayout(ScoreLibraryActivity.this);text.setOrientation(LinearLayout.VERTICAL);text.setPadding(UiTheme.dp(row,12),0,UiTheme.dp(row,8),0);
                TextView name=UiTheme.body(ScoreLibraryActivity.this,e.name);name.setMaxLines(2);name.setEllipsize(android.text.TextUtils.TruncateAt.END);name.setTextSize(15);text.addView(name);
                text.addView(UiTheme.caption(ScoreLibraryActivity.this,e.unnamedLegacy?"历史下载 · 可重命名":"MIDI · "+Math.max(1,(e.size+1023)/1024)+" KB · 已保存在手机"));
                row.addView(text,new LinearLayout.LayoutParams(0,-2,1));TextView arrow=UiTheme.body(ScoreLibraryActivity.this,"›");arrow.setTextColor(UiTheme.MUTED);row.addView(arrow);
                return row;
            }
        };
        list.setAdapter(adapter);list.setOnItemClickListener(new AdapterView.OnItemClickListener(){
            public void onItemClick(AdapterView<?> parent,View view,int position,long id){if(!busy&&position>=0&&position<entries.size())actions(entries.get(position));}
        });
        root.addView(list,new LinearLayout.LayoutParams(-1,0,1));
        root.addView(UiTheme.caption(this,"卸载 App 或清除数据前，请先用“另存”备份曲目。"));
        Button back=new Button(this);back.setText("返回曲谱");UiTheme.button(back,UiTheme.Style.SECONDARY);
        back.setOnClickListener(new View.OnClickListener(){public void onClick(View view){finish();}});root.addView(back);
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener(){public android.view.WindowInsets onApplyWindowInsets(View view,android.view.WindowInsets insets){
            int left=insets.getSystemWindowInsetLeft(),right=insets.getSystemWindowInsetRight();
            int top=Build.VERSION.SDK_INT>=30?insets.getInsets(android.view.WindowInsets.Type.systemBars()).top:insets.getSystemWindowInsetTop();
            int bottom=Build.VERSION.SDK_INT>=30?insets.getInsets(android.view.WindowInsets.Type.systemBars()|android.view.WindowInsets.Type.ime()).bottom:insets.getSystemWindowInsetBottom();
            view.setPadding(UiTheme.dp(view,16)+left,UiTheme.dp(view,12)+top,UiTheme.dp(view,16)+right,UiTheme.dp(view,12)+bottom);
            return insets;
        }});
        setContentView(root);refreshList();
    }
    private void refreshList(){
        if(closed)return;final int id=++generation;busy=true;status.setText("正在读取曲库…");
        worker.execute(new Runnable(){public void run(){
            List<ScoreLibrary.Entry> found=null;String problem=null;
            try{found=ScoreLibrary.list(ScoreLibraryActivity.this);}catch(Exception e){problem=message(e);}
            final List<ScoreLibrary.Entry> result=found;final String error=problem;
            main.post(new Runnable(){public void run(){if(closed||id!=generation)return;busy=false;
                if(error!=null){status.setText("读取曲库失败："+error);return;}
                entries.clear();entries.addAll(result);adapter.notifyDataSetChanged();
                status.setText(entries.isEmpty()?"曲库为空：请从人人钢琴下载或导入 MIDI。":"已保存 "+entries.size()+" 首 · 点击曲目操作");
            }});
        }});
    }
    private void actions(final ScoreLibrary.Entry e){
        new AlertDialog.Builder(this).setTitle(e.name)
            .setItems(new String[]{"载入到曲谱区","另存 MIDI 到手机","重命名","删除"},new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){
                if(which==0)load(e);else if(which==1)export(e);else if(which==2)rename(e);else confirmDelete(e);
            }}).setNegativeButton("取消",null).show();
    }
    private void load(final ScoreLibrary.Entry e){
        busy=true;status.setText("正在读取 " + e.name + "…");final int id=++generation;
        worker.execute(new Runnable(){public void run(){String problem=null;
            try{ScoreLibrary.read(ScoreLibraryActivity.this,e.token);}catch(Exception ex){problem=message(ex);}
            final String error=problem;main.post(new Runnable(){public void run(){if(closed||id!=generation)return;busy=false;
                if(error!=null){status.setText("读取失败："+error);return;}
                setResult(RESULT_OK,new Intent().putExtra(WebsiteScoreActivity.EXTRA_TOKEN,e.token).putExtra(WebsiteScoreActivity.EXTRA_NAME,e.name));finish();
            }});
        }});
    }
    private void rename(final ScoreLibrary.Entry e){
        final EditText name=new EditText(this);name.setSingleLine(true);name.setText(e.unnamedLegacy?"":e.name);name.setHint("输入曲名");UiTheme.input(name);
        new AlertDialog.Builder(this).setTitle("重命名曲谱").setView(name).setNegativeButton("取消",null)
            .setPositiveButton("保存",new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){
                final String value=name.getText().toString();busy=true;final int id=++generation;
                worker.execute(new Runnable(){public void run(){String problem=null;
                    try{ScoreLibrary.rename(ScoreLibraryActivity.this,e.token,value);}catch(Exception ex){problem=message(ex);}
                    final String error=problem;main.post(new Runnable(){public void run(){if(closed||id!=generation)return;busy=false;
                        if(error!=null)status.setText("重命名失败："+error);else refreshList();
                    }});
                }});
            }}).show();
    }
    private void confirmDelete(final ScoreLibrary.Entry e){
        new AlertDialog.Builder(this).setTitle("删除这首曲谱？")
            .setMessage("删除 App 曲库中的「"+e.name+"」。已另存到其他位置的文件不受影响。")
            .setNegativeButton("取消",null).setPositiveButton("删除",new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){
                busy=true;final int id=++generation;
                worker.execute(new Runnable(){public void run(){String problem=null;
                    try{ScoreLibrary.delete(ScoreLibraryActivity.this,e.token);}catch(Exception ex){problem=message(ex);}
                    final String error=problem;main.post(new Runnable(){public void run(){if(closed||id!=generation)return;busy=false;
                        if(error!=null)status.setText("删除失败："+error);else refreshList();
                    }});
                }});
            }}).show();
    }
    private void export(ScoreLibrary.Entry e){
        exportToken=e.token;exportName=e.name;
        Intent intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("audio/midi").addCategory(Intent.CATEGORY_OPENABLE)
            .putExtra(Intent.EXTRA_TITLE,WebMidiDownload.displayName(e.name));
        try{startActivityForResult(intent,EXPORT);}catch(RuntimeException ex){exportToken=exportName=null;status.setText("无法打开手机文件保存器。");}
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);if(request!=EXPORT||closed)return;
        final String token=exportToken;exportToken=exportName=null;
        if(result!=RESULT_OK||data==null||data.getData()==null||token==null){status.setText("已取消另存，曲库保留。");return;}
        final Uri destination=data.getData();final int id=++generation;busy=true;status.setText("正在另存 MIDI…");
        worker.execute(new Runnable(){public void run(){String problem=null;try{
            byte[] bytes=ScoreLibrary.read(ScoreLibraryActivity.this,token);
            try(OutputStream out=getContentResolver().openOutputStream(destination,"wt")){
                if(out==null)throw new IOException("无法打开保存位置");out.write(bytes);out.flush();
            }
        }catch(Exception ex){problem=message(ex);}final String error=problem;
            main.post(new Runnable(){public void run(){if(closed||id!=generation)return;busy=false;
                status.setText(error==null?"已另存 MIDI；曲库中的文件保留。":"另存失败："+error);
            }});
        }});
    }
    private static String message(Exception ex){String value=ex.getMessage();return value==null?ex.getClass().getSimpleName():value;}
    @Override protected void onSaveInstanceState(Bundle state){super.onSaveInstanceState(state);state.putString("exportToken",exportToken);state.putString("exportName",exportName);}
    @Override protected void onDestroy(){closed=true;generation++;worker.shutdownNow();main.removeCallbacksAndMessages(null);super.onDestroy();}
}
