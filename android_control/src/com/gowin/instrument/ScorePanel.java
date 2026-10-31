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
    private Button legacyFold;
    private TextView legacyHint;
    private final TextView description,status,capabilityHint,uploadHint;private final ProgressBar progress;
    private final Button probe,play,stop,cancel,importButton,load;
    private Button upload,volumeApply,volumeMute,volumeRestore;
    private Button resumeReliable,releaseReliable,recoverReliable;
    private final Spinner songs,mode;
    private SeekBar volumeBar;
    private TextView volumeValue,volumeHint;
    private Score score;private boolean capable,loaded,started,closed,parsing,advancing;private int epoch,loadEpoch,operation;
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
    private long capabilityNonce;
    private final java.security.SecureRandom queryRandom=new java.security.SecureRandom();
    private boolean uploadAfterAbort;
    private String reliablePeer;
    private int reliableSendSerial;
    private boolean recovering,recoveryWritten;
    private long recoverySession;
    private ReliableScoreProtocol.Reply recoveryReply;
    private static final String[] MODES={"9600 · 快速（至少30ms）","9600 · 兼容（确认后40ms）","115200 · 逐帧确认（兼容）","115200 · 批量提速（每组最多8事件）","115200 · 可靠v2（累计确认 / 可续传）","自动提速（推荐，按板端能力选择）"};
    private static final String[] SONG_NAMES={"欢乐颂 · 四部合声","致爱丽丝 · 钢琴","晴天 · 社区旋律测试","你离开的真相 · 上半段（1/2）","你离开的真相 · 下半段（2/2）","你离开的真相 · 完整版（需足够板端容量）"};
    private static final String[] FILES={"scores/ode_to_joy.mid","scores/fur_elise.mid","scores/sunny_melody_test.mid","scores/the_truth_that_you_leave_part1.mid","scores/the_truth_that_you_leave_part2.mid","scores/the_truth_that_you_leave_full.mid"};
    public ScorePanel(Activity activity,Host host){
        super(activity);this.activity=activity;this.host=host;setOrientation(VERTICAL);
        tutorial=new TutorialPanel(activity,new TutorialPanel.Host(){
            public BleTransport transport(){return host.transport();}
            public boolean otherBusy(){return !host.tutorialEnabled()||transfer.busy()||reliable.busy()||recovering||parsing||started||closed;}
            public void log(String text){host.log(text);}
            public void refresh(){ScorePanel.this.refresh();host.refresh();}
            public void exportLedMap(String csv){host.exportLedMap(csv);}
        });
        addCard(tutorial);
        LinearLayout legacyCard=UiTheme.card(activity);
        legacyCard.addView(UiTheme.section(activity,"MIDI曲谱与自动演奏"));
        legacyHint=UiTheme.caption(activity,"");legacyCard.addView(legacyHint);
        legacyFold=makeButton("展开MIDI上传与自动演奏",new Runnable(){public void run(){setLegacyExpanded(legacyContent.getVisibility()!=View.VISIBLE);}});
        UiTheme.button(legacyFold,UiTheme.Style.SECONDARY);padTop(legacyFold);legacyCard.addView(legacyFold);
        addCard(legacyCard);
        legacyContent=new LinearLayout(activity);legacyContent.setOrientation(VERTICAL);legacyContent.setVisibility(View.GONE);
        addView(legacyContent);UiTheme.gap(legacyContent);
        // 卡1：当前曲目与状态
        LinearLayout currentCard=UiTheme.card(activity);
        currentCard.addView(UiTheme.section(activity,"当前曲目"));
        currentCard.addView(UiTheme.caption(activity,"自动演奏由FPGA发声。138K需新版曲谱程序，并先检测曲谱接口；内置《晴天》跟灯练习仍在上方，无需上传。"));
        description=UiTheme.body(activity,"尚未载入曲目");currentCard.addView(description);
        progress=new ProgressBar(activity,null,android.R.attr.progressBarStyleHorizontal);UiTheme.progress(progress);padTop(progress);currentCard.addView(progress);
        status=UiTheme.caption(activity,"选择曲目或导入 MIDI 后上传到乐器。");
        status.setMaxLines(4);status.setEllipsize(android.text.TextUtils.TruncateAt.END);status.setTextIsSelectable(true);
        status.setOnClickListener(new View.OnClickListener(){public void onClick(View view){new android.app.AlertDialog.Builder(activity).setTitle("曲谱状态详情").setMessage(status.getText()).setPositiveButton("知道了",null).show();}});
        currentCard.addView(status);
        capabilityHint=UiTheme.caption(activity,"可解析8192事件 · MIDI ≤1 MiB；未检测板端时按2048事件、8声部限制上传。");currentCard.addView(capabilityHint);
        currentCard.addView(UiTheme.caption(activity,"Truth完整版与两段均保留，按检测容量上传；曲谱断电后需重传。点状态可看完整详情。"));
        addCard(currentCard);
        // 卡2：曲目来源
        LinearLayout sourceCard=UiTheme.card(activity);
        sourceCard.addView(UiTheme.section(activity,"曲目来源"));
        songs=new Spinner(activity);songs.setAdapter(UiTheme.spinnerAdapter(activity,SONG_NAMES));UiTheme.spinner(songs);sourceCard.addView(songs);
        load=makeButton("载入所选内置曲谱",new Runnable(){public void run(){loadAsset(songs.getSelectedItemPosition());}});UiTheme.button(load,UiTheme.Style.SECONDARY);padTop(load);sourceCard.addView(load);
        importButton=makeButton("导入 MIDI (.mid)",new Runnable(){public void run(){Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);intent.setType("*/*");intent.addCategory(Intent.CATEGORY_OPENABLE);try{activity.startActivityForResult(intent,IMPORT_MIDI);}catch(RuntimeException ex){host.log("无法打开文件选择器："+ex);}}});UiTheme.button(importButton,UiTheme.Style.SECONDARY);padTop(importButton);sourceCard.addView(importButton);
        addCard(sourceCard);
        // 卡3：上传与演奏
        LinearLayout playCard=UiTheme.card(activity);
        playCard.addView(UiTheme.section(activity,"上传与演奏"));
        uploadHint=UiTheme.caption(activity,"");playCard.addView(uploadHint);
        upload=makeButton("上传当前曲谱",new Runnable(){public void run(){
            prepareUpload();}});
        playCard.addView(upload);
        play=makeButton("FPGA开始演奏",new Runnable(){public void run(){begin(0x53,Collections.singletonList(Score.command(0x53)),false);}});padTop(play);playCard.addView(play);
        stop=makeButton("FPGA停止演奏",new Runnable(){public void run(){begin(0x54,Collections.singletonList(Score.command(0x54)),false);}});padTop(stop);playCard.addView(stop);
        LinearLayout miscRow=row();
        probe=makeButton("检测接口 / 容量",new Runnable(){public void run(){uploadAfterProbe=false;begin(0x55,Collections.singletonList(Score.command(0x55)),false);}});miscRow.addView(probe,weighted());
        cancel=makeButton("取消上传 / 断开连接",new Runnable(){public void run(){fail("已取消，需重新连接并上传",true);}});miscRow.addView(cancel,weighted());
        padTop(miscRow);playCard.addView(miscRow);
        resumeReliable=makeButton("查询 / 继续此前可靠曲谱",new Runnable(){public void run(){resumeReliable();}});UiTheme.button(resumeReliable,UiTheme.Style.SECONDARY);padTop(resumeReliable);playCard.addView(resumeReliable);
        releaseReliable=makeButton("释放此前可靠会话",new Runnable(){public void run(){uploadAfterAbort=false;abortReliable();}});UiTheme.button(releaseReliable,UiTheme.Style.GHOST);padTop(releaseReliable);playCard.addView(releaseReliable);
        recoverReliable=makeButton("恢复可靠接口（重开App后检测无回复时）",new Runnable(){public void run(){recoverReliableInterface();}});UiTheme.button(recoverReliable,UiTheme.Style.GHOST);padTop(recoverReliable);playCard.addView(recoverReliable);
        addCard(playCard);
        // 卡4：总音量
        buildVolumeControls();
        // 卡5：上传设置（折叠）
        LinearLayout modeBox=new LinearLayout(activity);modeBox.setOrientation(VERTICAL);
        modeBox.addView(UiTheme.caption(activity,"上传节奏（开始上传后锁定，传输中不可切换）"));
        mode=new Spinner(activity);mode.setAdapter(UiTheme.spinnerAdapter(activity,MODES));UiTheme.spinner(mode);modeBox.addView(mode);
        mode.setSelection(5);
        modeBox.addView(UiTheme.caption(activity,"推荐自动提速：新版138K检测通过后批量发送，每组最多8个事件；模块支持时使用无响应写，整组板端回信与最终CRC校验仍必须通过。不支持批量时保留逐帧确认；上传中断需整曲重传。加法音色固件才提供可靠v2续传。选择模式不改硬件。换曲或重播前先停止。保持供电可脱离手机播放，断电不保存。曲谱保留原始音高和节奏，鼓轨忽略，延音转换为音符时长。Sunny跟灯的移调和速度不会改变这里的自动演奏；自动演奏和跟灯练习不能同时运行。"));
        collapsible("上传设置 · 节奏与说明",modeBox,false);
        emphasize();refresh();
    }
    private LinearLayout row(){LinearLayout r=new LinearLayout(activity);r.setOrientation(HORIZONTAL);return r;}
    private LayoutParams weighted(){LayoutParams p=new LayoutParams(0,-2,1f);p.setMarginStart(UiTheme.dp(this,4));p.setMarginEnd(UiTheme.dp(this,4));return p;}
    private void padTop(View v){LayoutParams p=new LayoutParams(-1,v instanceof SeekBar?UiTheme.dp(v,48):-2);p.topMargin=UiTheme.dp(v,10);v.setLayoutParams(p);}
    private void addCard(View card){(legacyContent==null?this:legacyContent).addView(card);UiTheme.gap(card);}
    void addLegacySource(View view){addCard(view);}
    void setLegacyExpanded(boolean expanded){legacyContent.setVisibility(expanded?View.VISIBLE:View.GONE);legacyFold.setText(expanded?"收起MIDI上传与自动演奏":"展开MIDI上传与自动演奏");}
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
    void emphasize(){UiTheme.button(upload,UiTheme.Style.PRIMARY);UiTheme.button(play,UiTheme.Style.PRIMARY);UiTheme.button(stop,UiTheme.Style.DANGER);UiTheme.button(probe,UiTheme.Style.GHOST);UiTheme.button(cancel,UiTheme.Style.GHOST);}
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
        addCard(volumeCard);
        updateVolumeLabel();
    }
    private int pendingVolume(){int value=volumeBar.getProgress();if(value<0)value=0;if(value>127)value=127;volumeValue0=value;return value;}
    private void updateVolumeLabel(){volumeValue.setText("当前选择 "+percent(volumeValue0)+"（0..127 → 0..100%，不自动发送）");}
    private String percent(int value){return (value*100/127)+"%";}
    private Button makeButton(String label,final Runnable action){Button b=new Button(activity);b.setText(label);b.setOnClickListener(new View.OnClickListener(){public void onClick(View v){action.run();}});return b;}
    public boolean busy(){return transfer.busy()||reliable.busy()||recovering||tutorial.busy();}
    public boolean uploading(){return busy()&&operation==0x52;}
    public boolean canLoadDownloaded(){BleTransport b=host.transport();return !closed&&!busy()&&!parsing&&!started&&(b==null||!b.isSending());}
    public boolean loadDownloaded(final String name,byte[] bytes){
        if(!canLoadDownloaded()||bytes==null||bytes.length>Score.MAX_BYTES)return false;
        final byte[] snapshot=bytes.clone();
        parseAsync(name,new Input(){public InputStream open(){return new ByteArrayInputStream(snapshot);}});
        return true;
    }
    public void refresh(){BleTransport b=host.transport();boolean available=host.scoreEnabled()&&!closed&&b!=null&&b.isReady()&&!b.isSending()&&!busy();boolean uploading=busy()&&operation==0x52; // Upload owns the frame slot and the mode; volume stays usable while playing.
        tutorial.refresh();
        uploadHint.setText(b==null||!b.isReady()?"先在连接页连接蓝牙。":busy()?"正在传输，请等待本次命令结束。":started?"重播或换曲前，先点“FPGA停止演奏”。":!capable&&!host.legacyEnabled()?"上传尚未开放：先点下方“检测接口 / 容量”；旧版138K需先升级FPGA程序。":score==null?"先载入内置曲谱或导入MIDI，再上传。":"曲谱已载入；上传确认后，再点“FPGA开始演奏”。");
        legacyHint.setText(host.legacyEnabled()?"已选择曲谱 / 加法音色用途。需要板端支持对应协议；MIDI下载、解析、上传和自动演奏分别操作。":capable?"138K曲谱接口已回应，可载入、上传，再点FPGA开始演奏。先停止上方跟灯练习；总音量请用乐器屏幕调节。":"先连接蓝牙，再点“检测接口 / 容量”。检测通过后可上传；若板端拒绝，需由你烧入新版138K程序。上方跟灯练习与这里自动演奏分开操作。");
        probe.setEnabled(available);upload.setEnabled(available&&(host.legacyEnabled()||capable)&&score!=null&&!parsing&&!started);play.setEnabled(available&&capable&&loaded&&!started);stop.setEnabled(available&&capable);cancel.setEnabled(transfer.busy()||reliable.busy()||recovering);load.setEnabled(!busy()&&!parsing&&!started);importButton.setEnabled(!busy()&&!parsing&&!started);songs.setEnabled(!busy()&&!parsing&&!started);mode.setEnabled(!busy()&&!parsing);volumeBar.setEnabled(host.legacyEnabled()&&!closed&&!busy());volumeApply.setEnabled(available&&host.legacyEnabled());volumeMute.setEnabled(available&&host.legacyEnabled());volumeRestore.setEnabled(available&&host.legacyEnabled());
        resumeReliable.setEnabled(available&&host.legacyEnabled()&&sameReliablePeer()&&reliable.canResume()&&!started);releaseReliable.setEnabled(available&&host.legacyEnabled()&&sameReliablePeer()&&reliable.hasSession()&&!started);recoverReliable.setEnabled(available&&host.legacyEnabled()&&!reliable.hasSession());}
    private void begin(int operation,List<byte[]> frames,boolean fast){BleTransport b=host.transport();if(!host.scoreEnabled()||b==null||!b.isReady()||b.isSending()||busy())return;
        if(operation==0x52){
            waitSamples=0;readyWaitTotalMs=localWaitTotalMs=ackWaitTotalMs=readyWaitMaxMs=0;
            priorityRequested=b.requestTransferPriority(true);
            host.log(priorityRequested?"曲谱上传：已请求BLE高优先级，是否生效取决于手机和模块。":"曲谱上传：BLE高优先级请求未提交，继续使用当前连接参数。");
        }
        try{transfer.start(frames,operation==0x52&&uploadMode==3,capabilities);}catch(RuntimeException ex){releaseTransferPriority();uploadTimed=false;status.setText("曲谱传输准备失败："+ex.getMessage());host.log(status.getText().toString());refresh();host.refresh();return;}
        this.operation=operation;probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;status.setText(operation==0x56?"正在发送音量，等待FPGA确认。":transfer.windowed()?"窗口上传：每组回复收齐后继续，最终等待数量/CRC校验。":"逐帧等待FPGA确认；上传不自动重试。");progress.setMax(frames.size());progress.setProgress(0);refresh();host.refresh();sendCurrent();
    }
    private void begin(int operation,List<byte[]> frames){begin(operation,frames,false);}
    private void prepareUpload(){
        if(score==null||busy())return;
        uploadMode=mode.getSelectedItemPosition();
        if(reliable.hasSession()){uploadAfterAbort=true;abortReliable();return;}
        if(!capable||!capabilitiesChecked||uploadMode==4){uploadAfterProbe=true;begin(0x55,Collections.singletonList(Score.command(0x55)),false);return;}
        startUpload();
    }
    private void startUpload(){
        uploadAfterProbe=false;
        try{capabilities.checkUpload(score);}catch(IllegalArgumentException ex){status.setText(ex.getMessage());host.log(ex.getMessage());refresh();host.refresh();return;}
        if(uploadMode==5){uploadMode=capabilities.recommendedUploadMode();host.log("自动提速选择："+MODES[uploadMode]+"；"+capabilities.description());}
        if(uploadMode==4){
            if(capabilities.reliableSupported()){startReliable();return;}
            uploadMode=capabilities.recommendedUploadMode();host.log("板端未声明可靠v2，改用："+MODES[uploadMode]+"；保留当前容量限制。");
        }
        loaded=false;windowNoResponse=false;uploadStartElapsed=SystemClock.elapsedRealtime();uploadTimed=true;uploadElapsedMs=0;
        List<byte[]> f=new ArrayList<byte[]>();f.add(Score.command(0x55));f.addAll(score.uploadFrames());begin(0x52,f,false);
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
        status.setText("已收到校验有效的可靠查询回复（状态"+recoveryReply.status+"），可重新检测接口、停止演奏。此回复不表示曲谱上传成功；App重启遗失的旧会话不能续传，若旧会话仍占用，需由你重启板端后重新上传。");
        host.log(status.getText().toString());refresh();host.refresh();
    }
    private void startReliable(){
        long session;do{session=queryRandom.nextLong();}while(session==0);
        try{reliable.start(score,capabilities,session);}catch(RuntimeException ex){status.setText(ex.getMessage());refresh();return;}
        reliablePeer=host.transport().peerAddress();operation=0x52;loaded=false;epoch++;advancing=false;
        uploadStartElapsed=SystemClock.elapsedRealtime();uploadElapsedMs=0;uploadTimed=true;priorityRequested=host.transport().requestTransferPriority(true);
        progress.setMax(reliable.total());progress.setProgress(reliable.done());refresh();host.refresh();sendReliableCurrent();
    }
    private void resumeReliable(){
        if(busy()||!reliable.canResume())return;
        if(!sameReliablePeer()){status.setText("请先连接此前上传的同一蓝牙设备，再继续会话。");return;}
        try{reliable.resume();}catch(RuntimeException ex){status.setText(ex.getMessage());return;}
        score=reliable.score();description.setText("继续此前曲目："+score.name+" · "+score.events.size()+"事件");
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
                if(reliable.completed()){loaded=true;capable=true;status.setText("可靠曲谱封存成功："+reliable.total()+"事件，累计位置与整曲CRC一致。本次运行耗时"+uploadElapsedMs+" ms；声音与无线稳定性请在实板确认。");}
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
            fail("曲谱传输超时："+transfer.waitingSummary()+" elapsed="+(SystemClock.elapsedRealtime()-sentAtElapsed)
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
        if(operation==0x53&&r.command==0x53&&r.status==1&&r.capabilities==null&&r.reliable==null&&transfer.command()==0x53){
            playRefusal="板端拒绝开始演奏：请先停止跟灯练习，确认当前曲谱已完整上传；若仍在清理音符，稍后再试。蓝牙连接和已上传曲谱保留。";
            if(transfer.isWritten())finishPlayRefusal();else status.setText("开始演奏被拒绝，等待本地发送收尾后保留连接。");
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
        if(timeout!=null)main.removeCallbacks(timeout);started=false;status.setText(message);host.log(message);refresh();host.refresh();
    }
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
            else {if(operation==0x52){loaded=true;
                    if(uploadTimed){uploadElapsedMs=SystemClock.elapsedRealtime()-uploadStartElapsed;uploadTimed=false;}
                    releaseTransferPriority();
                    status.setText("曲谱上传完成："+(transfer.windowed()?"各组回复已收齐，板端数量/CRC校验通过（ACK无序号）。":"所有帧已确认，板端CRC校验通过。")+"本次上传实测耗时"+uploadElapsedMs+" ms（"+transfer.total()+"帧，平均"+averageFrameMs()+" ms/帧）；模式："+modeName()+"。\n"+waitSummary()+"\n可开始演奏。");}
                else if(operation==0x55){queryCapabilities();return;}
                else if(operation==0x57){finishCapabilities();return;}
                else if(operation==0x53){started=true;status.setText("FPGA已接受开始演奏。请通过板上喇叭确认声音；重播或换曲前先点停止。本版尚无板端播放结束通知。");}
                else if(operation==0x56){status.setText("FPGA已确认音量 "+percent(volumeValue0)+" 已排队（ACK 0），声音是否变化需听板上喇叭；未改动曲谱与播放状态。");}
                else {started=false;status.setText("FPGA已接受停止并清理音符，释放尾音可能仍持续。");}
                host.log(status.getText().toString());refresh();host.refresh();}
        }},delay);
    }
    private String modeName(){return MODES[uploadMode]+(uploadMode==3?(windowNoResponse?" · 蓝牙无响应写":" · 蓝牙带响应写"):"");}
    private String averageFrameMs(){return transfer.total()>0?String.valueOf(uploadElapsedMs/transfer.total()):"未知";}
    private String waitSummary(){return (transfer.windowed()?"每组从提交起等待：":"每帧从提交起等待：")+"GATT写完成平均"+(waitSamples==0?0:localWaitTotalMs/waitSamples)+"ms；FPGA ACK平均"+(waitSamples==0?0:ackWaitTotalMs/waitSamples)+"ms；两者齐全平均"+(waitSamples==0?0:readyWaitTotalMs/waitSamples)+"ms，最长"+readyWaitMaxMs+"ms。两种等待会重叠，不能相加。";}
    private void releaseTransferPriority(){if(!priorityRequested)return;priorityRequested=false;BleTransport b=host.transport();if(b!=null)b.requestTransferPriority(false);}
    public void disconnected(){tutorial.disconnected();priorityRequested=false;recovering=false;probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;uploadTimed=false;uploadAfterProbe=false;uploadAfterAbort=false;capabilitiesChecked=false;capabilities=ScoreCapabilities.legacy();capabilityHint.setText("未检测板端：按2048事件、8声部限制上传。");transfer.cancel();reliable.pause();capable=false;loaded=false;started=false;if(timeout!=null)main.removeCallbacks(timeout);status.setText(reliable.canResume()?"蓝牙已断开；连接同一设备后可查询 / 继续可靠曲谱，板端复位则需重新上传。":"蓝牙已断开；FPGA可继续演奏。重连后先检测接口、点停止，再重新上传；重开App后检测无回复可恢复可靠接口。");refresh();}
    public void sendError(String message){if(tutorial.busy()){tutorial.sendError(message);return;}if(busy())fail(message,false);}
    private void fail(String message,boolean disconnect){releaseTransferPriority();recovering=false;probeRefused=false;volumeRefusal=null;playRefusal=null;epoch++;advancing=false;uploadTimed=false;uploadAfterProbe=false;uploadAfterAbort=false;transfer.cancel();reliable.pause();loaded=false;if(timeout!=null)main.removeCallbacks(timeout);status.setText(message);host.log(message);BleTransport b=host.transport();if(disconnect&&b!=null)b.disconnect(message);refresh();host.refresh();}
    public boolean activityResult(int request,int result,Intent data){if(request!=IMPORT_MIDI)return false;if(result!=Activity.RESULT_OK||data==null||data.getData()==null)return true;final android.net.Uri uri=data.getData();parseAsync("导入曲谱",new Input(){public InputStream open()throws IOException{return activity.getContentResolver().openInputStream(uri);}});return true;}
    private interface Input{InputStream open()throws IOException;}
    private void loadAsset(final int index){parseAsync(SONG_NAMES[index],new Input(){public InputStream open()throws IOException{return activity.getAssets().open(FILES[index]);}});}
    private void parseAsync(final String name,final Input source){if(!canLoadDownloaded())return;parsing=true;final int token=++loadEpoch;refresh();host.refresh();status.setText("正在解析MIDI…");worker.execute(new Runnable(){public void run(){try(InputStream in=source.open()){if(in==null)throw new IOException("无法打开文件");ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buf=new byte[4096];int n;while((n=in.read(buf))!=-1){if(bytes.size()+n>Score.MAX_BYTES)throw new IOException("文件超过1 MiB");bytes.write(buf,0,n);}final Score parsed=Score.fromMidi(name,bytes.toByteArray());main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;parsing=false;score=parsed;loaded=false;description.setText(parsed.name+"\n"+parsed.events.size()+"事件；"+String.format(Locale.US,"%.1f",parsed.durationMs/1000.0)+"秒；最大"+parsed.peakVoices+"同时音符；音域MIDI "+parsed.minNote+".."+parsed.maxNote+"\n"+String.format(Locale.US,"%.1f",(parsed.events.size()+3)*12/1024.0)+" KiB上传数据；推荐自动提速。上传时间在完成后实测显示，曲目时长指演奏长度。");status.setText("曲谱已解析，尚未上传。");refresh();host.refresh();}});}catch(final Exception ex){main.post(new Runnable(){public void run(){if(closed||loadEpoch!=token)return;parsing=false;status.setText("MIDI导入失败："+ex.getMessage());host.log(status.getText().toString());refresh();host.refresh();}});}}});}
    public void close(){tutorial.close();releaseTransferPriority();closed=true;epoch++;loadEpoch++;transfer.cancel();reliable.pause();main.removeCallbacksAndMessages(null);worker.shutdownNow();}
}
