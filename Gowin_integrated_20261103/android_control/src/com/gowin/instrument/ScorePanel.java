package com.gowin.instrument;

import android.app.Activity;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.widget.*;
import android.view.View;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

/** Incremental score UI. Actual sound and timing are entirely in the FPGA. */
public final class ScorePanel extends LinearLayout {
    public static final int IMPORT_MIDI=1010;
    public interface Host {
        BleTransport transport();void log(String message);void refresh();
        default void openLibrary(){}
        default void openSettings(){}
        default boolean legacyEnabled(){return true;}
        default boolean tutorialEnabled(){return true;}
        default boolean scoreEnabled(){return legacyEnabled();}
        default void exportLedMap(String csv){throw new IllegalStateException("当前窗口没有文件导出入口，可先复制明细");}
    }
    private final Activity activity;private final Host host;
    private final Handler main=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final ScoreTransfer transfer=new ScoreTransfer();
    private final ReliableScoreTransfer reliable=new ReliableScoreTransfer();
    private final TutorialPanel tutorial;
    private LinearLayout legacyContent;
    private LinearLayout sourceActions,diagnostics;
    private Button legacyFold;
    private TextView legacyHint;
    private TextView midiDiagnostic;
    private final TextView description,status,capabilityHint,uploadHint,coverageHint,segmentHint;private final ProgressBar progress;
    private final Button probe,guide,stop,cancel,importButton;
    private Button upload,volumeApply,volumeMute,volumeRestore;
    private Button resumeReliable,releaseReliable,recoverReliable;
    private final Spinner mode,segment;
    private final CheckBox playableOnlyChoice,mapChoice;
    private SeekBar volumeBar;
    private TextView volumeValue,volumeHint;
    private Score score,segmentSource,segmentScore,segmentUnfiltered;private int segmentIndex,segmentCacheIndex=-1,selectedTranspose,segmentCacheTranspose;
    private Score mappedScore;private byte[] sourceMidi;private boolean mapSelected,suppressMapChoice;
    private boolean playableOnly,segmentCachePlayableOnly,suppressPlayableChoice;private boolean[] segmentCacheMask;
    private int selectedNoteCount,skippedNoteCount;private String skippedPitches="";
    private boolean uploadedSelected,uploadedShiftValid=true;private String shiftError;
    private boolean capable,loaded,started,closed,parsing,advancing;private int epoch,loadEpoch,operation;
    private boolean needsStopAfterDisconnect;
    private Runnable afterConfirmedStop;
    private boolean stopIncludesSunny;
    private Runnable timeout;
    private int uploadMode;private int volumeValue0,lastNonZeroVolume;
    private long sentAtElapsed,uploadStartElapsed,uploadElapsedMs;
    private boolean uploadTimed;
    private boolean windowNoResponse;
    private long localWaitMs,ackWaitMs,readyWaitTotalMs,localWaitTotalMs,ackWaitTotalMs,readyWaitMaxMs;
    private int waitSamples;
    private boolean priorityRequested;
    private ScoreCapabilities capabilities=ScoreCapabilities.legacy();
    private boolean capabilitiesChecked,uploadAfterProbe;
    private boolean probeRefused;
    private String volumeRefusal;
    private String playRefusal;
    private String uploadFailureDetail;
    private long capabilityNonce;
    private final java.security.SecureRandom queryRandom=new java.security.SecureRandom();
    private boolean uploadAfterAbort;
    private String reliablePeer;
    private int reliableSendSerial;
    private boolean recovering,recoveryWritten;
    private long recoverySession;
    private ReliableScoreProtocol.Reply recoveryReply;
    private static final String[] MODES={"9600 · 快速（至少30ms）","9600 · 兼容（确认后40ms）","115200 · 逐帧确认（推荐）","115200 · 批量提速（需链路实测）","115200 · 可靠v2（累计确认 / 可续传）","自动提速（需链路实测）"};
    private static final String[] SEGMENTS={"完整曲谱","前 1/2（按事件数量）","前 1/4（按事件数量）","前 1/8（按事件数量）"};
    private static final int[] SEGMENT_DIVISORS={1,2,4,8};
    public ScorePanel(Activity activity,Host host){
        super(activity);this.activity=activity;this.host=host;setOrientation(VERTICAL);
        diagnostics=new LinearLayout(activity);diagnostics.setOrientation(VERTICAL);
        needsStopAfterDisconnect=activity.getSharedPreferences("score-session-safety-v1",android.content.Context.MODE_PRIVATE).getBoolean("stopRequired",false);
        tutorial=new TutorialPanel(activity,new TutorialPanel.Host(){
            public BleTransport transport(){return host.transport();}
            public boolean otherBusy(){return !host.tutorialEnabled()||transfer.busy()||reliable.busy()||recovering||parsing||started||closed;}
            public void log(String text){host.log(text);}
            public void refresh(){ScorePanel.this.refresh();host.refresh();}
            public void exportLedMap(String csv){host.exportLedMap(csv);}
            public void selectUploaded(boolean selected){if(score!=null&&!busy()&&!started&&!tutorial.sunnyPlaying()){uploadedSelected=selected;ScorePanel.this.refresh();host.refresh();}}
            public void uploadedShiftChanged(String value){changeUploadedShift(value);}
            public boolean uploadedReady(){return capable&&loaded&&selectedScore()!=null&&!needsStopAfterDisconnect;}
            public boolean uploadedPlaying(){return started;}
            public boolean uploadedStopRequired(){return started||needsStopAfterDisconnect;}
            public boolean canStopUploaded(){return host.scoreEnabled()&&!closed&&!parsing&&!transfer.busy()&&!reliable.busy()&&!recovering;}
            public String uploadedProblem(boolean wait){String missing=uncoveredNotes(selectedScore());return wait&&!missing.isEmpty()?"弹对再走所需音高未被当前手机校准覆盖：MIDI "+missing+"。可勾选下方“只练已校准琴键”并重新上传，或调整移调；固定跟拍时这些音不会亮灯。":null;}
            public void startUploaded(int speed,boolean wait){startUploadedPractice(speed,wait);}
            public void stopUploaded(){stopUploadedSession(null);}
            public void beforeDeviceChange(Runnable ready){ScorePanel.this.beforeDeviceChange(ready);}
        });
        addCard(tutorial);
        LinearLayout legacyCard=UiTheme.card(activity);
        LinearLayout libraryRow=UiTheme.row(activity);libraryRow.addView(UiTheme.section(activity,"选择曲目"),new LayoutParams(0,-2,1));
        Button library=makeButton("我的曲库  ›",new Runnable(){public void run(){host.openLibrary();}});
        UiTheme.ghost(library);libraryRow.addView(library,new LayoutParams(-2,-2));legacyCard.addView(libraryRow);
        sourceActions=UiTheme.row(activity);UiTheme.space(legacyCard,8);legacyCard.addView(sourceActions);
        legacyHint=UiTheme.caption(activity,"");diagnostics.addView(legacyHint);
        legacyFold=makeButton("曲谱上传与选项  ›",new Runnable(){public void run(){setLegacyExpanded(legacyContent.getVisibility()!=View.VISIBLE);}});
        UiTheme.button(legacyFold,UiTheme.Style.GHOST);padTop(legacyFold);legacyCard.addView(legacyFold);
        addCard(legacyCard);
        legacyContent=new LinearLayout(activity);legacyContent.setOrientation(VERTICAL);legacyContent.setVisibility(View.GONE);
        addView(legacyContent);UiTheme.gap(legacyContent);
        // 卡1：当前曲目与状态
        LinearLayout currentCard=UiTheme.card(activity);
        currentCard.addView(UiTheme.section(activity,"准备曲谱"));
        description=UiTheme.body(activity,"尚未载入曲目");currentCard.addView(description);
        progress=new ProgressBar(activity,null,android.R.attr.progressBarStyleHorizontal);UiTheme.progress(progress);padTop(progress);currentCard.addView(progress);
        status=UiTheme.caption(activity,"选择曲目或导入 MIDI 后上传到乐器。");
        status.setMaxLines(4);status.setEllipsize(android.text.TextUtils.TruncateAt.END);status.setTextIsSelectable(true);
        status.setOnClickListener(new View.OnClickListener(){public void onClick(View view){new android.app.AlertDialog.Builder(activity).setTitle("曲谱状态详情").setMessage(status.getText()).setPositiveButton("知道了",null).show();}});
        currentCard.addView(status);
        capabilityHint=UiTheme.caption(activity,"可解析8192事件 · MIDI ≤1 MiB；未检测板端时按2048事件、8声部限制上传。");diagnostics.addView(capabilityHint);
        midiDiagnostic=UiTheme.caption(activity,"");midiDiagnostic.setVisibility(View.GONE);diagnostics.addView(midiDiagnostic);
        currentCard.addView(UiTheme.caption(activity,"上传后在下方开始练习；乐器断电后需要重新上传。"));
        UiTheme.compactDetail(description,"MIDI 解析详情",3);
        addCard(currentCard);
        // 卡2：曲目来源
        importButton=makeButton("导入 MIDI",new Runnable(){public void run(){Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);intent.setType("*/*");intent.addCategory(Intent.CATEGORY_OPENABLE);try{activity.startActivityForResult(intent,IMPORT_MIDI);}catch(RuntimeException ex){host.log("无法打开文件选择器："+ex);}}});
        importButton.setContentDescription("从手机文件导入 MIDI 曲谱");UiTheme.button(importButton,UiTheme.Style.SECONDARY);LayoutParams importLayout=new LayoutParams(0,-2,1);importLayout.setMarginStart(UiTheme.dp(this,8));sourceActions.addView(importButton,importLayout);
        // 卡3：上传与演奏
        LinearLayout playCard=UiTheme.card(activity);
        playCard.addView(UiTheme.section(activity,"安排这次练习"));
        uploadHint=UiTheme.caption(activity,"");playCard.addView(uploadHint);
        coverageHint=UiTheme.caption(activity,"");playCard.addView(coverageHint);
        UiTheme.compactDetail(coverageHint,"琴键覆盖详情",3);
        mapChoice=new CheckBox(activity);mapChoice.setText("一键多音 · 自动分配 25 键");
        mapChoice.setTextColor(UiTheme.TEXT);mapChoice.setMinHeight(UiTheme.dp(this,48));
        mapChoice.setButtonTintList(android.content.res.ColorStateList.valueOf(UiTheme.PRIMARY));
        playCard.addView(mapChoice,new LayoutParams(-1,-2));
        playCard.addView(UiTheme.caption(activity,"适合超出键盘音域的曲谱。生成后请确认配对与映射范围。"));
        mapChoice.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener(){public void onCheckedChanged(CompoundButton button,boolean checked){
            if(suppressMapChoice)return;
            if(busy()||parsing||started||closed){suppressMapChoice=true;mapChoice.setChecked(mapSelected);suppressMapChoice=false;return;}
            if(checked)prepareMappedScore();
            else {mapSelected=false;mappedScore=null;segmentSource=null;loaded=false;status.setText("已关闭一键多音，需重新上传。");refresh();host.refresh();}
        }});
        playableOnlyChoice=new CheckBox(activity);
        playableOnlyChoice.setText("只练已校准琴键（跳过其他音符）");
        playableOnlyChoice.setTextColor(UiTheme.TEXT);playableOnlyChoice.setMinHeight(UiTheme.dp(this,48));
        playableOnlyChoice.setButtonTintList(android.content.res.ColorStateList.valueOf(UiTheme.PRIMARY));
        playCard.addView(playableOnlyChoice,new LayoutParams(-1,-2));
        playCard.addView(UiTheme.caption(activity,"默认保留全部音符；开启筛选会跳过未校准音符，更改后需重新上传。"));
        playableOnlyChoice.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener(){
            public void onCheckedChanged(CompoundButton button,boolean checked){
                if(suppressPlayableChoice)return;
                if(busy()||parsing||started||closed){
                    suppressPlayableChoice=true;playableOnlyChoice.setChecked(playableOnly);suppressPlayableChoice=false;return;
                }
                playableOnly=checked;segmentSource=null;loaded=false;updateSegmentHint();
                if(score!=null)status.setText("已更改上传内容，请重新上传后再开始练习。");
                refresh();host.refresh();
            }
        });
        playCard.addView(UiTheme.caption(activity,"本次上传范围"));
        segment=new Spinner(activity);segment.setAdapter(UiTheme.spinnerAdapter(activity,SEGMENTS));UiTheme.spinner(segment);playCard.addView(segment);
        segmentHint=UiTheme.caption(activity,"");playCard.addView(segmentHint);
        UiTheme.compactDetail(segmentHint,"本次上传范围",3);
        segment.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){
            public void onNothingSelected(AdapterView<?> parent){}
            public void onItemSelected(AdapterView<?> parent,View view,int position,long id){
                if(position==segmentIndex)return;
                if(busy()||parsing||started||closed){segment.setSelection(segmentIndex);return;}
                segmentIndex=position;segmentSource=null;loaded=false;
                updateSegmentHint();
                if(score!=null)status.setText("已更改上传范围；请重新上传所选片段后再开始指引。");
                refresh();host.refresh();
            }
        });
        upload=makeButton("上传到乐器",new Runnable(){public void run(){
            prepareUpload();}});
        playCard.addView(upload);
        // The daily practice buttons live in TutorialPanel; keep command callbacks in one owner.
        guide=makeButton("开始已上传曲谱",new Runnable(){public void run(){try{tutorial.startSelectedUploaded();}catch(RuntimeException ex){String message=ex.getMessage()==null?"无法开始练习，请检查蓝牙、曲谱和灯位。":ex.getMessage();status.setText(message);host.log(message);tutorial.showStartProblem(message);}}});
        stop=makeButton("停止曲谱灯光指引",new Runnable(){public void run(){try{if(tutorial.sunnyMayBeRunning()&&!needsStopAfterDisconnect&&!started)tutorial.stopSunny();else stopUploadedSession(null);}catch(RuntimeException ex){status.setText(ex.getMessage());host.log(ex.getMessage());}}});
        playCard.addView(UiTheme.caption(activity,"上传时会检测设备。换曲前请先停止练习；乐器屏幕保持 PLAY。"));
        probe=makeButton("检测接口 / 容量",new Runnable(){public void run(){uploadAfterProbe=false;begin(0x55,Collections.singletonList(Score.command(0x55)),false);}});diagnostics.addView(probe);
        cancel=makeButton("取消上传并断开",new Runnable(){public void run(){fail("已取消，需重新连接并上传",true);}});padTop(cancel);playCard.addView(cancel);
        resumeReliable=makeButton("查询 / 继续此前可靠曲谱",new Runnable(){public void run(){resumeReliable();}});UiTheme.button(resumeReliable,UiTheme.Style.SECONDARY);padTop(resumeReliable);diagnostics.addView(resumeReliable);
        releaseReliable=makeButton("释放此前可靠会话",new Runnable(){public void run(){uploadAfterAbort=false;abortReliable();}});UiTheme.button(releaseReliable,UiTheme.Style.GHOST);padTop(releaseReliable);diagnostics.addView(releaseReliable);
        recoverReliable=makeButton("恢复可靠接口（重开App后检测无回复时）",new Runnable(){public void run(){recoverReliableInterface();}});UiTheme.button(recoverReliable,UiTheme.Style.GHOST);padTop(recoverReliable);diagnostics.addView(recoverReliable);
        addCard(playCard);
        // 卡4：总音量
        buildVolumeControls();
        // 卡5：上传设置（折叠）
        LinearLayout modeBox=new LinearLayout(activity);modeBox.setOrientation(VERTICAL);
        modeBox.addView(UiTheme.caption(activity,"上传节奏（开始上传后锁定，传输中不可切换）"));
        mode=new Spinner(activity);mode.setAdapter(UiTheme.spinnerAdapter(activity,MODES));UiTheme.spinner(mode);modeBox.addView(mode);
        mode.setSelection(2);
        modeBox.addView(UiTheme.caption(activity,"默认逐帧确认：每帧等待本地写完成和板端回复，速度取决于手机与蓝牙模块。批量和自动提速可能受链路间隔影响，须先实测；上传中断需重新连接并重新上传所选片段。换曲或重新开始前先停止；断电后曲谱需重传。下载曲谱默认原音高，选择移调后须重传；保留节奏，鼓轨忽略，延音转换为音符时长。曲谱指引与《晴天》练习不能同时运行。"));
        diagnostics.addView(modeBox);
        diagnostics.addView(tutorial.diagnosticsView());
        // Show the current song first, with sources and upload before practice actions.
        removeView(tutorial);removeView(legacyCard);removeView(legacyContent);
        tutorial.addView(legacyCard,1);tutorial.addView(legacyContent,2);addView(tutorial);UiTheme.gap(tutorial);
        updateSegmentHint();emphasize();refresh();
    }
    private LinearLayout row(){LinearLayout r=new LinearLayout(activity);r.setOrientation(HORIZONTAL);return r;}
    private LayoutParams weighted(){LayoutParams p=new LayoutParams(0,-2,1f);p.setMarginStart(UiTheme.dp(this,4));p.setMarginEnd(UiTheme.dp(this,4));return p;}
    private void padTop(View v){LayoutParams p=new LayoutParams(-1,v instanceof SeekBar?UiTheme.dp(v,48):-2);p.topMargin=UiTheme.dp(v,10);v.setLayoutParams(p);}
    private void addCard(View card){(legacyContent==null?this:legacyContent).addView(card);UiTheme.gap(card);}
    void addSourceAction(Button button){sourceActions.addView(button,0,new LayoutParams(0,-2,1));}
    View diagnosticsView(){return diagnostics;}
    void setLegacyExpanded(boolean expanded){legacyContent.setVisibility(expanded?View.VISIBLE:View.GONE);legacyFold.setText(expanded?"收起曲谱上传与选项  ⌃":"曲谱上传与选项  ›");}
    private void collapsible(String title,final View content,boolean expanded){
        LinearLayout card=UiTheme.card(activity);
        final TextView chevron=new TextView(activity);chevron.setTextColor(UiTheme.MUTED);chevron.setTextSize(14);
        final TextView label=new TextView(activity);label.setText(title);label.setTextColor(UiTheme.TEXT);label.setTextSize(14);label.setTypeface(null,android.graphics.Typeface.BOLD);
        LinearLayout header=new LinearLayout(activity);header.setOrientation(HORIZONTAL);header.setGravity(android.view.Gravity.CENTER_VERTICAL);header.setMinimumHeight(UiTheme.dp(activity,48));
        header.addView(label,new LayoutParams(0,-2,1f));header.addView(chevron);
        chevron.setText(expanded?"▾":"▸");content.setVisibility(expanded?View.VISIBLE:View.GONE);
        header.setOnClickListener(new View.OnClickListener(){public void onClick(View v){boolean show=content.getVisibility()!=View.VISIBLE;content.setVisibility(show?View.VISIBLE:View.GONE);chevron.setText(show?"▾":"▸");}});
        card.addView(header);card.addView(content);addCard(card);
    }
    void emphasize(){UiTheme.button(upload,UiTheme.Style.PRIMARY);UiTheme.button(guide,UiTheme.Style.PRIMARY);UiTheme.button(stop,UiTheme.Style.DANGER);UiTheme.button(probe,UiTheme.Style.GHOST);UiTheme.button(cancel,UiTheme.Style.GHOST);}
    private void buildVolumeControls(){
        LinearLayout volumeCard=UiTheme.card(activity);
        volumeCard.addView(UiTheme.section(activity,"乐器总音量"));
        volumeValue=UiTheme.body(activity,"");volumeCard.addView(volumeValue);
        volumeBar=new SeekBar(activity);volumeBar.setContentDescription("FPGA总音量");volumeBar.setMax(127);volumeBar.setProgress(127);UiTheme.seek(volumeBar);padTop(volumeBar);volumeCard.addView(volumeBar);
        volumeValue0=127;lastNonZeroVolume=127;
        volumeBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onProgressChanged(SeekBar bar,int value,boolean fromUser){volumeValue0=value;if(value>0)lastNonZeroVolume=value;updateVolumeLabel();}
            public void onStartTrackingTouch(SeekBar bar){}
            public void onStopTrackingTouch(SeekBar bar){}
        });
        volumeHint=UiTheme.caption(activity,"拖动只选择数值，点按钮才发送。需配套音量版FPGA；滑块不是板端读回值。静音后已有的混响/延迟尾音会继续衰减。");volumeCard.addView(volumeHint);
        volumeApply=makeButton("应用总音量",new Runnable(){public void run(){sendVolume(pendingVolume());}});UiTheme.button(volumeApply,UiTheme.Style.SECONDARY);padTop(volumeApply);volumeCard.addView(volumeApply);
        LinearLayout volumeRow=row();padTop(volumeRow);
        volumeMute=makeButton("静音",new Runnable(){public void run(){volumeBar.setProgress(0);sendVolume(0);}});UiTheme.button(volumeMute,UiTheme.Style.SECONDARY);volumeRow.addView(volumeMute,weighted());
        volumeRestore=makeButton("恢复非零",new Runnable(){public void run(){int v=lastNonZeroVolume>0?lastNonZeroVolume:127;volumeBar.setProgress(v);sendVolume(v);}});UiTheme.button(volumeRestore,UiTheme.Style.SECONDARY);volumeRow.addView(volumeRestore,weighted());
        volumeCard.addView(volumeRow);
        // Legacy volume protocol remains supported; its controls are no longer part of the score page.
        updateVolumeLabel();
    }
    private int pendingVolume(){int value=volumeBar.getProgress();if(value<0)value=0;if(value>127)value=127;volumeValue0=value;return value;}
    private void updateVolumeLabel(){volumeValue.setText("当前选择 "+percent(volumeValue0)+"（0..127 → 0..100%，不自动发送）");}
    private String percent(int value){return (value*100/127)+"%";}
    private Button makeButton(String label,final Runnable action){Button b=new Button(activity);b.setText(label);b.setOnClickListener(new View.OnClickListener(){public void onClick(View v){action.run();}});return b;}
    public boolean busy(){return transfer.busy()||reliable.busy()||recovering||tutorial.busy();}
    public boolean uploading(){return busy()&&operation==0x52;}
    public boolean canLoadDownloaded(){BleTransport b=host.transport();return !closed&&!busy()&&!parsing&&!started&&!tutorial.sunnyPlaying()&&(b==null||!b.isSending());}
    public boolean loadDownloaded(final String name,byte[] bytes){
        return loadBytes(name,bytes,true);
    }
    public boolean loadLibraryScore(final String name,byte[] bytes){
        return loadBytes(name,bytes,false);
    }
    private boolean loadBytes(final String name,byte[] bytes,boolean save){
        if(!canLoadDownloaded()||bytes==null||bytes.length>Score.MAX_BYTES)return false;
        final byte[] snapshot=bytes.clone();
        parseAsync(name,new Input(){public InputStream open(){return new ByteArrayInputStream(snapshot);}},save);
        return true;
    }
    public void refresh(){BleTransport b=host.transport();boolean available=host.scoreEnabled()&&!closed&&b!=null&&b.isReady()&&!b.isSending()&&!busy();boolean uploading=busy()&&operation==0x52; // Upload owns the frame slot and the mode; volume stays usable while playing.
        tutorial.setScoreContext(score,selectedScore(),uploadedSelected,loaded,started);tutorial.refresh();
        updateSegmentHint();updateCoverageHint();
        uploadHint.setText(b==null||!b.isReady()?"连接乐器后，即可上传曲谱。":busy()?"正在传输，请稍候。":started||tutorial.sunnyPlaying()?"请先停止当前练习，再上传其他曲谱。":score==null?"先从曲库选择或导入一首曲谱。":needsStopAfterDisconnect||tutorial.sunnyMayBeRunning()?"上传时会先确认结束上次指引，无需手动检测或停止。":"上传后，在下方选择方式并开始练习。");
        legacyHint.setText(capable?"曲谱接口已回应。上传后可在上方选择练习方式和速度；需配套新版FPGA。":"先连接蓝牙并检测接口；下载曲谱练习需配套新版FPGA程序。");
        boolean safe=!started&&!parsing&&!tutorial.sunnyPlaying();
        probe.setEnabled(available);upload.setEnabled(available&&selectedScore()!=null&&!parsing&&safe);guide.setEnabled(available&&capable&&loaded&&selectedScore()!=null&&safe&&!needsStopAfterDisconnect);stop.setEnabled(available&&capable);cancel.setEnabled(transfer.busy()||reliable.busy()||recovering);cancel.setVisibility(busy()?View.VISIBLE:View.GONE);importButton.setEnabled(!closed&&!busy()&&!parsing&&safe);segment.setEnabled(!closed&&!busy()&&safe);playableOnlyChoice.setEnabled(!closed&&!busy()&&safe&&score!=null&&!mapSelected);mapChoice.setEnabled(!closed&&!busy()&&safe&&sourceMidi!=null);mode.setEnabled(!busy()&&!parsing);volumeBar.setEnabled(host.legacyEnabled()&&!closed&&!busy());volumeApply.setEnabled(available&&host.legacyEnabled());volumeMute.setEnabled(available&&host.legacyEnabled());volumeRestore.setEnabled(available&&host.legacyEnabled());
        resumeReliable.setEnabled(available&&host.legacyEnabled()&&sameReliablePeer()&&reliable.canResume()&&safe);releaseReliable.setEnabled(available&&host.legacyEnabled()&&sameReliablePeer()&&reliable.hasSession()&&safe);recoverReliable.setEnabled(available&&host.legacyEnabled()&&!reliable.hasSession()&&safe);}
    private void begin(int operation,List<byte[]> frames,boolean fast){
        // This app only permits score upload, guide, stop, probe and volume operations.
        if(operation!=0x52&&operation!=0x54&&operation!=0x55&&operation!=0x56&&operation!=0x57&&operation!=0x59&&operation!=0x5a)return;
        for(byte[] frame:frames)if(frame==null||frame.length!=12||(frame[2]&255)==0x53)return;
        BleTransport b=host.transport();if(!host.scoreEnabled()||b==null||!b.isReady()||b.isSending()||busy())return;
        if((operation==0x59||operation==0x5a)&&(started||needsStopAfterDisconnect))return;
        uploadFailureDetail=null;
        if(operation==0x52){
            waitSamples=0;readyWaitTotalMs=localWaitTotalMs=ackWaitTotalMs=readyWaitMaxMs=0;
            priorityRequested=b.requestTransferPriority(true);
            host.log(priorityRequested?"曲谱上传：已请求BLE高优先级，是否生效取决于手机和模块。":"曲谱上传：BLE高优先级请求未提交，继续使用当前连接参数。");
        }
        try{transfer.start(frames,operation==0x52&&uploadMode==3,capabilities);}catch(RuntimeException ex){releaseTransferPriority();uploadTimed=false;status.setText("曲谱传输准备失败："+ex.getMessage());host.log(status.getText().toString());refresh();host.refresh();return;}
        this.operation=operation;if(operation==0x59||operation==0x5a)rememberStopRequired(true);probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;status.setText(operation==0x56?"正在发送音量，等待FPGA确认。":transfer.windowed()?"窗口上传：每组回复收齐后继续，最终等待数量/CRC校验。":"逐帧等待FPGA确认；上传不自动重试。");progress.setMax(frames.size());progress.setProgress(0);refresh();host.refresh();sendCurrent();
    }
    private Score selectedScore(){
        if(score==null||!uploadedShiftValid)return null;
        if(!mapSelected&&score.fidelityIssue!=null){
            loaded=false;shiftError=score.fidelityIssue+" 请启用一键多音重新按轨检查；若检查拒绝，本 App 不会上传残缺的完整曲谱。";return null;
        }
        Score base=mapSelected?mappedScore:score;
        if(base==null)return null;
        if(mapSelected){try{if(tutorial.keyPlanFirst()!=base.mappedFirstKey)throw new IllegalArgumentException("最低实体键已改变，请关闭后重新生成一键多音映射。");}
            catch(IllegalArgumentException ex){loaded=false;shiftError=ex.getMessage();return null;}}
        boolean[] currentMask=playableOnly?tutorial.calibratedNotes():null;
        boolean mappingChanged=playableOnly&&segmentCachePlayableOnly&&segmentSource==base&&
            !Arrays.equals(currentMask,segmentCacheMask);
        if(mappingChanged&&loaded){loaded=false;status.setText("琴键校准覆盖已更改；请重新上传所选片段。");}
        if(segmentSource!=base||segmentCacheIndex!=segmentIndex||segmentCacheTranspose!=selectedTranspose||
           segmentCachePlayableOnly!=playableOnly||mappingChanged){
            segmentSource=base;segmentCacheIndex=segmentIndex;segmentCacheTranspose=selectedTranspose;
            segmentCachePlayableOnly=playableOnly;segmentCacheMask=currentMask;segmentUnfiltered=null;
            selectedNoteCount=0;skippedNoteCount=0;skippedPitches="";
            try{
                segmentUnfiltered=base.prefix(SEGMENT_DIVISORS[segmentIndex]).transposed(selectedTranspose);
                for(Score.Event e:segmentUnfiltered.events)if(e.velocity>0){
                    selectedNoteCount++;if(playableOnly&&!currentMask[e.note])skippedNoteCount++;
                }
                if(playableOnly)skippedPitches=uncoveredNotes(segmentUnfiltered);
                segmentScore=playableOnly?segmentUnfiltered.onlyPitches(currentMask):segmentUnfiltered;shiftError=null;
            }catch(IllegalArgumentException ex){segmentScore=null;shiftError=ex.getMessage();}
        }
        return segmentScore;
    }
    private void changeUploadedShift(String value){
        int shift=0;boolean valid=true;try{shift=Integer.parseInt(value.trim());valid=shift>=-24&&shift<=24;}catch(RuntimeException ex){valid=false;}
        if(valid==uploadedShiftValid&&(!valid||shift==selectedTranspose))return;
        selectedTranspose=shift;uploadedShiftValid=valid;segmentSource=null;loaded=false;shiftError=valid?null:"移调需填写 -24..24 的整数";
        updateSegmentHint();if(score!=null)status.setText(valid?"移调已更改；请重新上传后再开始练习。":"移调不合法；请填写 -24..24 的整数。");refresh();host.refresh();
    }
    private void startUploadedPractice(int speed,boolean wait){
        Score part=selectedScore();if(!uploadedSelected||part==null||!loaded||!capable||started||busy())return;
        begin(0x5a,Collections.singletonList(part.practiceCommand(speed,wait)),false);
    }
    private void updateSegmentHint(){
        Score part=selectedScore();
        if(part==null){
            segmentHint.setText(score==null?"分段从曲首开始，按事件数截取；截断处会补松键。载入曲谱后显示实际大小。":shiftError!=null?shiftError:"请填写有效的移调。");
            return;
        }
        String actual=segmentIndex!=0&&segmentUnfiltered.events.size()>=score.events.size()?"（此曲过短或同时事件过多，实际保留完整曲谱）":"";
        String filtered=playableOnly?"只练已校准琴键：保留 "+(selectedNoteCount-skippedNoteCount)+" / "+selectedNoteCount+" 个音符，跳过 "+skippedNoteCount+" 个"+(skippedPitches.isEmpty()?"":"（MIDI "+skippedPitches+"）")+"。原 MIDI 文件不变。":"保留原片段的全部音符。";
        segmentHint.setText("本次上传："+SEGMENTS[segmentIndex]+actual+"；"+part.events.size()+" / "+score.events.size()+" 事件，约 "+String.format(Locale.US,"%.1f",(part.events.size()+3)*12/1024.0)+" KiB，演奏约 "+String.format(Locale.US,"%.1f",part.durationMs/1000.0)+" 秒。"+filtered+"按事件数取曲首，保留同时事件并补松键。");
    }
    private void updateCoverageHint(){
        String prefix=selectedTranspose==0?"上传曲谱保留原 MIDI 音高，不使用《晴天》的移调；":"本次上传移调 "+selectedTranspose+" 半音；";
        prefix+="仅已校准的25键灯位能点亮。以下按所选片段统计。";
        Score part=selectedScore();
        if(part==null){coverageHint.setText(prefix+(score==null?"载入曲谱后可查看手机校准未覆盖的音高。":shiftError!=null?shiftError:"请填写有效的移调。"));return;}
        String notes=uncoveredNotes(part);
        coverageHint.setText(prefix+(notes.isEmpty()?"当前手机灯位已覆盖所选片段的上传内容。":"当前手机灯位未覆盖 MIDI："+notes+"；若板端使用此校准，这些音不会亮灯。")+"这是手机数据，不是板端读回；须先将校准写入FPGA。上传受板端复音数限制（"+(capabilities.negotiated?"板端报告 ":"未协商，暂按 ")+capabilities.voices+" 声部）。");
    }
    private String uncoveredNotes(Score part){
        if(part==null)return "";
        boolean[] mapped=tutorial.calibratedNotes(),missing=new boolean[128];
        for(Score.Event e:part.events)if(e.velocity>0&&!mapped[e.note])missing[e.note]=true;
        StringBuilder notes=new StringBuilder();for(int i=0;i<missing.length;i++)if(missing[i]){if(notes.length()>0)notes.append("、");notes.append(i);}
        return notes.toString();
    }
    private void clearMapChoice(){suppressMapChoice=true;mapChoice.setChecked(false);suppressMapChoice=false;mapSelected=false;mappedScore=null;segmentSource=null;}
    private void prepareMappedScore(){
        final int first;
        try{if(sourceMidi==null)throw new IllegalArgumentException("请先载入 MIDI");first=tutorial.keyPlanFirst();}
        catch(IllegalArgumentException ex){clearMapChoice();status.setText("无法生成映射："+ex.getMessage());refresh();host.refresh();return;}
        final byte[] midi=sourceMidi.clone();final String name=score.name;final int token=++loadEpoch;
        parsing=true;loaded=false;status.setText("正在逐轨检查 MIDI 并分配 25 键…");refresh();host.refresh();
        worker.execute(new Runnable(){public void run(){try{
            final KeyPlan.Result result=KeyPlan.fromMidi(name,midi,first);
            main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;
                String text="配对 "+result.pairedNotes+" 个音符，最多同时使用 "+result.score.peakVoices+" 个实体键；同通道跨轨同音重叠 "+result.sameChannelOverlaps+" 处。\n\n"+
                    "同音按各自轨道内的按下/松开配对；MIDI 没有实例编号，这是一种解释。练习数据调整 "+result.shiftedEvents+" 个事件，单个最多后移 1 ms；原文件不变。\n"+
                    "原曲音色种类 "+result.programs+"、其他控制 "+result.otherControls+"、弯音/压力 "+result.expression+"、系统专用事件 "+result.sysex+" 个，不保证还原这些效果；鼓轨、踏板或轨内无法配对的情况会拒绝。\n"+
                    "非零松键力度 "+result.releaseVelocities+" 个；当前映射和乐器不会还原原文件的松键力度。\n\n"+
                    "请先把当前灯位写入板端；开始前释放键盘、关闭单音连奏。实际力度和时长由你的 USB 键盘按键决定，手型和速度可行性需实测。";
                new android.app.AlertDialog.Builder(activity).setTitle("确认逐轨配对与映射范围").setMessage(text).setCancelable(false)
                    .setPositiveButton("采用此映射",new android.content.DialogInterface.OnClickListener(){public void onClick(android.content.DialogInterface d,int which){
                        parsing=false;mappedScore=result.score;mapSelected=true;playableOnly=false;suppressPlayableChoice=true;playableOnlyChoice.setChecked(false);suppressPlayableChoice=false;
                        segmentSource=null;loaded=false;status.setText("一键多音计划已生成，请确认灯位写入板端后上传。");host.log("逐轨映射："+result.pairedNotes+" 音符，重叠 "+result.sameChannelOverlaps+"，调整 "+result.shiftedEvents+" 事件；未使用非零松键力度 "+result.releaseVelocities+" 个。");refresh();host.refresh();}})
                    .setNegativeButton("取消",new android.content.DialogInterface.OnClickListener(){public void onClick(android.content.DialogInterface d,int which){parsing=false;clearMapChoice();status.setText("未采用逐轨映射。");refresh();host.refresh();}}).show();
            }});
        }catch(final Exception ex){main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;parsing=false;clearMapChoice();status.setText("一键多音检查拒绝："+ex.getMessage());host.log(status.getText().toString());refresh();host.refresh();}});}}});
    }
    private void begin(int operation,List<byte[]> frames){begin(operation,frames,false);}
    // A saved flag records an uncertain previous session, not a running device.
    // Leave connection/browsing alone; settle it only for a user-requested write.
    private void beforeDeviceChange(Runnable ready){
        BleTransport b=host.transport();
        if(closed||busy()||parsing||started||!host.scoreEnabled()||b==null||!b.isReady()||b.isSending())
            throw new IllegalStateException("请先连接乐器并等待当前操作结束；正在练习时请先停止。");
        if(needsStopAfterDisconnect||tutorial.sunnyMayBeRunning())stopUploadedSession(ready);
        else ready.run();
    }
    private void stopUploadedSession(Runnable ready){
        BleTransport b=host.transport();
        if(closed||busy()||parsing||!host.scoreEnabled()||b==null||!b.isReady()||b.isSending())return;
        List<byte[]> frames=new ArrayList<>();frames.add(Score.command(0x54));
        stopIncludesSunny=tutorial.sunnyMayBeRunning();
        if(stopIncludesSunny)frames.add(TutorialProtocol.stop());
        afterConfirmedStop=ready;
        begin(0x54,frames,false);
        if(!transfer.busy()){afterConfirmedStop=null;stopIncludesSunny=false;}
    }
    private void prepareUpload(){
        BleTransport b=host.transport();
        if(score==null||selectedScore()==null||busy()||parsing||started||tutorial.sunnyPlaying()||closed||!host.scoreEnabled()||b==null||!b.isReady()||b.isSending())return;
        beforeDeviceChange(new Runnable(){public void run(){prepareUploadAfterStop();}});
    }
    private void prepareUploadAfterStop(){
        if(!uploadedSelected){uploadedSelected=true;refresh();}
        uploadMode=mode.getSelectedItemPosition();
        if(reliable.hasSession()){uploadAfterAbort=true;abortReliable();return;}
        if(!capable||!capabilitiesChecked||uploadMode==4){uploadAfterProbe=true;begin(0x55,Collections.singletonList(Score.command(0x55)),false);return;}
        startUpload();
    }
    private void startUpload(){
        uploadAfterProbe=false;
        try{capabilities.checkUpload(selectedScore());}catch(IllegalArgumentException ex){status.setText(ex.getMessage());host.log(ex.getMessage());refresh();host.refresh();return;}
        if(uploadMode==5){uploadMode=capabilities.recommendedUploadMode();host.log("自动提速选择："+MODES[uploadMode]+"；"+capabilities.description());}
        if(selectedScore().isMapped()&&uploadMode==4){uploadMode=2;host.log("一键多音使用逐帧上传；可靠 v2 上传不承载实体键映射。");}
        if(uploadMode==4){
            if(capabilities.reliableSupported()){startReliable();return;}
            uploadMode=capabilities.negotiated&&capabilities.uartBaud>=115200?2:1;host.log("板端未声明可靠v2，改用："+MODES[uploadMode]+"；保留当前容量限制。");
        }
        loaded=false;windowNoResponse=false;uploadStartElapsed=SystemClock.elapsedRealtime();uploadTimed=true;uploadElapsedMs=0;
        List<byte[]> f=new ArrayList<byte[]>();f.add(Score.command(0x55));f.addAll(selectedScore().uploadFrames());begin(0x52,f,false);
    }
    private void queryCapabilities(){
        capabilities=ScoreCapabilities.legacy();capabilitiesChecked=false;
        do{capabilityNonce=queryRandom.nextInt()&0xffffffffL;}while(capabilityNonce==0);
        begin(0x57,Collections.singletonList(ScoreCapabilities.query(capabilityNonce)),false);
        status.setText("曲谱接口已确认，正在检测板端容量与声部数…");
    }
    private void finishCapabilities(){
        capabilitiesChecked=true;capabilityHint.setText(capabilities.description()+"；同时按住音符数不含释音尾声。");
        status.setText(capabilities.description()+(capabilities.negotiated?"。":"；旧板未提供能力回复，保持2048事件上限。"));
        host.log(status.getText().toString());refresh();host.refresh();
        if(uploadAfterProbe)startUpload();
    }
    private boolean sameReliablePeer(){BleTransport b=host.transport();return b!=null&&reliablePeer!=null&&reliablePeer.equals(b.peerAddress());}
    // A verified v2 envelope safely exits the receiver's partial-frame quarantine.
    // This query does not recover an owner session lost when Android killed the app.
    private void recoverReliableInterface(){
        BleTransport b=host.transport();if(closed||busy()||reliable.hasSession()||b==null||!b.isReady()||b.isSending())return;
        do{recoverySession=queryRandom.nextLong()&0x7f7f7f7f7f7f7f7fL;}while(recoverySession==0);
        recoveryWritten=false;recoveryReply=null;recovering=true;operation=0x64;final int token=++epoch;
        status.setText("发送可靠v2查询恢复帧，等待有效F2；此操作不上传曲谱、不接管此前会话。");refresh();host.refresh();
        timeout=new Runnable(){public void run(){if(!closed&&epoch==token&&recovering)fail("可靠接口恢复未收到有效F2；旧板可能不支持v2。请重连并按旧协议检测。",true);}};main.postDelayed(timeout,8000);
        if(!b.sendReliableScore(ReliableScoreProtocol.message(ReliableScoreProtocol.QUERY,recoverySession,0,0,new byte[0])))fail("可靠接口恢复帧未能写出",true);
    }
    private void maybeRecoveryComplete(){
        if(!recovering||!recoveryWritten||recoveryReply==null)return;
        if(timeout!=null)main.removeCallbacks(timeout);recovering=false;epoch++;capabilitiesChecked=false;capabilities=ScoreCapabilities.legacy();
        capabilityHint.setText("可靠接口已回应；请检测当前板端能力。");
        status.setText("已收到校验有效的可靠查询回复（状态"+recoveryReply.status+"），可重新检测接口、停止当前指引。此回复不表示曲谱上传成功；App重启遗失的旧会话不能续传，若旧会话仍占用，需由你重启板端后重新上传。");
        host.log(status.getText().toString());refresh();host.refresh();
    }
    private void startReliable(){
        long session;do{session=queryRandom.nextLong();}while(session==0);
        try{reliable.start(selectedScore(),capabilities,session);}catch(RuntimeException ex){status.setText(ex.getMessage());refresh();return;}
        reliablePeer=host.transport().peerAddress();operation=0x52;loaded=false;epoch++;advancing=false;
        uploadStartElapsed=SystemClock.elapsedRealtime();uploadElapsedMs=0;uploadTimed=true;priorityRequested=host.transport().requestTransferPriority(true);
        progress.setMax(reliable.total());progress.setProgress(reliable.done());refresh();host.refresh();sendReliableCurrent();
    }
    private void resumeReliable(){
        if(busy()||!reliable.canResume())return;
        if(!sameReliablePeer()){status.setText("请先连接此前上传的同一蓝牙设备，再继续会话。");return;}
        try{reliable.resume();}catch(RuntimeException ex){status.setText(ex.getMessage());return;}
        // The reliable session already stores the exact selected content, which may
        // have been filtered. Do not filter it a second time against a newer map.
        playableOnly=false;suppressPlayableChoice=true;playableOnlyChoice.setChecked(false);suppressPlayableChoice=false;
        clearMapChoice();sourceMidi=null;score=reliable.score();uploadedSelected=true;selectedTranspose=0;uploadedShiftValid=true;shiftError=null;segmentIndex=0;segment.setSelection(0);segmentSource=null;updateSegmentHint();description.setText("继续此前上传内容（可能已筛选）："+score.name+" · "+score.events.size()+"事件");
        operation=0x52;uploadMode=4;epoch++;advancing=false;uploadStartElapsed=SystemClock.elapsedRealtime();uploadTimed=true;
        priorityRequested=host.transport().requestTransferPriority(true);progress.setMax(reliable.total());progress.setProgress(reliable.done());refresh();host.refresh();sendReliableCurrent();
    }
    private void abortReliable(){
        if(!sameReliablePeer()){uploadAfterAbort=false;status.setText("此前可靠会话属于另一台蓝牙设备；请连接原设备后释放。");return;}
        try{reliable.abort();}catch(RuntimeException ex){uploadAfterAbort=false;status.setText(ex.getMessage());return;}
        operation=0x65;epoch++;advancing=false;refresh();host.refresh();sendReliableCurrent();
    }
    private void sendReliableCurrent(){
        if(closed||!reliable.busy())return;
        final int token=epoch,serial=++reliableSendSerial;
        sentAtElapsed=SystemClock.elapsedRealtime();status.setText("可靠上传："+reliable.waitingSummary());
        timeout=new Runnable(){public void run(){if(closed||epoch!=token||serial!=reliableSendSerial||!reliable.busy())return;
            try{reliable.timeout();host.log("可靠超时，按session查询/幂等重传："+reliable.waitingSummary());sendReliableCurrent();}
            catch(RuntimeException ex){fail(ex.getMessage(),true);}}};
        main.postDelayed(timeout,8000);
        if(!host.transport().sendReliableScore(reliable.current()))fail("可靠曲谱消息未能写出",true);
    }
    private void maybeReliableAdvance(){
        if(!reliable.canAdvance()||advancing)return;advancing=true;if(timeout!=null)main.removeCallbacks(timeout);final int token=epoch;
        main.postDelayed(new Runnable(){public void run(){if(closed||epoch!=token||!reliable.canAdvance())return;
            try{reliable.advance();advancing=false;progress.setProgress(reliable.done());
                if(reliable.busy()){sendReliableCurrent();return;}
                releaseTransferPriority();uploadElapsedMs=SystemClock.elapsedRealtime()-uploadStartElapsed;uploadTimed=false;
                if(reliable.completed()){loaded=true;capable=true;status.setText("可靠曲谱封存成功："+reliable.total()+"事件，累计位置与所选片段CRC一致。本次运行耗时"+uploadElapsedMs+" ms；声音与无线稳定性请在实板确认。");}
                else if(reliable.aborted()){loaded=false;capabilitiesChecked=false;status.setText("此前可靠会话已释放，可重新检测并上传。");}
                host.log(status.getText().toString());refresh();host.refresh();
                if(uploadAfterAbort){uploadAfterAbort=false;prepareUpload();}
            }catch(RuntimeException ex){advancing=false;fail(ex.getMessage(),true);}
        }},reliable.type()==ReliableScoreProtocol.QUERY?400:0);
    }
    private void sendVolume(int value){
        if(closed||busy()){status.setText("已有一次传输在处理中，请等它结束再调音量；本次音量未发送。");return;}
        byte[] frame;try{frame=Score.volume(value);}catch(RuntimeException ex){status.setText(ex.getMessage());return;}
        volumeValue0=value;if(value>0)lastNonZeroVolume=value;updateVolumeLabel();
        status.setText("已发送音量 "+percent(value)+"，等待FPGA确认（0x56）。确认只表示事件已排队，声音大小请以板上喇叭为准。");
        begin(0x56,Collections.singletonList(frame),false);
    }
    private void sendCurrent(){if(!busy()||closed)return;final int token=epoch;final int at=transfer.done();
        final boolean window=transfer.windowed()&&transfer.command()==0x51;
        final byte[] frame=window?null:transfer.current();
        sentAtElapsed=SystemClock.elapsedRealtime();
        localWaitMs=ackWaitMs=0;
        timeout=new Runnable(){public void run(){if(!closed&&busy()&&epoch==token&&transfer.done()==at){
            if(operation==0x57 && host.transport()!=null && host.transport().isReady() && !host.transport().isSending()){
                epoch++;advancing=false;transfer.cancel();capabilities=ScoreCapabilities.legacy();finishCapabilities();return;
            }
            if(operation==0x59||operation==0x5a)needsStopAfterDisconnect=true;
            fail("曲谱命令超时，板端执行状态未知："+transfer.waitingSummary()+" elapsed="+(SystemClock.elapsedRealtime()-sentAtElapsed)
                +"ms；连接已断开，不自动重试。重连检测、停止后重新上传。",true);}}};
        main.postDelayed(timeout,window?8000:3500);
        if(!(window?host.transport().sendScoreWindow(transfer.chunks(),capabilities.negotiated&&capabilities.uartBaud>=115200):host.transport().sendFrame(frame)))fail("曲谱帧未能写出",true);
    }
    public void onProgress(BleTransport.SendProgress p){if(tutorial.busy()){tutorial.onProgress(p);return;}if(!busy())return;if(p.cancelled){fail("曲谱发送被取消",false);return;}if(recovering){if(p.finished){recoveryWritten=true;maybeRecoveryComplete();}return;}if(reliable.busy()){if(p.finished){reliable.written();maybeReliableAdvance();}return;}if(transfer.windowed()&&transfer.command()==0x51&&!p.ackedByPeer())windowNoResponse=true;if(p.finished){localWaitMs=Math.max(0,SystemClock.elapsedRealtime()-sentAtElapsed);transfer.written();if(probeRefused){finishProbeRefusal();return;}if(volumeRefusal!=null){volumeIssue(volumeRefusal);return;}if(playRefusal!=null){finishPlayRefusal();return;}maybeAdvance();}}
    public void onReply(ReplyDecoder.Reply r){if(!busy())return;
        if(tutorial.busy()){tutorial.onReply(r);return;}
        if(recovering){if(r.reliable!=null&&r.reliable.session==recoverySession&&r.reliable.type==ReliableScoreProtocol.QUERY){recoveryReply=r.reliable;maybeRecoveryComplete();}return;}
        if(reliable.busy()){if(r.reliable!=null)try{if(reliable.accept(r.reliable))maybeReliableAdvance();}catch(RuntimeException ex){fail(ex.getMessage(),true);}return;}
        if(r.command==0x56&&operation==0x56){onVolumeReply(r);return;}
        // An explicit refusal of the first PROBE is not a broken BLE link.
        // Wait for its local write completion before releasing the shared frame slot.
        if((operation==0x55||operation==0x52)&&r.command==0x55&&r.status==1
                &&r.capabilities==null&&r.reliable==null&&transfer.busy()
                &&transfer.command()==0x55&&transfer.done()==0){
            probeRefused=true;
            if(transfer.isWritten())finishProbeRefusal();
            else status.setText("板端已拒绝旧曲谱接口；等待本地发送收尾后保留连接，可改用上方138K跟灯练习。");
            return;
        }
        if(probeRefused||playRefusal!=null)return;
        if(operation==0x52&&r.command==0x51&&r.status==3&&transfer.command()==0x51){
            String detail="曲谱数据帧内超时（0x51/状态3）；已完成 "+transfer.done()+" / "+transfer.total()+" 帧，本帧或本组未确认。App 已停止传输并主动断开。请重新连接、检测接口，选择“115200 · 逐帧确认”并从头上传。";
            uploadFailureDetail=detail;
            fail(detail,true);return;
        }
        if((operation==0x59||operation==0x5a)&&r.command==operation&&r.status==1&&r.capabilities==null&&r.reliable==null&&transfer.command()==operation){
            playRefusal=operation==0x5a?"板端拒绝曲谱练习0x5A：请先将 FPGA 屏幕从 PRACTICE 切回 PLAY，并关闭其他练习或伴奏；也请核对配套新版 FPGA。蓝牙和已上传曲谱保留。":"板端拒绝灯光指引0x59：固件可能不支持此功能，或曲谱/当前模式不允许。请停止其他指引并核对新版FPGA；蓝牙和已上传曲谱保留。";
            if(mapSelected)playRefusal+=" 一键多音还要求 USB 键盘已连接、所有琴键松开且滑音/单音模式关闭；乐器移调和弯音设置也会影响实际音高。";
            if(transfer.isWritten())finishPlayRefusal();else status.setText("灯光指引被拒绝，等待本地发送收尾后保留连接。");
            return;
        }
        try{
        if(operation==0x57 && r.command==0x57){
            if(r.capabilities!=null){if(r.capabilities.nonce!=capabilityNonce)return;capabilities=r.capabilities;}
            else if(r.status==1){capabilities=ScoreCapabilities.legacy();}
            else if(r.status==0)return; // A six-byte ACK cannot advertise a capacity.
            else {transfer.reply(r.command,r.status);return;}
            if(!transfer.reply(0x57,0))return;
        }else{if(r.capabilities!=null||!transfer.reply(r.command,r.status))return;}
        ackWaitMs=Math.max(0,SystemClock.elapsedRealtime()-sentAtElapsed);maybeAdvance();
    }catch(RuntimeException ex){if(r.command==0x55)capable=false;fail("曲谱失败："+ex.getMessage()+"；请确认已烧入配套曲谱版FPGA",true);}}
    private void finishPlayRefusal(){
        String message=playRefusal;playRefusal=null;epoch++;advancing=false;transfer.cancel();
        if(timeout!=null)main.removeCallbacks(timeout);started=false;rememberStopRequired(false);status.setText(message);host.log(message);refresh();host.refresh();tutorial.showStartProblem(message);
    }
    private void rememberStopRequired(boolean value){activity.getSharedPreferences("score-session-safety-v1",android.content.Context.MODE_PRIVATE).edit().putBoolean("stopRequired",value).apply();}
    private void finishProbeRefusal(){
        capable=false;capabilitiesChecked=false;capabilities=ScoreCapabilities.legacy();
        capabilityHint.setText("板端拒绝旧曲谱检测（0x55/status1），尚未确认曲谱上传能力。138K内置《晴天》请用上方跟灯练习。");
        fail("板端拒绝旧曲谱接口（0x55/status1）。若使用138K内置《晴天》，请用本页最上方“138K《晴天》跟灯练习”，先检查指引接口；无需上传。蓝牙连接已保留，曲谱未上传。",false);
    }
    private void onVolumeReply(ReplyDecoder.Reply r){
        if(volumeRefusal!=null)return;
        try{
            if(r.status==0){if(transfer.reply(r.command,r.status))maybeAdvance();return;} // 0 = queued only.
            if(r.status==1){
                String message="板端不支持音量命令或音量队列忙（status 1）。保留连接和已上传曲谱，可稍后重试；138K指引口不提供此音量控制。";
                if(transfer.isWritten())volumeIssue(message);else{volumeRefusal=message;status.setText("音量命令已拒绝，等待本地发送收尾后保留连接。");}
                return;
            }
            transfer.reply(r.command,r.status); // Error/unknown status throws.
        }catch(RuntimeException ex){fail("音量传输异常："+ex.getMessage()+"；已断开连接。",true);}
    }
    private void volumeIssue(String message){ // Volume-only failure: never touches loaded/started/capable and keeps Bluetooth up.
        volumeRefusal=null;playRefusal=null;epoch++;advancing=false;transfer.cancel();if(timeout!=null)main.removeCallbacks(timeout);
        status.setText(message);host.log(message);refresh();host.refresh();
    }
    private void maybeAdvance(){if(!transfer.canAdvance()||advancing)return;advancing=true;if(timeout!=null)main.removeCallbacks(timeout);final int token=epoch;
        if(operation==0x52){long ready=Math.max(localWaitMs,ackWaitMs);waitSamples++;readyWaitTotalMs+=ready;localWaitTotalMs+=localWaitMs;ackWaitTotalMs+=ackWaitMs;readyWaitMaxMs=Math.max(readyWaitMaxMs,ready);}
        // Both local completion and ACK are already required. Only wait for
        // the unelapsed part of start spacing; final frame has no next-frame gap.
        final long delay=transfer.done()+transfer.groupSize()<transfer.total()
            ? UploadPacing.delayAfterReady(operation==0x52?(uploadMode==3?2:uploadMode):1,sentAtElapsed,SystemClock.elapsedRealtime()) : 0;
        main.postDelayed(new Runnable(){public void run(){if(closed||epoch!=token||!transfer.canAdvance())return;int cmd=transfer.command();transfer.advance();advancing=false;progress.setProgress(transfer.done());if(cmd==0x55)capable=true;
            if(busy()){status.setText("FPGA已确认 "+transfer.done()+" / "+transfer.total()+" 帧");sendCurrent();}
            else {Runnable nextAfterStop=null;if(operation==0x52){loaded=true;
                    if(uploadTimed){uploadElapsedMs=SystemClock.elapsedRealtime()-uploadStartElapsed;uploadTimed=false;}
                    releaseTransferPriority();
                    status.setText("曲谱上传完成："+(transfer.windowed()?"各组回复已收齐，板端数量/CRC校验通过（ACK无序号）。":"所有帧已确认，板端CRC校验通过。")+"本次上传实测耗时"+uploadElapsedMs+" ms（"+transfer.total()+"帧，平均"+averageFrameMs()+" ms/帧）；模式："+modeName()+"。\n"+waitSummary()+"\n可选择开始曲谱灯光指引。");}
                else if(operation==0x55){queryCapabilities();return;}
                else if(operation==0x57){finishCapabilities();return;}
                else if(operation==0x59||operation==0x5a){started=true;status.setText("练习已开始。跟着灯光弹奏，换曲或重新开始前请先停止。");}
                else if(operation==0x56){status.setText("FPGA已确认音量 "+percent(volumeValue0)+" 已排队（ACK 0），声音是否变化需听板上喇叭；未改动曲谱与指引状态。");}
                else {started=false;needsStopAfterDisconnect=false;rememberStopRequired(false);if(stopIncludesSunny)tutorial.confirmSunnyStopped();stopIncludesSunny=false;nextAfterStop=afterConfirmedStop;afterConfirmedStop=null;status.setText("FPGA已接受停止曲谱灯光指引。");}
                host.log(status.getText().toString());refresh();host.refresh();
                if(nextAfterStop!=null)try{nextAfterStop.run();}catch(RuntimeException ex){String text="准备新练习未完成："+ex.getMessage();status.setText(text);host.log(text);tutorial.showStartProblem(text);refresh();host.refresh();}}
        }},delay);
    }
    private String modeName(){return MODES[uploadMode]+(uploadMode==3?(windowNoResponse?" · 蓝牙无响应写":" · 蓝牙带响应写"):"");}
    private String averageFrameMs(){return transfer.total()>0?String.valueOf(uploadElapsedMs/transfer.total()):"未知";}
    private String waitSummary(){return (transfer.windowed()?"每组从提交起等待：":"每帧从提交起等待：")+"GATT写完成平均"+(waitSamples==0?0:localWaitTotalMs/waitSamples)+"ms；FPGA ACK平均"+(waitSamples==0?0:ackWaitTotalMs/waitSamples)+"ms；两者齐全平均"+(waitSamples==0?0:readyWaitTotalMs/waitSamples)+"ms，最长"+readyWaitMaxMs+"ms。两种等待会重叠，不能相加。";}
    private void releaseTransferPriority(){if(!priorityRequested)return;priorityRequested=false;BleTransport b=host.transport();if(b!=null)b.requestTransferPriority(false);}
    public void disconnected(){afterConfirmedStop=null;stopIncludesSunny=false;needsStopAfterDisconnect=needsStopAfterDisconnect||started||(transfer.busy()&&(operation==0x59||operation==0x5a));tutorial.disconnected();priorityRequested=false;recovering=false;probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;uploadTimed=false;uploadAfterProbe=false;uploadAfterAbort=false;capabilitiesChecked=false;capabilities=ScoreCapabilities.legacy();capabilityHint.setText("未检测板端：按2048事件、8声部限制上传。");transfer.cancel();reliable.pause();capable=false;loaded=false;started=false;if(timeout!=null)main.removeCallbacks(timeout);status.setText(uploadFailureDetail!=null?uploadFailureDetail:needsStopAfterDisconnect?"蓝牙已断开，乐器可能仍在指引。可继续在手机选曲；下次上传或开始时会先确认结束上次指引。":reliable.canResume()?"蓝牙已断开；连接同一设备后可查询 / 继续可靠曲谱，板端复位则需重新上传。":"蓝牙已断开；重连后可重新上传；重开App后检测无回复可恢复可靠接口。");refresh();}
    public void sendError(String message){if(tutorial.busy()){tutorial.sendError(message);return;}if(busy())fail(message,false);}
    private void fail(String message,boolean disconnect){afterConfirmedStop=null;stopIncludesSunny=false;if(transfer.busy()&&(operation==0x59||operation==0x5a))needsStopAfterDisconnect=true;uploadFailureDetail=message;releaseTransferPriority();recovering=false;probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;uploadTimed=false;uploadAfterProbe=false;uploadAfterAbort=false;transfer.cancel();reliable.pause();loaded=false;if(timeout!=null)main.removeCallbacks(timeout);status.setText(message);host.log(message);BleTransport b=host.transport();if(disconnect&&b!=null)b.disconnect(message);refresh();host.refresh();}
    public boolean activityResult(int request,int result,Intent data){if(request!=IMPORT_MIDI)return false;if(result!=Activity.RESULT_OK||data==null||data.getData()==null)return true;final android.net.Uri uri=data.getData();String name="导入曲谱";
        try(android.database.Cursor cursor=activity.getContentResolver().query(uri,new String[]{android.provider.OpenableColumns.DISPLAY_NAME},null,null,null)){
            if(cursor!=null&&cursor.moveToFirst()){int column=cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);if(column>=0){String value=cursor.getString(column);if(value!=null&&!value.trim().isEmpty())name=WebMidiDownload.displayName(value);}}
        }catch(RuntimeException ex){host.log("无法读取文件名，显示为导入曲谱。");}
        parseAsync(name,new Input(){public InputStream open()throws IOException{return activity.getContentResolver().openInputStream(uri);}},true);return true;}
    private interface Input{InputStream open()throws IOException;}
    private void parseAsync(final String name,final Input source,final boolean save){
        if(!canLoadDownloaded())return;parsing=true;final int token=++loadEpoch;refresh();host.refresh();status.setText("正在解析MIDI…");
        worker.execute(new Runnable(){public void run(){boolean saved=!save;String libraryError=null;try(InputStream in=source.open()){
            if(in==null)throw new IOException("无法打开文件");ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buf=new byte[4096];int n;
            while((n=in.read(buf))!=-1){if(bytes.size()+n>Score.MAX_BYTES)throw new IOException("文件超过1 MiB");bytes.write(buf,0,n);}
            final byte[] original=bytes.toByteArray();
            if(save)try{ScoreLibrary.save(activity,original,name);saved=true;}catch(Exception ex){libraryError=ex.getMessage()==null?"无法保存":ex.getMessage();}
            final Score parsed=Score.fromMidi(name,original);
            final String saveProblem=libraryError;
            main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;
                parsing=false;clearMapChoice();sourceMidi=original;score=parsed;uploadedSelected=true;selectedTranspose=0;uploadedShiftValid=true;shiftError=null;segmentSource=null;loaded=false;
                playableOnly=false;suppressPlayableChoice=true;playableOnlyChoice.setChecked(false);suppressPlayableChoice=false;
                description.setText(parsed.name+"\n约 "+String.format(Locale.US,"%.1f",parsed.durationMs/1000.0)+" 秒"+(parsed.fidelityIssue==null?"":" · 需启用一键多音检查"));
                midiDiagnostic.setText("常规解析："+parsed.events.size()+"事件；最大"+parsed.peakVoices+"同时音符；音域MIDI "+parsed.minNote+".."+parsed.maxNote+"。常规解析可能合并同音。启用一键多音后会从原文件重新逐轨检查；原文件不变。");midiDiagnostic.setVisibility(View.VISIBLE);
                updateSegmentHint();status.setText(saveProblem==null?"曲谱已解析，文件保存在手机曲库，尚未上传。":"曲谱已解析，尚未上传；保存到曲库失败："+saveProblem);
                setLegacyExpanded(true);if(saveProblem!=null)host.log("保存到手机曲库失败："+saveProblem);refresh();host.refresh();
            }});
        }catch(final Exception ex){final boolean retained=saved;final String saveFailure=libraryError;main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;parsing=false;status.setText("MIDI导入失败："+ex.getMessage()+(retained?"；原文件保存在手机曲库。":saveFailure==null?"":"；保存到曲库失败："+saveFailure));host.log(status.getText().toString());refresh();host.refresh();}});}}});
    }
    public void close(){afterConfirmedStop=null;stopIncludesSunny=false;tutorial.close();releaseTransferPriority();closed=true;epoch++;loadEpoch++;transfer.cancel();reliable.pause();main.removeCallbacksAndMessages(null);worker.shutdownNow();}
}
