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
        default void selectUploaded(boolean selected){}
        default void uploadedShiftChanged(String value){}
        default boolean uploadedReady(){return false;}
        default boolean uploadedPlaying(){return false;}
        default boolean uploadedStopRequired(){return uploadedPlaying();}
        default boolean canStopUploaded(){return !otherBusy();}
        default void beforeDeviceChange(Runnable ready){ready.run();}
        default String uploadedProblem(boolean waitForKey){return null;}
        default void startUploaded(int speed,boolean waitForKey){}
        default void stopUploaded(){}
    }
    private final Activity activity;
    private final Host host;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private final ScoreTransfer transfer=new ScoreTransfer();
    private final SharedPreferences saved;
    private final TextView status,speedLabel,speedDetail,startHint,calibrationSummary,calibrationCount,selectedKeyHint,calibrationFeedback;
    private final TextView songEyebrow,songTitle,songSubtitle,songMetadata,speedExplainer,shiftHint;
    private final LinearLayout diagnostics;
    private final LinearLayout practiceOptions;
    private final Button practiceFold;
    private final InstrumentGraphics.PianoMap pianoPreview;
    private final List<Button> rateButtons=new ArrayList<>();
    private final SeekBar speed;
    private final EditText ledCount,firstNote,transpose,beatIndex,scanIndex;
    private final Spinner key,practiceMode;
    private final List<Button> buttons=new ArrayList<>();
    private final List<Button> localButtons=new ArrayList<>();
    private final List<View> editors=new ArrayList<>();
    private final Button startButton,stopButton,writeMappingButton,copyButton,detailsButton,undoButton,songSwitch;
    private final int[] keyIndices=new int[25];
    private int undoKey,undoValue;
    private Runnable timeout;
    private String completedMessage;
    private String pendingRefusal;
    private int epoch;
    private boolean closed;
    private boolean calibrationTransfer,completionConfirmed;
    private boolean uploadedSelected,suppressShift,pendingUploadedStart,sunnyMayBeRunning,sunnyPlaying;
    private int sunnyShift,pendingSpeed;private boolean pendingWait;
    private String uploadedShift="0";
    private Score contextOriginal,contextPart;
    private boolean contextLoaded,contextPlaying;

    public TutorialPanel(Activity activity,Host host){
        super(activity);this.activity=activity;this.host=host;setOrientation(VERTICAL);
        saved=activity.getSharedPreferences("sunny-led-guide-v1",Context.MODE_PRIVATE);
        sunnyShift=saved.getInt("transpose",-2);
        sunnyMayBeRunning=activity.getSharedPreferences("sunny-session-safety-v1",Context.MODE_PRIVATE).getBoolean("stopRequired",false);
        for(int i=0;i<25;i++)keyIndices[i]=saved.getInt("key"+i,-1);
        undoKey=saved.getInt("undoKey",-1);undoValue=saved.getInt("undoValue",-1);
        if(undoKey<0||undoKey>=25)undoKey=-1;
        calibrationFeedback=UiTheme.caption(activity,"点亮确认后再保存。保存只改手机，不会自动写入FPGA。");
        calibrationFeedback.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        LinearLayout song=UiTheme.card(activity);
        song.setBackground(UiTheme.round(song,UiTheme.HERO,22));
        songEyebrow=UiTheme.eyebrow(activity,"内置曲谱");song.addView(songEyebrow);
        LinearLayout songRow=UiTheme.row(activity);
        LinearLayout songText=new LinearLayout(activity);songText.setOrientation(VERTICAL);
        songTitle=UiTheme.heading(activity,"晴天");songTitle.setTextSize(30);songTitle.setMaxLines(2);songTitle.setEllipsize(android.text.TextUtils.TruncateAt.END);
        songSubtitle=UiTheme.caption(activity,"社区旋律练习版");songText.addView(songTitle);songText.addView(songSubtitle);
        songRow.addView(songText,new LayoutParams(0,-2,1));
        InstrumentGraphics.Icon songIcon=new InstrumentGraphics.Icon(activity,1);
        songIcon.color(UiTheme.PRIMARY);songIcon.setBackground(UiTheme.round(songIcon,0xFFD3E2CC,16));
        songRow.addView(songIcon,new LayoutParams(UiTheme.dp(this,52),UiTheme.dp(this,52)));
        song.addView(songRow);UiTheme.space(song,12);
        songMetadata=UiTheme.caption(activity,"旋律练习  ·  约 2 分 36 秒");songMetadata.setTextColor(UiTheme.TEXT);song.addView(songMetadata);
        song.addView(UiTheme.caption(activity,"跟随灯光，把喜欢的旋律弹出来。"));
        songSwitch=addButton(song,"切换至内置《晴天》",new Runnable(){public void run(){host.selectUploaded(!uploadedSelected);}},UiTheme.Style.GHOST,false);
        songSwitch.setVisibility(View.GONE);addCard(song);

        LinearLayout player=UiTheme.card(activity);
        player.addView(UiTheme.section(activity,"开始练习"));
        player.addView(UiTheme.caption(activity,"练习方式"));
        practiceMode=new Spinner(activity);
        practiceMode.setAdapter(UiTheme.spinnerAdapter(activity,new String[]{"弹对再走","固定跟拍"}));
        practiceMode.setSelection(saved.getBoolean("waitForKey",true)?0:1);UiTheme.spinner(practiceMode);
        practiceMode.setContentDescription("练习方式，弹对再走或固定跟拍");player.addView(practiceMode);editors.add(practiceMode);
        final TextView modeExplainer=UiTheme.caption(activity,practiceMode.getSelectedItemPosition()==0?"按对后继续；同音请松键再按。":"灯光按节奏前进，跟着拍点弹奏。");player.addView(modeExplainer);
        // Put the daily actions before optional tempo and transpose controls.
        LinearLayout controls=new LinearLayout(activity);
        controls.setOrientation(getResources().getConfiguration().fontScale>1.2f?VERTICAL:HORIZONTAL);
        startButton=addButton(controls,"开始练习",new Runnable(){public void run(){startFromTop();}},UiTheme.Style.PRIMARY);
        startButton.setContentDescription("开始练习，写入灯位和设置后，FPGA预备4拍再开始跟灯");
        stopButton=addButton(controls,"停止跟灯",new Runnable(){public void run(){if(uploadedSelected||host.uploadedStopRequired())host.stopUploaded();else stopSunny();}},UiTheme.Style.SECONDARY);
        player.addView(controls);
        startHint=UiTheme.caption(activity,"");UiTheme.compactDetail(startHint,"练习提示",3);UiTheme.space(player,6);player.addView(startHint);
        practiceOptions=new LinearLayout(activity);practiceOptions.setOrientation(VERTICAL);practiceOptions.setVisibility(View.GONE);
        practiceFold=new Button(activity);practiceFold.setText("速度与移调  ›");UiTheme.ghost(practiceFold);
        practiceFold.setOnClickListener(new View.OnClickListener(){public void onClick(View view){setPracticeExpanded(practiceOptions.getVisibility()!=View.VISIBLE);}});
        player.addView(practiceFold,new LayoutParams(-1,-2));player.addView(practiceOptions);
        practiceOptions.addView(UiTheme.eyebrow(activity,"练习速度"));
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
        practiceOptions.addView(tempoRow);
        speedDetail=UiTheme.caption(activity,"");practiceOptions.addView(speedDetail);
        speed=new SeekBar(activity);speed.setMax(100);speed.setProgress(Math.max(50,Math.min(150,saved.getInt("speed",100)))-50);
        speed.setContentDescription("练习速度，50%到150%，开始时应用");UiTheme.seek(speed);practiceOptions.addView(speed);editors.add(speed);
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
        practiceOptions.addView(rates);UiTheme.space(practiceOptions,14);
        speedExplainer=UiTheme.caption(activity,"50%慢练为75 BPM。弹对再走时，速度只影响开头的预备拍。");practiceOptions.addView(speedExplainer);
        LinearLayout shiftRow=UiTheme.row(activity);
        shiftRow.addView(UiTheme.body(activity,"移调 · 半音"),new LayoutParams(0,-2,1));
        transpose=numberBox("练习移调（-24..24半音）",sunnyShift);transpose.setGravity(android.view.Gravity.CENTER);
        shiftRow.addView(transpose,new LayoutParams(UiTheme.dp(this,88),-2));practiceOptions.addView(shiftRow);
        shiftHint=UiTheme.caption(activity,"MIDI 48..72 键盘建议 -2；设置在开始时应用。");practiceOptions.addView(shiftHint);
        status=UiTheme.caption(activity,"" );status.setVisibility(View.GONE);UiTheme.compactDetail(status,"练习状态",2);status.setTextIsSelectable(true);player.addView(status);addCard(player);

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
        undoButton=addButton(calibration,"撤回上一步键位校准",new Runnable(){public void run(){undoKey();}},UiTheme.Style.SECONDARY,false);
        addButton(calibration,"重置灯带校准",new Runnable(){public void run(){confirmReset();}},UiTheme.Style.GHOST,false);
        calibration.addView(UiTheme.caption(activity,"撤回只针对最近一次保存的琴键灯位；重置清空25键及节拍灯。两者只修改手机，板端原映射不会改变，重新校准后需写入乐器。"));
        calibration.addView(calibrationFeedback,new LayoutParams(-1,-2));
        beatIndex=number(calibration,"独立节拍灯编号（先用-1：只亮板上节拍LED）",saved.getInt("beatIndex",-1));
        UiTheme.space(calibration,16);calibration.addView(UiTheme.section(activity,"03  写入乐器"));
        calibration.addView(UiTheme.caption(activity,"写入会先停止练习，并同时应用上方选择的速度、移调和4拍预备。"));
        writeMappingButton=addButton(calibration,"写入全部校准灯位",new Runnable(){public void run(){prepare(false);}},UiTheme.Style.SECONDARY);
        copyButton=addButton(calibration,"复制校准JSON（用于下次编入FPGA）",new Runnable(){public void run(){copyProfile();}},UiTheme.Style.GHOST,false);
        calibration.addView(UiTheme.caption(activity,"保存只改手机。写入FPGA后本次供电期间可用S0开始、S1停止；S4复位或断电后需重新写入。扫描会先停止练习。若要上电直接S0开始，需把校准JSON编入FPGA。"));
        addCard(card);

        diagnostics=new LinearLayout(activity);diagnostics.setOrientation(VERTICAL);
        diagnostics.addView(UiTheme.caption(activity,"手动检查跟灯接口；日常练习会随操作检查。"));
        addButton(diagnostics,"检查138K指引接口",new Runnable(){public void run(){send(Collections.singletonList(TutorialProtocol.probe()),"138K内置指引接口已回应；接下来校准灯位。灯带与节奏仍需实板确认。");}},UiTheme.Style.SECONDARY);
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
        transpose.addTextChangedListener(new android.text.TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){if(uploadedSelected&&!suppressShift){uploadedShift=s.toString();host.uploadedShiftChanged(uploadedShift);}}
            public void afterTextChanged(android.text.Editable text){}
        });
        android.text.TextWatcher mappingWatcher=new android.text.TextWatcher(){
            public void beforeTextChanged(CharSequence s,int start,int count,int after){}
            public void onTextChanged(CharSequence s,int start,int before,int count){host.refresh();}
            public void afterTextChanged(android.text.Editable text){}
        };
        firstNote.addTextChangedListener(mappingWatcher);ledCount.addTextChangedListener(mappingWatcher);
        practiceMode.setOnItemSelectedListener(new android.widget.AdapterView.OnItemSelectedListener(){
            public void onNothingSelected(android.widget.AdapterView<?> parent){}
            public void onItemSelected(android.widget.AdapterView<?> parent,View view,int position,long id){modeExplainer.setText(position==0?"按对后继续；同音请松键再按。":"灯光按节奏前进，跟着拍点弹奏。");refresh();}
        });
        updateSelectedKey();updateCalibrationSummary();
    }
    void setScoreContext(Score original,Score part,boolean selected,boolean loaded,boolean playing){
        selected=selected&&original!=null;
        boolean sourceChanged=selected!=uploadedSelected,scoreChanged=original!=contextOriginal;
        if(!sourceChanged&&!scoreChanged&&part==contextPart&&loaded==contextLoaded&&playing==contextPlaying)return;
        if(sourceChanged&&!uploadedSelected)try{sunnyShift=number(transpose);}catch(RuntimeException ignored){}
        if(scoreChanged)uploadedShift="0";
        uploadedSelected=selected;contextOriginal=original;contextPart=part;contextLoaded=loaded;contextPlaying=playing;
        if(sourceChanged||scoreChanged){suppressShift=true;transpose.setText(selected?uploadedShift:String.valueOf(sunnyShift));suppressShift=false;}
        songSwitch.setVisibility(original==null?View.GONE:View.VISIBLE);
        songSwitch.setText(selected?"切换至内置《晴天》":"切换至已载入曲谱");
        if(selected){
            Score shown=part!=null?part:original;int notes=0;for(Score.Event e:shown.events)if(e.velocity>0)notes++;
            songEyebrow.setText("当前曲目");songTitle.setTextSize(24);songTitle.setText(shown.name);
            songSubtitle.setText(playing?"练习已开始 · 换曲前请先停止":loaded?"准备好了，开始练习吧":"已载入 · 请先上传到乐器");
            songMetadata.setText(notes+" 音符  ·  原速约 "+String.format(java.util.Locale.US,"%.1f",shown.durationMs/1000.0)+" 秒");
            speedExplainer.setText("速度按曲首 BPM 显示；弹对再走时只影响预备拍，固定跟拍按所选速度执行。");
            shiftHint.setText("下载曲谱默认不移调；更改半音后需重新上传，灯位覆盖以下方提示为准。");
        }else{
            songEyebrow.setText("内置曲谱");songTitle.setTextSize(30);songTitle.setText("晴天");songSubtitle.setText("社区旋律练习版");songMetadata.setText("旋律练习  ·  约 2 分 36 秒");
            speedExplainer.setText("50%慢练为75 BPM。弹对再走时，速度只影响开头的预备拍。");shiftHint.setText("MIDI 48..72 键盘建议 -2；设置在开始时应用。");
        }
        updateSpeed();
    }
    View diagnosticsView(){return diagnostics;}
    void setPracticeExpanded(boolean expanded){practiceOptions.setVisibility(expanded?View.VISIBLE:View.GONE);practiceFold.setText(expanded?"收起速度与移调  ⌃":"速度与移调  ›");}
    void startSelectedUploaded(){if(!uploadedSelected)host.selectUploaded(true);prepare(true);}
    boolean sunnyMayBeRunning(){return sunnyMayBeRunning;}
    boolean sunnyPlaying(){return sunnyPlaying;}
    void confirmSunnyStopped(){sunnyPlaying=false;rememberSunnyMayRun(false);}
    void stopSunny(){send(Collections.singletonList(TutorialProtocol.stop()),"FPGA已确认停止指引；正常琴键演奏保持可用。");}
    private void rememberSunnyMayRun(boolean value){sunnyMayBeRunning=value;activity.getSharedPreferences("sunny-session-safety-v1",Context.MODE_PRIVATE).edit().putBoolean("stopRequired",value).apply();}
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
    private void setStatus(String text){status.setText(text);status.setVisibility(View.VISIBLE);calibrationFeedback.setText(text);calibrationFeedback.setTextColor(UiTheme.MUTED);}
    private void updateSpeed(){
        int value=speed.getProgress()+50,twice=value*3;
        if(uploadedSelected&&contextOriginal!=null){double bpm=60000.0*value/(100.0*contextOriginal.firstBeatMs);speedLabel.setText(bpm==Math.rint(bpm)?String.valueOf((int)bpm):String.format(java.util.Locale.US,"%.1f",bpm));}
        else speedLabel.setText(twice%2==0?String.valueOf(twice/2):twice/2+".5");
        speedLabel.setTextSize(speedLabel.length()>5?28:(getResources().getConfiguration().fontScale>1.2f?44:48));
        speedLabel.setContentDescription("练习速度 "+speedLabel.getText()+" BPM");
        speedDetail.setText((uploadedSelected?"BPM（曲首）  ·  ":"BPM  ·  ")+value+"%"+(value==100?" 原速":" 练习速度")+(getResources().getConfiguration().fontScale>1.2f?" · 4拍预备":""));
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
        String problem=null;try{validateSettings();mapping();if(!uploadedSelected)TutorialProtocol.checkRange(number(firstNote),number(transpose));}catch(RuntimeException ex){problem=ex.getMessage();}
        if(problem!=null&&done==0&&keyIndices[0]<0&&problem.startsWith("第1键"))problem="首次使用，请逐键保存灯位（包含黑键）";
        calibrationCount.setText(done+" / 25");calibrationCount.setTextColor(problem==null?UiTheme.SUCCESS:UiTheme.WARNING);
        calibrationSummary.setText("手机灯位 "+done+"/25 · "+(problem==null?"已备齐，可写入或开始练习。":problem+"。"));
        calibrationSummary.setTextColor(UiTheme.MUTED);
        updateSelectedKey();return problem==null;
    }
    private void persist(){
        if(!uploadedSelected)sunnyShift=number(transpose);
        SharedPreferences.Editor edit=saved.edit().putInt("speed",speed.getProgress()+50)
            .putInt("transpose",sunnyShift).putInt("ledCount",number(ledCount))
            .putInt("firstNote",number(firstNote)).putInt("beatIndex",number(beatIndex)).putBoolean("waitForKey",practiceMode.getSelectedItemPosition()==0);
        for(int i=0;i<25;i++)edit.putInt("key"+i,keyIndices[i]);
        edit.putInt("undoKey",undoKey).putInt("undoValue",undoValue).apply();
    }
    private List<byte[]> mapping(){return TutorialProtocol.profile(ledCount(),number(firstNote),keyIndices,number(beatIndex));}
    int keyPlanFirst(){validateSettings();mapping();return number(firstNote);}
    boolean[] calibratedNotes(){
        boolean[] notes=new boolean[128];int first=optionalNumber(firstNote),count=optionalNumber(ledCount);
        if(first<0||first>103||count<25||count>160)return notes;
        for(int i=0;i<25;i++)if(keyIndices[i]>=0&&keyIndices[i]<count)notes[first+i]=true;
        return notes;
    }
    private void startFromTop(){
        try{prepare(true);}catch(RuntimeException ex){
            String message=ex.getMessage()==null?"无法开始练习，请检查蓝牙、曲谱和灯位。":ex.getMessage();
            setStatus(message);startHint.setText(message);startHint.setTextColor(UiTheme.WARNING);host.log("开始练习："+message);
            new AlertDialog.Builder(activity).setTitle("暂不能开始练习").setMessage(message).setPositiveButton("知道了",null).show();
        }
    }
    void showStartProblem(String message){
        setStatus(message);startHint.setText(message);startHint.setTextColor(UiTheme.WARNING);
        Toast.makeText(activity,"开始练习未成功，请查看开始按钮下方提示",Toast.LENGTH_LONG).show();
    }
    private void prepare(boolean start){
        validateSettings();
        List<byte[]> profile=mapping();int shift=number(transpose),rate=speed.getProgress()+50;
        boolean forUploaded=start&&uploadedSelected,wait=practiceMode.getSelectedItemPosition()==0;
        if(forUploaded){if(!host.uploadedReady())throw new IllegalStateException("请先上传当前所选曲谱和移调，再开始练习。");String issue=host.uploadedProblem(wait);if(issue!=null)throw new IllegalArgumentException(issue);}
        if(!uploadedSelected)TutorialProtocol.checkRange(number(firstNote),shift);
        byte[] settings=TutorialProtocol.settings(rate,4,uploadedSelected?sunnyShift:shift);
        persist();List<byte[]> frames=new ArrayList<>();frames.add(TutorialProtocol.probe());frames.add(TutorialProtocol.stop());
        frames.add(TutorialProtocol.mode(practiceMode.getSelectedItemPosition()==0));
        frames.add(settings);frames.addAll(profile);frames.add(TutorialProtocol.calibrationComplete());
        if(start&&!forUploaded)frames.add(TutorialProtocol.start());
        String snapshot=(practiceMode.getSelectedItemPosition()==0?"弹对再走，相同音需松键再按。":"固定跟拍。")+"灯数"+number(ledCount)+"，最低MIDI "+number(firstNote)+"，速度"+rate+"%，移调"+shift+"。";
        final String message=(forUploaded?"灯位已写入，正在准备所选曲谱。":start?"准备完成，4 拍预备后开始练习。":"灯位与设置已写入乐器；复位或断电后需重新写入。")+snapshot;
        host.beforeDeviceChange(new Runnable(){public void run(){
            pendingUploadedStart=forUploaded;pendingSpeed=rate;pendingWait=wait;
            try{send(frames,message,true);}catch(RuntimeException ex){pendingUploadedStart=false;throw ex;}
        }});
    }
    private void scan(int delta){
        int count=ledCount(),index=number(scanIndex)+delta;
        if(index<0||index>=count)throw new IllegalArgumentException("定位灯编号超出所填灯数");
        scanIndex.setText(String.valueOf(index));
        host.beforeDeviceChange(new Runnable(){public void run(){send(Arrays.asList(TutorialProtocol.probe(),TutorialProtocol.stop(),TutorialProtocol.scan(true,index)),"定位灯命令已确认：编号"+index+"；请看实物确认位置。");}});
    }
    private void saveKey(){
        validateSettings();int at=key.getSelectedItemPosition(),index=number(scanIndex),count=ledCount();
        if(index<0||index>=count)throw new IllegalArgumentException("灯位越界");
        for(int i=0;i<25;i++)if(i!=at&&keyIndices[i]==index)throw new IllegalArgumentException("此灯已用于第"+(i+1)+"键");
        undoKey=at;undoValue=keyIndices[at];keyIndices[at]=index;persist();int done=0;for(int value:keyIndices)if(value>=0)done++;
        setStatus("手机已保存第"+(at+1)+"键 → 灯"+index+"（从DIN端数第"+(index+1)+"颗），共"+done+"/25键；尚未写入FPGA。");
        Toast.makeText(activity,"手机校准已修改",Toast.LENGTH_SHORT).show();
        if(at<24)key.setSelection(at+1);
        refresh();host.refresh();
    }
    private void undoKey(){
        if(undoKey<0)throw new IllegalStateException("没有可撤回的键位保存记录");
        int at=undoKey,previous=undoValue;keyIndices[at]=previous;undoKey=-1;undoValue=-1;
        saved.edit().putInt("key"+at,previous).putInt("undoKey",-1).putInt("undoValue",-1).apply();
        key.setSelection(at);if(previous>=0)scanIndex.setText(String.valueOf(previous));
        setStatus("已撤回第"+(at+1)+"键的上次保存；手机灯位已更新，板端原映射不变，需重新写入。");Toast.makeText(activity,"手机校准已修改",Toast.LENGTH_SHORT).show();refresh();host.refresh();
    }
    private void confirmReset(){
        new AlertDialog.Builder(activity).setTitle("重置手机灯带校准？")
            .setMessage("将清空手机保存的25键灯位和节拍灯，并清除撤回记录；灯数、MIDI、速度和移调保留。板端原映射不变，重新校准后需写入乐器。")
            .setNegativeButton("取消",null).setPositiveButton("重置",new DialogInterface.OnClickListener(){public void onClick(DialogInterface dialog,int which){
                BleTransport ble=host.transport();
                if(closed||busy()||host.otherBusy()||(ble!=null&&ble.isSending())){setStatus("传输进行中，未重置手机校准；请等待结束后重试。");return;}
                Arrays.fill(keyIndices,-1);undoKey=-1;undoValue=-1;
                SharedPreferences.Editor edit=saved.edit().putInt("beatIndex",-1).putInt("undoKey",-1).putInt("undoValue",-1);
                for(int i=0;i<25;i++)edit.putInt("key"+i,-1);edit.apply();
                beatIndex.setText("-1");key.setSelection(0);
                setStatus("手机25键及节拍灯校准已清空；板端原映射不变，重新校准后需写入乐器。");Toast.makeText(activity,"手机校准已修改",Toast.LENGTH_SHORT).show();refresh();host.refresh();
            }}).show();
    }
    private void copyProfile(){
        validateSettings();mapping();StringBuilder text=new StringBuilder("{\"led_count\":").append(number(ledCount)).append(",\"keys\":{");
        for(int i=0;i<25;i++){if(i>0)text.append(',');text.append('"').append(number(firstNote)+i).append("\":").append(keyIndices[i]);}
        text.append("},\"beat_led\":");int beat=number(beatIndex);text.append(beat<0?"null":String.valueOf(beat));
        TutorialProtocol.checkRange(number(firstNote),uploadedSelected?sunnyShift:number(transpose));persist();
        text.append(",\"speed_percent\":").append(speed.getProgress()+50).append(",\"count_in_beats\":4,\"transpose\":").append(sunnyShift).append('}');
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
        boolean editable=!closed&&!busy()&&!host.otherBusy()&&!sunnyPlaying&&(ble==null||!ble.isSending());
        for(Button button:buttons)button.setEnabled(enabled);for(Button button:localButtons)button.setEnabled(editable);
        for(View editor:editors)editor.setEnabled(editable);
        startButton.setEnabled(enabled&&valid&&!sunnyPlaying&&(!uploadedSelected||host.uploadedReady()));writeMappingButton.setEnabled(enabled&&valid&&!sunnyPlaying);copyButton.setEnabled(editable&&valid);
        // An unresolved uploaded-practice session must remain stoppable after a
        // reconnect or Activity recreation, even when the selected song is Sunny.
        if(uploadedSelected||host.uploadedStopRequired())stopButton.setEnabled(!closed&&!busy()&&host.canStopUploaded()&&ble!=null&&ble.isReady()&&!ble.isSending());
        undoButton.setEnabled(editable&&undoKey>=0);
        detailsButton.setEnabled(!closed);
        startHint.setTextColor(UiTheme.MUTED);
        if(busy())startHint.setText("正在发送指引命令；如需立即停止，请按板上 S1。");
        else if(uploadedSelected&&host.uploadedPlaying())startHint.setText("曲谱练习已开始；请先点停止，再换曲或修改设置。");
        else if(sunnyPlaying)startHint.setText("《晴天》练习已开始；请先点停止，再换曲或修改设置。");
        else if(host.otherBusy()||(ble!=null&&ble.isSending()))startHint.setText("请等待当前传输结束，再开始练习。");
        else if(ble==null||!ble.isReady())startHint.setText("先连接乐器。灯位可提前保存在手机。");
        else if(!valid)startHint.setText("请先完成下方25键灯位校准，再开始练习。");
        else if(uploadedSelected&&!host.uploadedReady())startHint.setText(host.uploadedStopRequired()||sunnyMayBeRunning?"请先上传当前曲谱；上传时会自动确认结束上次指引。":"请先在“曲谱上传与选项”中上传曲目；更改范围或移调后需重新上传。");
        else if(uploadedSelected&&practiceMode.getSelectedItemPosition()==0&&host.uploadedProblem(true)!=null){
            startHint.setText(host.uploadedProblem(true));startHint.setTextColor(UiTheme.WARNING);
        }else startHint.setText(host.uploadedStopRequired()||sunnyMayBeRunning?"准备好了。开始新练习时会先确认结束上次指引，再预备 4 拍。":"准备好了。开始后预备 4 拍，再跟着灯光弹奏。");
    }
    private void send(List<byte[]> frames,String message){
        send(frames,message,false);
    }
    private void send(List<byte[]> frames,String message,boolean calibration){
        if(!available())throw new IllegalStateException("请先连接蓝牙并等待当前传输结束");
        transfer.start(frames);completedMessage=message;pendingRefusal=null;calibrationTransfer=calibration;completionConfirmed=false;epoch++;refresh();host.refresh();sendCurrent();
    }
    private void sendCurrent(){
        if(!busy()||closed)return;final int token=epoch;
        final String step=commandLabel(transfer.command());
        if(transfer.command()==0x70&&(transfer.current()[3]&255)==1)rememberSunnyMayRun(true);
        setStatus("正在准备乐器 · "+(transfer.done()+1)+" / "+transfer.total());
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
            case 0x77:return "确认整套校准完成0x77";
            default:return "命令0x"+Integer.toHexString(command);}
    }
    public void onProgress(BleTransport.SendProgress progress){if(!busy())return;if(progress.cancelled){fail("发送已取消",true);return;}if(progress.finished){transfer.written();if(pendingRefusal!=null)fail(pendingRefusal,false);else advance();}}
    public void onReply(ReplyDecoder.Reply reply){
        if(!busy()||pendingRefusal!=null||reply.capabilities!=null||reply.reliable!=null)return;
        if(reply.command==transfer.command()&&reply.status!=0){
            if(reply.command==0x70&&(transfer.current()[3]&255)==1)confirmSunnyStopped();
            // ScoreTransfer.reply() cancels on errors. Keep it owning the local
            // completion until both sides have finished this rejected frame.
            String text="指引命令被拒绝：0x"+Integer.toHexString(reply.command)+"，状态"+reply.status+"；停止练习后核对灯数、参数和配套138K程序。";
            if(reply.command==0x70)text="板端拒绝指引命令0x70：请先将 FPGA 屏幕从 PRACTICE 切回 PLAY，并关闭其他练习或伴奏；也请核对配套 FPGA。蓝牙连接保留。";
            if(reply.command==0x76)text="板端未接受练习方式0x76；需要配套的等键练习版138K程序，并先停止其他曲谱指引。练习尚未开始，手机灯位和蓝牙连接保留。";
            if(reply.command==0x77&&reply.status==1)text="板端拒绝校准完成通知0x77：可能是旧版FPGA不支持，或当前状态不允许。之前的校准帧已逐帧确认，但未收到整套完成确认；未发送开始指引。";
            if(transfer.isWritten())fail(text,false);else{pendingRefusal=text;setStatus("板端已拒绝，等待本地发送收尾；蓝牙连接将保留。");}
            return;
        }
        try{if(transfer.reply(reply.command,reply.status))advance();}
        catch(RuntimeException ex){fail("指引传输状态异常："+ex.getMessage()+"；请重连后检查接口。",true);}
    }
    private void advance(){
        if(!transfer.canAdvance())return;if(timeout!=null)handler.removeCallbacks(timeout);
        if(calibrationTransfer&&transfer.command()==0x77){completionConfirmed=true;Toast.makeText(activity,"灯带校准修改完成",Toast.LENGTH_SHORT).show();}
        if(transfer.command()==0x70){sunnyPlaying=(transfer.current()[3]&255)==1;rememberSunnyMayRun(sunnyPlaying);}
        transfer.advance();if(busy())sendCurrent();else{boolean startUploaded=pendingUploadedStart;pendingUploadedStart=false;setStatus(completedMessage);host.log(completedMessage);refresh();host.refresh();if(startUploaded)host.startUploaded(pendingSpeed,pendingWait);}
    }
    private void fail(String text,boolean disconnect){
        if(calibrationTransfer)text+=completionConfirmed?" 校准完成通知已确认，但后续操作未确认。":" 校准整体未确认，板端可能已有部分更改；请重新完整写入。";
        epoch++;pendingRefusal=null;pendingUploadedStart=false;transfer.cancel();if(timeout!=null)handler.removeCallbacks(timeout);
        host.log(text);BleTransport ble=host.transport();
        if(disconnect&&ble!=null)ble.disconnect(text);setStatus(text);refresh();host.refresh();
    }
    public void disconnected(){sunnyPlaying=false;boolean incomplete=calibrationTransfer&&busy()&&!completionConfirmed;epoch++;pendingRefusal=null;pendingUploadedStart=false;transfer.cancel();handler.removeCallbacksAndMessages(null);setStatus(incomplete?"蓝牙已断开；校准整体未确认，板端可能已有部分更改。手机灯位保留，重连后请重新完整写入。":"蓝牙已断开；若练习已经开始，FPGA会继续，S1可停止。手机灯位保留，重连后重新写入或开始。");calibrationTransfer=false;refresh();}
    public void sendError(String text){if(busy())fail(text,true);}
    public void close(){closed=true;epoch++;transfer.cancel();handler.removeCallbacksAndMessages(null);}
}
