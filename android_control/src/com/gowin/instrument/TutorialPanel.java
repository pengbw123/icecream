package com.gowin.instrument;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.DialogInterface;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.widget.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** ROM-backed LED practice; the phone sends controls and calibration only. */
public final class TutorialPanel extends LinearLayout {
    public interface Host {
        BleTransport transport();boolean otherBusy();void log(String text);void refresh();
        default void exportLedMap(String csv){throw new IllegalStateException("当前窗口没有文件导出入口，可先复制明细");}
    }
    private final Activity activity;
    private final Host host;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final ScoreTransfer transfer=new ScoreTransfer();
    private final SharedPreferences saved;
    private final TextView status,speedLabel,speedDetail,startHint,calibrationSummary,calibrationCount,selectedKeyHint,calibrationFeedback;
    private final InstrumentGraphics.PianoMap pianoPreview;
    private final List<Button> rateButtons=new ArrayList<>();
    private final SeekBar speed;
    private final EditText ledCount,firstNote,transpose,beatIndex,scanIndex;
    private final Spinner key,practiceMode;
    private final List<Button> buttons=new ArrayList<>();
    private final List<Button> localButtons=new ArrayList<>();
    private final List<View> editors=new ArrayList<>();
    private final Button startButton,writeMappingButton,copyButton,detailsButton;
    private final int[] keyIndices=new int[25];
    private Runnable timeout;
    private String completedMessage;
    private String pendingRefusal;
    private int epoch;
    private boolean closed;

