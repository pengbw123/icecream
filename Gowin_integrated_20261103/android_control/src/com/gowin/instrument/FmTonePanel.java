package com.gowin.instrument;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.view.View;
import android.widget.AdapterView;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

/** One acknowledged FM request at a time; no success message for a local BLE write. */
public final class FmTonePanel extends LinearLayout {
    public interface Host {BleTransport transport();boolean otherBusy();void log(String s);void refresh();}
    private final Activity activity;private final Host host;private final Handler main=new Handler(Looper.getMainLooper());
    private final Spinner group,selector,param,preset;private final EditText input;private final TextView hint,status;
    private final Button read,apply;private FmToneSpec.Param[] params;
    private boolean closed,pending,written;private int token=1,expectedToken,requestGroup,requestSelector,requestRow,requestValue;
    private boolean requestRead;private FmToneSpec.Param requestParam;private FmPhoneProtocol.Reply reply;private Runnable timeout;
    public FmTonePanel(Activity activity,Host host){
        super(activity);this.activity=activity;this.host=host;setOrientation(VERTICAL);
        token=1+(int)(System.nanoTime()&0xffff)%65535;
        LinearLayout intro=UiTheme.card(activity);intro.setBackground(UiTheme.round(intro,UiTheme.HERO,18));
        intro.addView(UiTheme.eyebrow(activity,"声音的更多可能"));intro.addView(UiTheme.heading(activity,"找到属于你的音色"));
        intro.addView(UiTheme.caption(activity,"从预设开始，再慢慢调成喜欢的声音。"));addView(intro);UiTheme.gap(intro);
        LinearLayout card=UiTheme.card(activity);card.addView(UiTheme.section(activity,"音色与参数"));
        card.addView(UiTheme.caption(activity,"先读取乐器当前值，再调整。切换预设会替换当前修改。"));
        UiTheme.space(card,12);card.addView(UiTheme.caption(activity,"选择调整内容"));
        group=spinner(FmToneSpec.GROUPS);card.addView(group);
        selector=spinner(new String[]{"全部"});spaceBefore(card,selector);
        param=spinner(new String[]{"参数"});spaceBefore(card,param);
        preset=spinner(FmPresetNames.NAMES);spaceBefore(card,preset);
        input=new EditText(activity);input.setSingleLine(true);input.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_SIGNED);UiTheme.input(input);input.setHint("输入新的数值");spaceBefore(card,input);
        hint=UiTheme.caption(activity,"");card.addView(hint);
        LinearLayout buttons=UiTheme.row(activity);
        read=new Button(activity);read.setText("读取当前值");UiTheme.button(read,false);buttons.addView(read,new LinearLayout.LayoutParams(0,-2,1));
        apply=new Button(activity);apply.setText("应用到乐器");UiTheme.button(apply,true);LinearLayout.LayoutParams applyLayout=new LinearLayout.LayoutParams(0,-2,1);applyLayout.setMarginStart(UiTheme.dp(this,8));buttons.addView(apply,applyLayout);UiTheme.space(card,12);card.addView(buttons);
        status=UiTheme.caption(activity,"连接乐器后可读取和调整。");status.setTextIsSelectable(true);card.addView(status);addView(card);
        group.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int position,long id){configureSelectors();}public void onNothingSelected(AdapterView<?> p){}});
        selector.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int position,long id){configureParams();}public void onNothingSelected(AdapterView<?> p){}});
        param.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onItemSelected(AdapterView<?> p,View v,int position,long id){showHint();}public void onNothingSelected(AdapterView<?> p){}});
        read.setOnClickListener(new OnClickListener(){public void onClick(View v){begin(true,false,0);}});
        apply.setOnClickListener(new OnClickListener(){public void onClick(View v){begin(false,false,0);}});
        configureSelectors();refresh();
    }
    private void spaceBefore(LinearLayout parent,View view){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,-2);p.topMargin=UiTheme.dp(parent,10);parent.addView(view,p);}
    private Spinner spinner(String[] options){Spinner s=new Spinner(activity);UiTheme.spinner(s);s.setAdapter(UiTheme.spinnerAdapter(activity,options));return s;}
    private int groupIndex(){return Math.max(0,group.getSelectedItemPosition());}
    private int selection(){return Math.max(0,selector.getSelectedItemPosition());}
    private void configureSelectors(){
        int g=groupIndex();String[] opts=(g==3||g==4)?FmToneSpec.OPERATORS:g==7?FmToneSpec.EFFECTS:new String[]{"全局参数"};
        selector.setAdapter(UiTheme.spinnerAdapter(activity,opts));selector.setVisibility((g==3||g==4||g==7)?VISIBLE:GONE);
        preset.setVisibility(g==0?VISIBLE:GONE);input.setVisibility(g==0?GONE:VISIBLE);configureParams();
    }
    private void configureParams(){params=FmToneSpec.parameters(groupIndex(),selection());String[] names=new String[params.length];for(int i=0;i<params.length;i++)names[i]=params[i].name;param.setAdapter(UiTheme.spinnerAdapter(activity,names));param.setVisibility(params.length>1?VISIBLE:GONE);showHint();}
    private FmToneSpec.Param selected(){int n=Math.max(0,param.getSelectedItemPosition());return params[Math.min(n,params.length-1)];}
    private void showHint(){if(params==null)return;FmToneSpec.Param p=selected();hint.setText("范围："+p.min+" ～ "+p.max+(groupIndex()==3&&p.row==1?"；固定模式上限为 3":"")+(groupIndex()==3&&p.row==0?"；切换模式会重置粗调和微调":""));}
    public boolean busy(){return pending;}
    public void refresh(){BleTransport b=host.transport();boolean enabled=!closed&&!pending&&!host.otherBusy()&&b!=null&&b.isReady()&&!b.isSending();read.setEnabled(enabled);apply.setEnabled(enabled);boolean edit=!closed&&!pending;group.setEnabled(edit);selector.setEnabled(edit);param.setEnabled(edit);preset.setEnabled(edit);input.setEnabled(edit);}
    private void begin(boolean isRead,boolean force,int forcedValue){
        BleTransport b=host.transport();if(closed||pending||host.otherBusy()||b==null||!b.isReady()||b.isSending())return;
        int g=groupIndex(),sel=selection();FmToneSpec.Param p=selected();int value=0;
        if(!isRead)try {value=force?forcedValue:(g==0?p.raw(preset.getSelectedItemPosition()+1):p.raw(Integer.parseInt(input.getText().toString().trim())));}
        catch(RuntimeException e){status.setText("请输入有效值："+p.min+" ～ "+p.max);return;}
        requestGroup=FmToneSpec.protocolGroup(g);requestSelector=FmToneSpec.protocolSelector(g,sel);requestRow=p.row;requestValue=value;requestRead=isRead;requestParam=p;
        expectedToken=token;token=token==65535?1:token+1;reply=null;written=false;pending=true;
        status.setText(isRead?"正在读取板端参数…":"正在等待板端修改与回读…");host.refresh();
        final int seq=expectedToken;timeout=new Runnable(){public void run(){if(pending&&expectedToken==seq)fail("未收到板端确认。请检查蓝牙，或确认 FPGA 已更新到支持手机 FM 控制的版本。具体值请重新读取。 ");}};
        main.postDelayed(timeout,30000);
        if(!b.sendFrame(FmPhoneProtocol.request(requestGroup,requestSelector,requestRow,value,expectedToken,isRead,force)))fail("蓝牙发送未开始，请检查连接并重试。");
    }
    public void onProgress(BleTransport.SendProgress p){if(!pending)return;if(p.cancelled){fail("发送取消，板端状态请重新读取。");return;}if(p.finished){written=true;completeIfReady();}}
    public void onReply(ReplyDecoder.Reply r){
        if(!pending)return;
        if(r.phone!=null){if(r.phone.token!=expectedToken)return;reply=r.phone;completeIfReady();}
        else if(r.command==FmPhoneProtocol.COMMAND&&r.status!=0)fail("板端拒绝音色命令（"+r.label()+"）。请确认 FPGA 与手机版本配套。");
    }
    private void completeIfReady(){
        if(!pending||!written||reply==null)return;
        final int result=reply.status,actual=reply.value;final boolean wasRead=requestRead;final int savedValue=requestValue;final FmToneSpec.Param p=requestParam;
        finish();
        if(result==2){status.setText("切换预设会覆盖未保存的音色修改。 ");new AlertDialog.Builder(activity).setTitle("切换预设音色？").setMessage("板端当前音色有修改。继续会替换这些修改。")
            .setNegativeButton("取消",null).setPositiveButton("继续切换",new DialogInterface.OnClickListener(){public void onClick(DialogInterface d,int which){begin(false,true,savedValue);}}).show();return;}
        if(result!=0){status.setText(reply.label()+"；板端回读值："+p.display(actual)+"。请重新读取并检查。");host.log(status.getText().toString());return;}
        if(groupIndex()==0)preset.setSelection(actual);else input.setText(Integer.toString(p.display(actual)));
        status.setText((wasRead?"当前板端值：":"板端已修改并回读：")+p.display(actual));host.log(status.getText().toString());
        if(!wasRead)Toast.makeText(activity,"修改完成",Toast.LENGTH_SHORT).show();
    }
    private void finish(){pending=false;if(timeout!=null)main.removeCallbacks(timeout);timeout=null;host.refresh();}
    private void fail(String message){if(!pending)return;finish();status.setText(message);host.log(message);}
    public void disconnected(){fail("蓝牙已断开；板端状态请重新读取。");}
    public void sendError(String message){fail("发送失败："+message+"；板端状态请重新读取。");}
    public void close(){closed=true;pending=false;main.removeCallbacksAndMessages(null);}
}