    public TutorialPanel(Activity activity,Host host){
        super(activity);this.activity=activity;this.host=host;setOrientation(VERTICAL);
        saved=activity.getSharedPreferences("sunny-led-guide-v1",Context.MODE_PRIVATE);
        for(int i=0;i<25;i++)keyIndices[i]=saved.getInt("key"+i,-1);
        calibrationFeedback=UiTheme.caption(activity,"点亮确认后再保存。保存只改手机，不会自动写入FPGA。");
        calibrationFeedback.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout song=UiTheme.card(activity);
        song.setBackground(UiTheme.round(song,UiTheme.HERO,22));
        song.addView(UiTheme.eyebrow(activity,"内置练习  /  138K"));
        LinearLayout songRow=UiTheme.row(activity);
        LinearLayout songText=new LinearLayout(activity);songText.setOrientation(VERTICAL);
        TextView songTitle=UiTheme.heading(activity,"晴天");songTitle.setTextSize(34);
        songText.addView(songTitle);songText.addView(UiTheme.caption(activity,"社区旋律练习版"));
        songRow.addView(songText,new LayoutParams(0,-2,1));
        InstrumentGraphics.Icon songIcon=new InstrumentGraphics.Icon(activity,1);
        songIcon.color(UiTheme.PRIMARY);songIcon.setBackground(UiTheme.round(songIcon,0xFF304C38,18));
        songRow.addView(songIcon,new LayoutParams(UiTheme.dp(this,64),UiTheme.dp(this,64)));
        song.addView(songRow);UiTheme.space(song,12);
        TextView metadata=UiTheme.caption(activity,"343 音符   ·   原速 2 分 36 秒");metadata.setTextColor(UiTheme.TEXT);song.addView(metadata);
        song.addView(UiTheme.caption(activity,"声音由你弹奏，灯光引导节奏。"));addCard(song);

        LinearLayout player=UiTheme.card(activity);
        player.addView(UiTheme.eyebrow(activity,"练习方式"));
        practiceMode=new Spinner(activity);
        practiceMode.setAdapter(UiTheme.spinnerAdapter(activity,new String[]{"弹对再走 · 先学指法","固定跟拍 · 练习节奏"}));
        practiceMode.setSelection(saved.getBoolean("waitForKey",true)?0:1);UiTheme.spinner(practiceMode);
        practiceMode.setContentDescription("练习方式，弹对再走或固定跟拍");player.addView(practiceMode);editors.add(practiceMode);
        player.addView(UiTheme.caption(activity,"弹对再走：绿灯一直等你，弹错不前进；相同音要松键再按。需配套新版138K程序。"));
        UiTheme.space(player,12);
        player.addView(UiTheme.eyebrow(activity,"练习速度"));
        LinearLayout tempoRow=UiTheme.row(activity);
        boolean largeText=getResources().getConfiguration().fontScale>1.2f;
        speedLabel=UiTheme.heading(activity,"");speedLabel.setTextSize(largeText?44:48);
        speedLabel.setTypeface(android.graphics.Typeface.create("sans-serif-light",android.graphics.Typeface.NORMAL));
        tempoRow.addView(speedLabel,new LayoutParams(0,-2,1));
        TextView countIn=UiTheme.caption(activity,"4 拍\n预备");countIn.setGravity(android.view.Gravity.CENTER);
        countIn.setPadding(UiTheme.dp(this,14),UiTheme.dp(this,6),UiTheme.dp(this,14),UiTheme.dp(this,6));
        countIn.setBackground(UiTheme.round(countIn,UiTheme.RAISED,14));tempoRow.addView(countIn);
        // Reserve the full row for decimal BPM at large font scales. The count-in
        // remains in the text below, so it does not compete for numeric width.
        if(largeText)countIn.setVisibility(View.GONE);
        player.addView(tempoRow);
        speedDetail=UiTheme.caption(activity,"");player.addView(speedDetail);
        speed=new SeekBar(activity);speed.setMax(100);speed.setProgress(Math.max(50,Math.min(150,saved.getInt("speed",100)))-50);
        speed.setContentDescription("练习速度，50%到150%，开始时应用");UiTheme.seek(speed);player.addView(speed);editors.add(speed);
        LinearLayout rates=new LinearLayout(activity);rates.setOrientation(VERTICAL);
        LinearLayout rateRow=UiTheme.row(activity);rates.addView(rateRow);
        for(final int rate:new int[]{50,75,100,150}){
            if(getResources().getConfiguration().fontScale>1.4f&&rateButtons.size()==2){rateRow=UiTheme.row(activity);rates.addView(rateRow);}
            Button choice=new Button(activity);choice.setText(rate+"%");choice.setContentDescription("练习速度 "+rate+"%");
            UiTheme.segment(choice);
            choice.setPadding(UiTheme.dp(this,8),UiTheme.dp(this,10),UiTheme.dp(this,8),UiTheme.dp(this,10));choice.setTextSize(13);
            choice.setOnClickListener(new View.OnClickListener(){public void onClick(View v){speed.setProgress(rate-50);}});
            LayoutParams p=new LayoutParams(0,-2,1);if(rateRow.getChildCount()>0)p.setMarginStart(UiTheme.dp(this,6));
            rateRow.addView(choice,p);rateButtons.add(choice);editors.add(choice);
        }
        player.addView(rates);UiTheme.space(player,14);
        player.addView(UiTheme.caption(activity,"50%慢练为75 BPM。弹对再走时，速度只影响开头的预备拍。"));
        LinearLayout shiftRow=UiTheme.row(activity);
        shiftRow.addView(UiTheme.body(activity,"移调 · 半音"),new LayoutParams(0,-2,1));
        transpose=numberBox("练习移调（-24..24半音）",saved.getInt("transpose",-2));transpose.setGravity(android.view.Gravity.CENTER);
        shiftRow.addView(transpose,new LayoutParams(UiTheme.dp(this,88),-2));player.addView(shiftRow);
        player.addView(UiTheme.caption(activity,"MIDI 48..72 键盘建议 -2；设置在开始时应用。"));
        LinearLayout controls=new LinearLayout(activity);
        controls.setOrientation(getResources().getConfiguration().fontScale>1.2f?VERTICAL:HORIZONTAL);
        startButton=addButton(controls,"开始练习",new Runnable(){public void run(){prepare(true);}},UiTheme.Style.PRIMARY);
        startButton.setContentDescription("开始练习，写入灯位和设置后，FPGA预备4拍再开始跟灯");
        addButton(controls,"停止跟灯",new Runnable(){public void run(){send(Collections.singletonList(TutorialProtocol.stop()),"FPGA已确认停止指引；正常琴键演奏保持可用。");}},UiTheme.Style.SECONDARY);
        player.addView(controls);
        startHint=UiTheme.caption(activity,"");UiTheme.space(player,6);player.addView(startHint);addCard(player);

        LinearLayout card=UiTheme.card(activity);
        LinearLayout mapHeading=UiTheme.row(activity);
        mapHeading.addView(UiTheme.section(activity,"灯位校准"),new LayoutParams(0,-2,1));
        calibrationCount=UiTheme.body(activity,"");calibrationCount.setTextSize(14);mapHeading.addView(calibrationCount);card.addView(mapHeading);
        pianoPreview=new InstrumentGraphics.PianoMap(activity);
        card.addView(pianoPreview,new LayoutParams(-1,UiTheme.dp(this,58)));
        UiTheme.space(card,8);calibrationSummary=UiTheme.caption(activity,"");card.addView(calibrationSummary);
        detailsButton=addButton(card,"查看 / 导出灯位明细",new Runnable(){public void run(){showMappingDetails();}},UiTheme.Style.GHOST,false);
        final LinearLayout calibration=new LinearLayout(activity);calibration.setOrientation(VERTICAL);
        final Button fold=new Button(activity);fold.setText("展开灯带校准");UiTheme.button(fold,UiTheme.Style.SECONDARY);
        calibration.setVisibility(View.GONE);fold.setOnClickListener(new View.OnClickListener(){public void onClick(View view){boolean show=calibration.getVisibility()!=View.VISIBLE;calibration.setVisibility(show?View.VISIBLE:View.GONE);fold.setText(show?"收起灯带校准":"展开灯带校准");}});
        card.addView(fold,new LayoutParams(-1,-2));card.addView(calibration);
        UiTheme.space(calibration,16);calibration.addView(UiTheme.section(activity,"01  确认灯带和键盘"));
        calibration.addView(UiTheme.caption(activity,"灯带沿琴键上沿连续铺设，每个白键和黑键各选一颗最接近中心的灯，灯位不能重复。编号从DIN端0开始，与MIDI编号不同。"));
        ledCount=number(calibration,"灯带实际共有多少颗灯（25..160，不是琴键数量）",saved.getInt("ledCount",160));
        firstNote=number(calibration,"最左琴键的实际MIDI编号（不是灯号，先固定键盘八度/移调）",saved.getInt("firstNote",48));
        UiTheme.space(calibration,16);calibration.addView(UiTheme.section(activity,"02  逐键定位与保存"));
        String[] labels=new String[25];for(int i=0;i<25;i++)labels[i]="第"+(i+1)+"键（从左到右，包含黑键）";
        key=new Spinner(activity);key.setAdapter(UiTheme.spinnerAdapter(activity,labels));UiTheme.spinner(key);calibration.addView(key);editors.add(key);
        selectedKeyHint=UiTheme.caption(activity,"");calibration.addView(selectedKeyHint);
        scanIndex=number(calibration,"要点亮灯带上的哪颗灯（DIN端第1颗填0，第4颗填3）",0);
        addButton(calibration,"点亮当前定位灯",new Runnable(){public void run(){scan(0);}},UiTheme.Style.SECONDARY);
        LinearLayout stepping=new LinearLayout(activity);stepping.setOrientation(HORIZONTAL);
        addButton(stepping,"上一灯",new Runnable(){public void run(){scan(-1);}},UiTheme.Style.SECONDARY);
        addButton(stepping,"下一灯",new Runnable(){public void run(){scan(1);}},UiTheme.Style.SECONDARY);
        calibration.addView(stepping,new LayoutParams(-1,-2));
        calibration.addView(UiTheme.caption(activity,"先看实物确认定位灯正对所选琴键，再保存。保存后自动选择下一键；例如最左键是C时，第2键就是C♯黑键，不能只数白键。"));
        addButton(calibration,"保存当前灯位到所选键（手机）",new Runnable(){public void run(){saveKey();}},UiTheme.Style.PRIMARY,false);
        calibration.addView(calibrationFeedback,new LayoutParams(-1,-2));
        beatIndex=number(calibration,"独立节拍灯编号（先用-1：只亮板上节拍LED）",saved.getInt("beatIndex",-1));
        UiTheme.space(calibration,16);calibration.addView(UiTheme.section(activity,"03  写入乐器"));
        calibration.addView(UiTheme.caption(activity,"写入会先停止练习，并同时应用上方选择的速度、移调和4拍预备。"));
        writeMappingButton=addButton(calibration,"写入全部校准灯位",new Runnable(){public void run(){prepare(false);}},UiTheme.Style.SECONDARY);
        copyButton=addButton(calibration,"复制校准JSON（用于下次编入FPGA）",new Runnable(){public void run(){copyProfile();}},UiTheme.Style.GHOST,false);
        calibration.addView(UiTheme.caption(activity,"保存只改手机。写入FPGA后本次供电期间可用S0开始、S1停止；S4复位或断电后需重新写入。扫描会先停止练习。若要上电直接S0开始，需把校准JSON编入FPGA。"));
        addCard(card);

        LinearLayout connection=UiTheme.card(activity);
        connection.addView(UiTheme.section(activity,"指引接口"));
        status=UiTheme.caption(activity,"连接蓝牙后，先检查138K指引接口。首次使用还需完成25键灯位校准。");connection.addView(status);
        addButton(connection,"检查138K指引接口",new Runnable(){public void run(){send(Collections.singletonList(TutorialProtocol.probe()),"138K内置指引接口已回应；接下来校准灯位。灯带与节奏仍需实板确认。");}},UiTheme.Style.SECONDARY);
        addCard(connection);
        LinearLayout notes=UiTheme.card(activity);
        notes.addView(UiTheme.section(activity,"跟着颜色练习"));
        notes.addView(UiTheme.caption(activity,"黄灯预告 · 绿灯到点 · 蓝灯拍点"));
        notes.addView(UiTheme.caption(activity,"曲谱已内置，无需上传。弹对再走只亮当前绿灯，预备拍后等你按对；固定跟拍按速度显示预告和拍点。S1可停止，断开手机后乐器继续。"));
        notes.addView(UiTheme.caption(activity,"手机预览显示已保存的灯位，不代表实物灯光或当前节拍。"));addCard(notes);
        speed.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean user){updateSpeed();}
            public void onStartTrackingTouch(SeekBar bar){}
            public void onStopTrackingTouch(SeekBar bar){}
        });updateSpeed();
        key.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){
            public void onItemSelected(android.widget.AdapterView<?> parent,View view,int position,long id){updateSelectedKey();}
            public void onNothingSelected(android.widget.AdapterView<?> parent){}
        });
        android.text.TextWatcher watcher=new android.text.TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){refresh();}
            public void afterTextChanged(android.text.Editable text){}
        };
        for(View editor:editors)if(editor instanceof EditText)((EditText)editor).addTextChangedListener(watcher);
        updateSelectedKey();updateCalibrationSummary();
    }
    private void addCard(LinearLayout card){addView(card,new LayoutParams(-1,-2));UiTheme.gap(card);}
    private EditText number(LinearLayout parent,String label,int value){
        TextView caption=UiTheme.caption(activity,label);caption.setPadding(0,UiTheme.dp(this,8),0,UiTheme.dp(this,4));parent.addView(caption);
        EditText box=numberBox(label,value);parent.addView(box,new LayoutParams(-1,-2));return box;
    }
    private EditText numberBox(String label,int value){
        EditText box=new EditText(activity);
        box.setSingleLine(true);box.setText(String.valueOf(value));box.setTextColor(UiTheme.TEXT);
        box.setInputType(android.text.InputType.TYPE_CLASS_NUMBER|android.text.InputType.TYPE_NUMBER_FLAG_SIGNED);
        UiTheme.input(box);box.setContentDescription(label);editors.add(box);return box;
    }
    private Button addButton(LinearLayout parent,String text,Runnable action,UiTheme.Style style){
        return addButton(parent,text,action,style,true);
    }
    private Button addButton(LinearLayout parent,String text,Runnable action,UiTheme.Style style,boolean online){
        Button button=new Button(activity);button.setText(text);UiTheme.button(button,style);
        button.setOnClickListener(new View.OnClickListener(){public void onClick(View view){try{action.run();}catch(RuntimeException ex){setStatus(ex.getMessage());calibrationFeedback.setTextColor(UiTheme.DANGER);host.log("指引设置："+ex.getMessage());}}});
        LayoutParams layout=parent.getOrientation()==HORIZONTAL?new LayoutParams(0,-2,1):new LayoutParams(-1,-2);
        layout.topMargin=UiTheme.dp(this,8);if(parent.getOrientation()==HORIZONTAL&&parent.getChildCount()>0)layout.setMarginStart(UiTheme.dp(this,8));
        parent.addView(button,layout);(online?buttons:localButtons).add(button);return button;
    }
    private int number(EditText box){try{return Integer.parseInt(box.getText().toString().trim());}catch(RuntimeException ex){throw new IllegalArgumentException(box.getContentDescription()+"：请填写整数");}}
    private void setStatus(String text){status.setText(text);calibrationFeedback.setText(text);calibrationFeedback.setTextColor(UiTheme.MUTED);}
    private void updateSpeed(){
        int value=speed.getProgress()+50,twice=value*3;
        speedLabel.setText(twice%2==0?String.valueOf(twice/2):twice/2+".5");
        speedLabel.setContentDescription("练习速度 "+speedLabel.getText()+" BPM");
        speedDetail.setText("BPM  ·  "+value+"%"+(value==100?" 原速":" 练习速度")+(getResources().getConfiguration().fontScale>1.2f?" · 4拍预备":""));
        int i=0;for(Button button:rateButtons)button.setSelected(new int[]{50,75,100,150}[i++]==value);
    }
    private int ledCount(){int count=number(ledCount);if(count<25||count>160)throw new IllegalArgumentException("当前配套138K程序支持25..160颗灯；超过160需重新生成FPGA程序");return count;}
    private void validateSettings(){
        int count=ledCount(),first=number(firstNote),beat=number(beatIndex);
        if(first<0||first>103)throw new IllegalArgumentException("最左琴键MIDI编号需为0..103");
        TutorialProtocol.settings(speed.getProgress()+50,4,number(transpose));
        if(beat< -1||beat>=count)throw new IllegalArgumentException("节拍灯需为-1或实际灯数内的编号");
    }
    private void updateSelectedKey(){
        int at=key.getSelectedItemPosition();if(at<0)return;
        String note;try{note=" · MIDI "+(number(firstNote)+at);}catch(RuntimeException ex){note="";}
        selectedKeyHint.setText("当前第"+(at+1)+"键"+note+"："+(keyIndices[at]<0?"尚未保存灯位":"手机已保存灯"+keyIndices[at])+"。选灯、点亮确认后再保存。");
        try{int first=number(firstNote),count=ledCount();pianoPreview.setVisibility(first>=0&&first<=103?View.VISIBLE:View.INVISIBLE);pianoPreview.update(first,keyIndices,at,count);}
        catch(RuntimeException ex){pianoPreview.setVisibility(View.INVISIBLE);}
    }
    private boolean updateCalibrationSummary(){
        int done=0;try{int count=ledCount();for(int index:keyIndices)if(index>=0&&index<count)done++;}catch(RuntimeException ignored){}
        String problem=null;try{validateSettings();mapping();TutorialProtocol.checkRange(number(firstNote),number(transpose));}catch(RuntimeException ex){problem=ex.getMessage();}
        if(problem!=null&&done==0&&keyIndices[0]<0&&problem.startsWith("第1键"))problem="首次使用，请逐键保存灯位（包含黑键）";
        calibrationCount.setText(done+" / 25");calibrationCount.setTextColor(problem==null?UiTheme.SUCCESS:UiTheme.WARNING);
        calibrationSummary.setText("手机灯位 "+done+"/25 · "+(problem==null?"已备齐，可写入或开始练习。":problem+"。"));
        calibrationSummary.setTextColor(UiTheme.MUTED);
        updateSelectedKey();return problem==null;
    }
    private void persist(){
        SharedPreferences.Editor edit=saved.edit().putInt("speed",speed.getProgress()+50)
            .putInt("transpose",number(transpose)).putInt("ledCount",number(ledCount))
            .putInt("firstNote",number(firstNote)).putInt("beatIndex",number(beatIndex)).putBoolean("waitForKey",practiceMode.getSelectedItemPosition()==0);
        for(int i=0;i<25;i++)edit.putInt("key"+i,keyIndices[i]);edit.apply();
    }
    private List<byte[]> mapping(){return TutorialProtocol.profile(ledCount(),number(firstNote),keyIndices,number(beatIndex));}
    private void prepare(boolean start){
        validateSettings();
        List<byte[]> profile=mapping();int shift=number(transpose),rate=speed.getProgress()+50;
        TutorialProtocol.checkRange(number(firstNote),shift);
        byte[] settings=TutorialProtocol.settings(rate,4,shift);
        persist();List<byte[]> frames=new ArrayList<>();frames.add(TutorialProtocol.probe());frames.add(TutorialProtocol.stop());
        frames.add(TutorialProtocol.mode(practiceMode.getSelectedItemPosition()==0));
        frames.add(settings);frames.addAll(profile);
        if(start)frames.add(TutorialProtocol.start());
        String snapshot=(practiceMode.getSelectedItemPosition()==0?"弹对再走，相同音需松键再按。":"固定跟拍。")+"灯数"+number(ledCount)+"，最低MIDI "+number(firstNote)+"，速度"+rate+"%，移调"+shift+"。";
        send(frames,(start?"FPGA已确认开始指引，先预备4拍；手机可断开，S1可随时停止。":"全部灯位与设置命令已确认。本次供电期间可用S0开始、S1停止；S4复位或断电后需重新写入。")+snapshot);
    }
    private void scan(int delta){
        int count=ledCount(),index=number(scanIndex)+delta;
        if(index<0||index>=count)throw new IllegalArgumentException("定位灯编号超出所填灯数");
        scanIndex.setText(String.valueOf(index));
        send(Arrays.asList(TutorialProtocol.probe(),TutorialProtocol.stop(),TutorialProtocol.scan(true,index)),"定位灯命令已确认：编号"+index+"；请看实物确认位置。");
    }
    private void saveKey(){
        validateSettings();int at=key.getSelectedItemPosition(),index=number(scanIndex),count=ledCount();
        if(index<0||index>=count)throw new IllegalArgumentException("灯位越界");
        for(int i=0;i<25;i++)if(i!=at&&keyIndices[i]==index)throw new IllegalArgumentException("此灯已用于第"+(i+1)+"键");
        keyIndices[at]=index;persist();int done=0;for(int value:keyIndices)if(value>=0)done++;
        setStatus("手机已保存第"+(at+1)+"键 → 灯"+index+"（从DIN端数第"+(index+1)+"颗），共"+done+"/25键；尚未写入FPGA。");
        if(at<24)key.setSelection(at+1);
        refresh();
    }
    private void copyProfile(){
        validateSettings();mapping();StringBuilder text=new StringBuilder("{\"led_count\":").append(number(ledCount)).append(",\"keys\":{");
        for(int i=0;i<25;i++){if(i>0)text.append(',');text.append('"').append(number(firstNote)+i).append("\":").append(keyIndices[i]);}
        text.append("},\"beat_led\":");int beat=number(beatIndex);text.append(beat<0?"null":String.valueOf(beat));
        TutorialProtocol.checkRange(number(firstNote),number(transpose));persist();
        text.append(",\"speed_percent\":").append(speed.getProgress()+50).append(",\"count_in_beats\":4,\"transpose\":").append(number(transpose)).append('}');
        ((ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("138K LED calibration",text.toString()));
        setStatus("校准JSON已复制；保存为文件后用生成工具编入FPGA，才能断电后直接S0开始。");
    }
    private int optionalNumber(EditText field){try{return number(field);}catch(RuntimeException ex){return Integer.MIN_VALUE;}}
    private String keyState(int at,int count,int first){
        int index=keyIndices[at];
        if(index<0)return "未校准";
        if(count<25||count>160)return "灯珠总数无效";
        if(index>=count)return "灯号越界";
        for(int i=0;i<25;i++)if(i!=at&&keyIndices[i]==index)return "灯号重复";
        if(first<0||first>103)return "最低MIDI无效";
        return "手机已保存";
    }
    /** A human-readable draft, deliberately separate from the validated FPGA JSON. */
    private String mappingCsv(){
        int first=optionalNumber(firstNote),count=optionalNumber(ledCount);
        StringBuilder csv=new StringBuilder("琴键序号,MIDI编号,灯珠编号(从0开始),实物第几颗灯(从1开始),状态\r\n");
        for(int i=0;i<25;i++){
            int index=keyIndices[i];
            csv.append(i+1).append(',').append(first>=0&&first<=103?String.valueOf(first+i):"").append(',')
                .append(index>=0?String.valueOf(index):"").append(',').append(index>=0?String.valueOf((long)index+1):"")
                .append(',').append(keyState(i,count,first)).append("\r\n");
        }
        return csv.toString();
    }
    private void showMappingDetails(){
        final String csv=mappingCsv();
        int first=optionalNumber(firstNote),count=optionalNumber(ledCount);
        StringBuilder text=new StringBuilder("灯号从DIN端0开始，灯3就是第4颗。\n以下为手机保存的灯位和当前MIDI设置，不是板端读回。未校准项不补灯号。\n\n");
        for(int i=0;i<25;i++){
            int index=keyIndices[i];text.append("第").append(i+1).append("键 · MIDI ")
                .append(first>=0&&first<=103?String.valueOf(first+i):"未确定").append(" → ");
            if(index<0)text.append("未校准");
            else text.append("灯").append(index).append("（第").append((long)index+1).append("颗） · ").append(keyState(i,count,first));
            text.append('\n');
        }
        TextView listing=UiTheme.mono(activity,text.toString());
        LinearLayout listingContent=new LinearLayout(activity);listingContent.setOrientation(VERTICAL);
        listingContent.addView(UiTheme.caption(activity,"CSV可在未完成校准时导出；完整FPGA校准JSON仍需25键全部有效。"));
        listingContent.addView(listing);
        ScrollView viewport=new ScrollView(activity);viewport.addView(listingContent);
        LinearLayout content=new LinearLayout(activity);content.setOrientation(VERTICAL);
        content.setPadding(UiTheme.dp(this,16),UiTheme.dp(this,8),UiTheme.dp(this,16),0);
        int height=Math.max(80,Math.min(320,getResources().getConfiguration().screenHeightDp/3));
        content.addView(viewport,new LayoutParams(-1,UiTheme.dp(this,height)));
        new AlertDialog.Builder(activity).setTitle("灯位明细（手机）").setView(content)
            .setPositiveButton("导出CSV",new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){try{host.exportLedMap(csv);}catch(RuntimeException ex){setStatus("导出未开始："+ex.getMessage());}}})
            .setNeutralButton("复制",new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){
                ((ClipboardManager)activity.getSystemService(Context.CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("25键灯位明细 CSV",csv));
                setStatus("25键灯位明细已复制；未校准键留空。此明细不代表已写入FPGA。");
            }}).setNegativeButton("关闭",null).show();
    }
    public boolean busy(){return transfer.busy();}
    private boolean available(){BleTransport ble=host.transport();return !closed&&!busy()&&!host.otherBusy()&&ble!=null&&ble.isReady()&&!ble.isSending();}
    public void refresh(){
        boolean enabled=available(),valid=updateCalibrationSummary();BleTransport ble=host.transport();
        boolean editable=!closed&&!busy()&&!host.otherBusy()&&(ble==null||!ble.isSending());
        for(Button button:buttons)button.setEnabled(enabled);for(Button button:localButtons)button.setEnabled(editable);
        for(View editor:editors)editor.setEnabled(editable);
        startButton.setEnabled(enabled&&valid);writeMappingButton.setEnabled(enabled&&valid);copyButton.setEnabled(editable&&valid);
        detailsButton.setEnabled(!closed);
        if(busy())startHint.setText("正在发送指引命令；如需立即停止，请按板上 S1。");
        else if(host.otherBusy()||(ble!=null&&ble.isSending()))startHint.setText("请等待当前传输结束，再开始练习。");
        else if(ble==null||!ble.isReady())startHint.setText("先连接乐器。灯位可提前保存在手机。");
        else if(!valid)startHint.setText("请先完成下方25键灯位校准，再开始练习。");
        else startHint.setText("开始会重写灯位和设置，随后预备4拍。");
    }
    private void send(List<byte[]> frames,String message){
        if(!available())throw new IllegalStateException("请先连接蓝牙并等待当前传输结束");
        transfer.start(frames);completedMessage=message;pendingRefusal=null;epoch++;refresh();host.refresh();sendCurrent();
    }
    private void sendCurrent(){
        if(!busy()||closed)return;final int token=epoch;
        final String step=commandLabel(transfer.command());
        setStatus("第"+(transfer.done()+1)+"/"+transfer.total()+"步："+step+"，等待本地写完成和板端回复。");
        timeout=new Runnable(){public void run(){if(!closed&&token==epoch&&busy()){
            host.log("指引超时状态："+transfer.waitingSummary());
            fail("指引命令超时："+step+"；"+(transfer.isWritten()?"手机本地写已完成":"本地写尚未完成")+"，未完成板端确认。连接断开，S1仍可停止板端指引。",true);}}};
        handler.postDelayed(timeout,4000);
        host.log("指引发送 第"+(transfer.done()+1)+"/"+transfer.total()+"步 "+step+" TX="+Protocol.hex(transfer.current()));
        if(!host.transport().sendFrame(transfer.current()))fail("指引命令未能写出",true);
    }
    private static String commandLabel(int command){
        switch(command){case 0x75:return "检查指引接口0x75";case 0x70:return "启停指引0x70";case 0x71:return "定位灯0x71";
            case 0x72:return "写入灯位0x72";case 0x73:return "清除旧映射0x73";case 0x74:return "写入练习设置0x74";
            case 0x76:return "设置练习方式0x76";
            default:return "命令0x"+Integer.toHexString(command);}
    }
    public void onProgress(BleTransport.SendProgress progress){if(!busy())return;if(progress.cancelled){fail("发送已取消",true);return;}if(progress.finished){transfer.written();if(pendingRefusal!=null)fail(pendingRefusal,false);else advance();}}
    public void onReply(ReplyDecoder.Reply reply){
        if(!busy()||pendingRefusal!=null||reply.capabilities!=null||reply.reliable!=null)return;
        if(reply.command==transfer.command()&&reply.status!=0){
            // ScoreTransfer.reply() cancels on errors. Keep it owning the local
            // completion until both sides have finished this rejected frame.
            String text="指引命令被拒绝：0x"+Integer.toHexString(reply.command)+"，状态"+reply.status+"；停止练习后核对灯数、参数和配套138K程序。";
            if(reply.command==0x76)text="板端未接受练习方式0x76；需要配套的等键练习版138K程序，并先停止自动演奏。练习尚未开始，手机灯位和蓝牙连接保留。";
            if(transfer.isWritten())fail(text,false);else{pendingRefusal=text;setStatus("板端已拒绝，等待本地发送收尾；蓝牙连接将保留。");}
            return;
        }
        try{if(transfer.reply(reply.command,reply.status))advance();}
        catch(RuntimeException ex){fail("指引传输状态异常："+ex.getMessage()+"；请重连后检查接口。",true);}
    }
    private void advance(){
        if(!transfer.canAdvance())return;if(timeout!=null)handler.removeCallbacks(timeout);
        transfer.advance();if(busy())sendCurrent();else{setStatus(completedMessage);host.log(completedMessage);refresh();host.refresh();}
    }
    private void fail(String text,boolean disconnect){
        epoch++;pendingRefusal=null;transfer.cancel();if(timeout!=null)handler.removeCallbacks(timeout);
        setStatus(text);host.log(text);BleTransport ble=host.transport();
        if(disconnect&&ble!=null)ble.disconnect(text);refresh();host.refresh();
    }
    public void disconnected(){epoch++;pendingRefusal=null;transfer.cancel();handler.removeCallbacksAndMessages(null);setStatus("蓝牙已断开；若练习已经开始，FPGA会继续，S1可停止。手机灯位保留，重连后重新写入或开始。");refresh();}
    public void sendError(String text){if(busy())fail(text,true);}
    public void close(){closed=true;epoch++;transfer.cancel();handler.removeCallbacksAndMessages(null);}
}
