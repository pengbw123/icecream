`timescale 1ns/1ps
// Runs the real RV32I firmware against a pin-level Goodix I2C model.
module tb_touch_ui;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    tri1 scl,sda,int_pin;
    wire rst_pin,uart,valid,present;
    wire [31:0] event_word;
    wire signed [3:0] octave;
    wire [6:0] volume;
    wire visual_mode,spectrum_enable;
    wire display_auto_gain;
    wire [6:0] xy_delay;
    wire [3:0] menu_page;
    reg [15:0] pr_data=16'h0021;
    reg performance_case=0,model_glide=0;
    reg [6:0] model_preset=0;
    reg [7:0] model_voices=32;
    reg [11:0] model_glide_delay=0;
    reg model_glide_target=0;
    reg [15:0] model_glide_ms=170;
    reg [15:0] aux_words[0:1023];integer aux_count=0;
    always @(posedge clk)if(dut.command_valid&&dut.command==8'h6a)begin
        aux_words[dut.command_payload[9:0]]<=dut.command_payload[31:16];aux_count<=aux_count+1;
        if(dut.command_payload[9:0]==10'h3fc)model_glide_ms<=dut.command_payload[31:16];
    end
    initial if($test$plusargs("glide_delay"))model_glide=1;
    always @(posedge clk)if($test$plusargs("glide_delay"))begin
        if(model_glide_delay!=0)begin
            model_glide_delay<=model_glide_delay-1'b1;
            if(model_glide_delay==1)model_glide<=model_glide_target;
        end
        if(valid&&arp_test_ready&&event_word[23:16]==8'hb0&&event_word[14:8]==22)begin
            model_glide_delay<=2000;model_glide_target<=event_word[6:0]!=0;
        end
    end
    reg [15:0] captured_cells[0:4095];
    initial performance_case=$test$plusargs("performance");
    reg [47:0] preview_flags[0:31];
    initial $readmemh("src/generated/fm_algorithm_flags.mem",preview_flags);
    wire [9:0] preview_addr=dut.command_payload[9:0];
    wire [15:0] preview_response=preview_addr==0?16'd4:preview_addr==9?preview_flags[4][15:0]:
        preview_addr==10?preview_flags[4][31:16]:preview_addr==11?preview_flags[4][47:32]:pr_data;
    wire [15:0] pr_response=dut.command_payload[9:0]==10'h00d ? model_glide_ms : dut.command_payload[9:0]==10'h00c ? {15'd0,model_glide}:$test$plusargs("algo_preview")?preview_response:pr_data;
    reg pr_valid=0;
    integer cmd_69=0,cmd_60=0,cmd_61=0,cmd_62=0,cmd_63=0,cmd_64=0,cmd_65=0,cmd_70=0,text_cells=0,pal_writes=0;
    wire perf_snap,perf_clear;wire [4:0] perf_index;
    reg [31:0] perf_model[0:17];integer perf_snaps=0,perf_clears=0,freeze_snaps;
    integer pm;
    initial begin for(pm=0;pm<18;pm=pm+1)perf_model[pm]=0;
        perf_model[0]=32'h50455231;perf_model[1]=50000000;perf_model[2]=1024;perf_model[3]=1024;
        perf_model[5]={16'd700,16'd600};perf_model[6]={16'd800,16'd650};perf_model[7]={16'd900,16'd700};
        perf_model[8]=2;perf_model[9]=1;perf_model[10]=3;perf_model[11]=4;perf_model[12]=123;
        perf_model[13]=$test$plusargs("poly32")?{16'd32,8'd32,8'd32}:{16'd16,8'd16,8'd8};perf_model[14]=1234567890;
    end
    always @(posedge clk)begin
        if(perf_snap)begin perf_snaps<=perf_snaps+1;perf_model[4]<=perf_model[4]+1;end
        if(perf_clear)begin perf_clears<=perf_clears+1;perf_model[8]<=0;perf_model[9]<=0;perf_model[11]<=0;end
    end
    wire [31:0] ai_status,composer_status,composer_detail;
    reg [31:0] gesture_model=32'h00000004;
    wire [2:0] gesture_config;
    wire [31:0] composer_data;wire composer_valid;integer composer_ons=0;
    wire [31:0] test_ai_data;wire test_ai_valid;
    integer ai_note_ons=0;
    ai_bass_accompaniment test_ai(.clk(clk),.reset_n(reset_n),
        .cfg_write(dut.command_valid&&dut.command==8'h6a),.cfg_address(dut.command_payload[9:0]),
        .cfg_value(dut.command_payload[31:16]),.suspend(dut.lesson_state[16]||dut.sequencer_active||dut.arp_config[0]),
        .observe_data(event_word),.observe_valid(valid&&arp_test_ready),
        .out_data(test_ai_data),.out_valid(test_ai_valid),.out_ready(1'b1),.status(ai_status));
    always @(posedge clk)if(test_ai_valid&&test_ai_data[23:20]==9)ai_note_ons<=ai_note_ons+1;
    ai_melody_composer #(.CLOCKS_PER_US(1)) test_composer(.clk(clk),.reset_n(reset_n),
        .cfg_write(dut.command_valid&&dut.command==8'h6a),.cfg_address(dut.command_payload[9:0]),.cfg_value(dut.command_payload[31:16]),
        .suspend(dut.lesson_state[16]||dut.sequencer_active||dut.arp_config[0]||ai_status[0]),
        .observe_data(event_word),.observe_valid(valid&&arp_test_ready),.out_data(composer_data),.out_valid(composer_valid),.out_ready(1'b1),
        .status(composer_status),.detail(composer_detail));
    always @(posedge clk)if(composer_valid&&composer_data[23:20]==9)composer_ons<=composer_ons+1;
    touch_ui_controller #(.GESTURE_ENABLED(1)) dut(.clk(clk),.reset_n(reset_n),.tp_scl(scl),.tp_sda(sda),.ai_status(ai_status),.composer_status(composer_status),.composer_detail(composer_detail),
        .gesture_status(gesture_model),.gesture_detail(32'hffff8001),.gesture_config(gesture_config),
        .perf_data(perf_model[perf_index]),.perf_index(perf_index),.perf_snapshot(perf_snap),.perf_clear(perf_clear),
        .tp_int(int_pin),.tp_rst(rst_pin),.uart_tx(uart),.midi_event_data(event_word),
        .sd_miso(1'b1),.midi_event_valid(valid),.midi_event_ready(arp_test_ready),.monitor_event($test$plusargs("seq")?event_word:32'd0),
        .monitor_event_valid($test$plusargs("seq")?valid&&arp_test_ready:1'b0),.preset_index($test$plusargs("poly32")?7'd127:performance_case?model_preset:7'd0),.algorithm(5'd4),.active_voices($test$plusargs("poly32")?model_voices:8'd0),
        .touch_present(present),.keyboard_octave(octave),.master_volume(volume),
        .visual_mode(visual_mode),.spectrum_enable(spectrum_enable),.xy_delay_samples(xy_delay),.display_auto_gain(display_auto_gain),
        .command_ready(1'b1),.fx_read_value(32'd0),
        .menu_page(menu_page),.patch_read_data(pr_response),.patch_read_valid(pr_valid));
    // Physical UI data RAM is 96KiB; catch stale stack/linker assumptions.
    always @(posedge clk)if(reset_n && dut.u_cpu.w_mic_req<=2'b01 &&
        dut.u_cpu.w_mic_addr[31:28]==4'h1 &&
        (dut.u_cpu.w_mic_addr[16:0]>=17'h18000 || (dut.u_cpu.w_mic_addr[31:17]!=15'h800 && dut.u_cpu.w_mic_addr[31:17]!=15'h801)))
        $fatal(1,"UI accessed outside 96KiB RAM: %h",dut.u_cpu.w_mic_addr);
    wire [159:0] test_arp_config=dut.arp_config;
    wire [31:0] test_arp_status;
    wire [127:0] test_arp_notes;
    wire [31:0] arp_test_out;wire arp_test_valid,arp_test_ready;
    midi_arpeggiator test_arp(.clk(clk),.reset_n(reset_n),.config_data(test_arp_config),
        .suspend(dut.lesson_state[16]||dut.sequencer_active),.sequence_mode(dut.sequencer_active),.sync_step(1'b0),.sync_restart(1'b0),.external_sync(1'b0),
        .in_data(event_word),.in_brightness(event_word[6:0]),.in_valid(valid),.in_ready(arp_test_ready),
        .out_data(arp_test_out),.out_brightness(),.out_valid(arp_test_valid),.out_ready(1'b1),
        .status(test_arp_status),.chord_notes(test_arp_notes));
    initial begin force dut.arp_status=test_arp_status;force dut.arp_notes=test_arp_notes;end
    // Minimal 0x69 responder: the real synth answers two clocks after the
    // address is presented; the firmware only needs a valid response.
    reg [1:0] pr_wait=0;
    always @(posedge clk) begin
        pr_valid<=0;
        if(dut.command_valid&&dut.command==8'h69&&pr_wait==0)pr_wait<=2'd3;
        else if(pr_wait!=0)begin
            pr_wait<=pr_wait-1;
            if(pr_wait==1)pr_valid<=1;
        end
    end
    integer cell_fd,eg_fd,algo_fd,eg6_fd,palette_fd;
    string capture_prefix=$test$plusargs("composer")?"composer_":$test$plusargs("algo_preview")?"algo_":$test$plusargs("ai")||$test$plusargs("composer")?"ai_":$test$plusargs("poly32")?"poly32_":$test$plusargs("metrics")?"metrics_":$test$plusargs("seq")?"seq_":$test$plusargs("arp")?"arp_":"tail_";
    initial if($test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("ui_tail")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq")) palette_fd=$fopen({"tmp/",capture_prefix,"menu_palette.txt"},"w");else palette_fd=$fopen("tmp/menu_palette.txt","w");
    always @(posedge clk)if(dut.palette_write)$fwrite(palette_fd,"%0d %0d %0d\n",dut.palette_index,dut.palette_data,$time);
    reg [9:0] eg6_base;
    initial if($test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("ui_tail")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq")) cell_fd=$fopen({"tmp/",capture_prefix,"menu_cells.txt"},"w");else cell_fd=$fopen("tmp/menu_cells.txt","w");
    initial if($test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("ui_tail")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq")) eg_fd=$fopen({"tmp/",capture_prefix,"eg_curve.txt"},"w");else eg_fd=$fopen("tmp/eg_curve.txt","w");
    initial if($test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("ui_tail")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq")) algo_fd=$fopen({"tmp/",capture_prefix,"algo_map.txt"},"w");else algo_fd=$fopen("tmp/algo_map.txt","w");
    initial if($test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("ui_tail")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq")) eg6_fd=$fopen({"tmp/",capture_prefix,"eg6_panels.txt"},"w");else eg6_fd=$fopen("tmp/eg6_panels.txt","w");
    always @(posedge clk)begin
        if(dut.text_write)captured_cells[dut.text_address]<=dut.text_data;
        if(dut.text_write)
            $fwrite(cell_fd,"%0d %0d %0d\n",dut.text_address,dut.text_data,$time);
        if(dut.eg_we)
            $fwrite(eg_fd,"%0d %0d %0d\n",dut.eg_addr,dut.eg_data,$time);
        if(dut.algo_we)
            $fwrite(algo_fd,"%0d %0d %0d\n",dut.algo_addr,dut.algo_data,$time);
    end
    // Mirror the six-panel EG upload (UI[25] base + UI[26] word burst).
    always @(posedge clk)begin
        if(dut.write_en && dut.address[31:8]==24'h230000)begin
            case(dut.address[7:2])
                6'd25:eg6_base<=dut.write_data[9:0];
                6'd26:begin
                    $fwrite(eg6_fd,"%0d %0d %0d\n",eg6_base,dut.write_data[7:0],$time);
                    $fwrite(eg6_fd,"%0d %0d %0d\n",eg6_base+1,dut.write_data[15:8],$time);
                    $fwrite(eg6_fd,"%0d %0d %0d\n",eg6_base+2,dut.write_data[23:16],$time);
                    $fwrite(eg6_fd,"%0d %0d %0d\n",eg6_base+3,dut.write_data[31:24],$time);
                    eg6_base<=eg6_base+10'd4;
                end
                default:;
            endcase
        end
    end
    always @(posedge clk)begin
        if(dut.command_valid)case(dut.command)
            8'h69:cmd_69<=cmd_69+1;
            8'h60:cmd_60<=cmd_60+1;
            8'h62:cmd_62<=cmd_62+1;
            8'h63:cmd_63<=cmd_63+1;
            8'h61:cmd_61<=cmd_61+1;
            8'h64:cmd_64<=cmd_64+1;
            8'h65:cmd_65<=cmd_65+1;
            8'h70:cmd_70<=cmd_70+1;
            default:;
        endcase
        if(dut.command_valid&&dut.command==8'h65&&dut.command_payload[63:47]!=0)$fatal(1,"Pitch target outside protocol bits 46:24");
        if(dut.command_valid&&dut.command==8'h64)begin
            if(dut.command_payload[41:40]!==2'd0)$fatal(1,"Slot right scaling curve field");
        end
        if(dut.command_valid&&dut.command==8'h65&&cmd_65>=1&&cmd_65<=4)begin
            if(dut.command_payload[46:24]!==23'h210021)$fatal(1,"Slot pitch target restore");
        end
        if(dut.text_write)text_cells<=text_cells+1;
        if(dut.palette_write)pal_writes<=pal_writes+1;
    end
    integer touch_kind=1;
    initial if($test$plusargs("gesture")||$test$plusargs("algo_preview")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("rename")||$test$plusargs("sd")||$test$plusargs("poly32")||$test$plusargs("metrics")||$test$plusargs("keyboard")||$test$plusargs("spectrum")||$test$plusargs("performance")||$test$plusargs("lesson")||$test$plusargs("arp")||$test$plusargs("seq"))touch_kind=0;
    integer frame_kind=1;reg [3:0] frame_page=0;
    reg slave_low=0;
    assign sda=slave_low?1'b0:1'bz;
    integer state=0,bits=0,reg_bytes=0;
    reg [7:0] sh=0,send_byte;
    reg address_phase=1,reading=0,ack_master;
    reg [15:0] pointer=0;
    function [7:0] goodix_read(input [15:0] addr);
        integer px,py;
        begin
            px=frame_kind==1?750:40;py=frame_kind==1?200:470;
            if(frame_kind==6)begin px=700;py=264;end
            if(frame_kind==7)begin px=736;py=24;end
            if(frame_kind==8)begin px=650;py=312;end
            if(frame_kind==9)begin px=376;py=376;end
            if(frame_kind==10)begin px=100;py=8;end
            if(frame_kind==11)begin px=64;py=24;end
            if(frame_kind==12)begin px=160;py=24;end
            if(frame_kind==13)begin px=200;py=frame_page==4?144:104;end
            if(frame_kind==14)begin px=750;py=450;end
            if(frame_kind==15)begin px=256;py=24;end
            if(frame_kind==17)begin px=736;py=24;end
            if(frame_kind==18)begin px=750;py=450;end
            if(frame_kind==19)begin px=352;py=24;end
            if(frame_kind==20)begin px=448;py=24;end
            if(frame_kind==21)begin px=120;py=450;end
            if(frame_kind==22)begin px=640;py=24;end
            if(frame_kind==23)begin px=500;py=450;end
            if(frame_kind==24)begin px=680;py=360;end
            if(frame_kind==25)begin px=480;py=360;end
            if(frame_kind==26)begin px=200;py=120;end
            if(frame_kind==27)begin px=750;py=450;end
            if(frame_kind==28)begin px=200;py=304;end
            if(frame_kind==29)begin px=750;py=450;end
            if(frame_kind==30)begin px=50;py=450;end
            if(frame_kind==31)begin px=750;py=450;end
            if(frame_kind==32)begin px=544;py=24;end
            if(frame_kind==33)begin px=30;py=120;end
            if(frame_kind==34)begin px=400;py=210;end
            if(frame_kind==35)begin px=750;py=450;end
            if(frame_kind==16)begin px=40;py=120;end
            if(frame_kind==36)begin px=100;py=200;end
            if(frame_kind==37)begin px=704;py=450;end
            if(frame_kind==38)begin px=250;py=376;end
            if(frame_kind==39)begin px=400;py=312;end
            if(frame_kind==40)begin px=700;py=264;end
            if(frame_kind==41)begin px=700;py=328;end
            if(frame_kind==42)begin px=100;py=200;end
            if(frame_kind==43)begin px=200;py=450;end
            if(frame_kind==44)begin px=200;py=320;end
            if(frame_kind==45)begin px=500;py=320;end
            if(frame_kind==46)begin px=200;py=296;end
            if(frame_kind==47)begin px=200;py=344;end
            if(frame_kind==48)begin px=600;py=152;end
            if(frame_kind==49)begin px=600;py=200;end
            if(frame_kind==50)begin px=600;py=248;end
            if(frame_kind==51)begin px=799;py=470;end
            if(frame_kind==52)begin px=750;py=264;end
            if(frame_kind==53)begin px=640;py=264;end
            if(frame_kind==54)begin px=200;py=248;end
            if(frame_kind==55)begin px=600;py=296;end
            if(frame_kind==56)begin px=100;py=390;end
            if(frame_kind==58)begin px=100;py=248;end
            if(frame_kind==59)begin px=650;py=200;end
            if(frame_kind==60)begin px=288;py=450;end
            if(frame_kind==61)begin px=600;py=344;end
            if(frame_kind==62)begin px=80;py=104;end
            if(frame_kind==63)begin px=240;py=104;end
            if(frame_kind==64)begin px=400;py=104;end
            if(frame_kind==65)begin px=640;py=104;end
            if(frame_kind==66)begin px=540;py=104;end
            if(frame_kind==67)begin px=100;py=104;end
            if(frame_kind==68)begin px=80;py=104;end
            if(frame_kind==69)begin px=240;py=104;end
            if(frame_kind==70)begin px=750;py=104;end
            if(frame_kind==71)begin px=360;py=152;end
            if(frame_kind==72)begin px=750;py=152;end
            if(frame_kind==73)begin px=750;py=200;end
            if(frame_kind==74)begin px=360;py=248;end
            if(frame_kind==75)begin px=750;py=248;end
            if(frame_kind==76)begin px=400;py=104;end
            if(frame_kind==77)begin px=600;py=104;end
            if(frame_kind==78)begin px=80;py=104;end
            if(frame_kind==79)begin px=240;py=104;end
            if(frame_kind==80)begin px=384;py=104;end
            if(frame_kind==81)begin px=496;py=104;end
            if(frame_kind==82)begin px=600;py=104;end
            if(frame_kind==83)begin px=720;py=104;end
            if(frame_kind==85)begin px=360;py=248;end
            if(frame_kind==86)begin px=750;py=248;end
            if(frame_kind==87)begin px=360;py=296;end
            if(frame_kind==88)begin px=568;py=296;end
            if(frame_kind==89)begin px=360;py=152;end
            if(frame_kind==90)begin px=750;py=152;end
            if(frame_kind==91)begin px=360;py=200;end
            if(frame_kind==92)begin px=750;py=200;end
            if(frame_kind==93)begin px=100;py=390;end
            if(frame_kind==94)begin px=350;py=450;end
            if(frame_kind==95)begin px=650;py=450;end
            if(frame_kind==96)begin px=500;py=408;end
            if(frame_kind==97)begin px=700;py=408;end
            if(frame_kind==98)begin px=550;py=320;end
            if(frame_kind==100)begin px=664;py=248;end
            if(frame_kind==101)begin px=600;py=390;end
            if(frame_kind==103)begin px=300;py=390;end
            if(frame_kind==104)begin px=80;py=104;end
            if(frame_kind==105)begin px=360;py=152;end
            if(frame_kind==106)begin px=750;py=152;end
            if(frame_kind==107)begin px=200;py=200;end
            if(frame_kind==108)begin px=360;py=296;end
            if(frame_kind==109)begin px=750;py=296;end
            if(frame_kind==110)begin px=360;py=248;end
            if(frame_kind==111)begin px=704;py=104;end
            if(frame_kind==131)begin px=696;py=336;end
            if(frame_kind==132)begin px=192;py=152;end
            if(frame_kind==133)begin px=600;py=152;end
            if(frame_kind==134)begin px=200;py=286;end
            if(frame_kind==112)begin px=80;py=104;end
            if(frame_kind==113)begin px=216;py=104;end
            if(frame_kind==114)begin px=510;py=155;end
            if(frame_kind==115)begin px=728;py=104;end
            if(frame_kind==116)begin px=100;py=288;end
            if(frame_kind==117)begin px=360;py=152;end
            if(frame_kind==118)begin px=760;py=152;end
            if(frame_kind==119)begin px=600;py=168;end
            if(frame_kind==120)begin px=600;py=104;end
            if(frame_kind==121)begin px=480;py=104;end
            if(frame_kind==122)begin px=696;py=288;end
            if(frame_kind==123)begin px=352;py=104;end
            if(frame_kind==124)begin px=600;py=264;end
            if(frame_kind==125)begin px=360;py=200;end
            if(frame_kind==126)begin px=728;py=168;end
            if(frame_kind==127)begin px=650;py=216;end
            if(frame_kind==129)begin px=80;py=460;end
            if(frame_kind==130)begin px=140;py=460;end
            case(addr)
                16'h8140:goodix_read="9";16'h8141:goodix_read="1";16'h8142:goodix_read="1";
                16'h8146:goodix_read=8'h20;16'h8147:goodix_read=8'h03;
                16'h8148:goodix_read=8'hE0;16'h8149:goodix_read=8'h01;
                16'h8047:goodix_read=8'h81;
                16'h814E:goodix_read=frame_kind==3?8'h00:frame_kind==0?8'h80:frame_kind==4?8'h82:8'h81;
                16'h814F:goodix_read=frame_kind==5?1:0;
                16'h8150:goodix_read=px&255;16'h8151:goodix_read=px>>8;
                16'h8152:goodix_read=py&255;16'h8153:goodix_read=py>>8;
                16'h8157:goodix_read=1;
                16'h8158:goodix_read=px&255;16'h8159:goodix_read=px>>8;
                16'h815A:goodix_read=py&255;16'h815B:goodix_read=py>>8;
                default:goodix_read=0;
            endcase
        end
    endfunction
    always @(negedge sda) if(scl===1'b1&&!slave_low)begin
        state=1;bits=0;sh=0;address_phase=1;reg_bytes=0;
    end
    always @(posedge sda) if(scl===1'b1&&!slave_low)state=0;
    always @(posedge scl)begin
        case(state)
            1:begin
                sh={sh[6:0],sda};bits=bits+1;
                if(bits==8)begin
                    if(address_phase)begin
                        if(sh[7:1]!=7'h14)$fatal(1,"Unexpected I2C address %h",sh);
                        reading=sh[0];address_phase=0;
                    end else if(reg_bytes==0)begin pointer[15:8]=sh;reg_bytes=1;end
                    else if(reg_bytes==1)begin pointer[7:0]=sh;reg_bytes=2;end
                    else pointer=pointer+1;
                    state=2;
                end
            end
            3:state=4;
            5:if(bits==0)state=6;else bits=bits-1;
            7:begin ack_master=!sda;state=8;end
        endcase
    end
    always @(negedge scl)begin
        case(state)
            2:begin slave_low=1;state=3;end
            4:begin
                slave_low=0;bits=0;sh=0;
                if(reading)begin
                    // Goodix holds one coordinate report stable until the host
                    // clears status. A scripted finger change must not tear
                    // the status/X/Y bytes during a read transaction.
                    if(pointer==16'h814E)begin frame_kind=touch_kind;frame_page=menu_page;end
                    send_byte=goodix_read(pointer);bits=7;slave_low=!send_byte[7];state=5;end
                else state=1;
            end
            5:slave_low=!send_byte[bits];
            6:begin slave_low=0;state=7;end
            8:begin
                if(ack_master)begin pointer=pointer+1;send_byte=goodix_read(pointer);
                    bits=7;slave_low=!send_byte[7];state=5;end
                else begin slave_low=0;state=0;end
            end
        endcase
    end
    integer event_count=0,seq_ons=0;
    always @(posedge clk)if(valid&&arp_test_ready&&event_word[31]&&event_word[23:20]==9)seq_ons<=seq_ons+1;
    always @(posedge clk)if(valid&&arp_test_ready)begin
        $display("UI MIDI %h at %t",event_word,$time);
        if($test$plusargs("gesture")||$test$plusargs("ai")||$test$plusargs("composer")||$test$plusargs("arp")||$test$plusargs("seq"))begin
            if(event_word[23:16]==8'hb0&&event_word[14:8]==22&&!$test$plusargs("glide_delay"))model_glide<=event_word[6:0]!=0;
        end else if($test$plusargs("lesson"))begin
            if(event_word!==32'h00b04000&&event_word!==32'h00903064&&event_word!==32'h00803000)
                $fatal(1,"Unexpected lesson UI MIDI %h",event_word);
        end else if(performance_case)begin
            if(event_word[23:16]==8'hb0&&event_word[14:8]==27)model_preset<=event_word[6:0];
            else if(event_word[23:16]==8'hb0&&event_word[14:8]==22&&!$test$plusargs("glide_delay"))model_glide<=event_word[6:0]!=0;
            else if(event_word!==32'h00903064 && event_word!==32'h00803000)$fatal(1,"Unexpected performance MIDI");
        end else if($test$plusargs("keyboard"))begin
            case(event_count)
                0:if(event_word!==32'h00903064)$fatal(1,"Default touch velocity/C3");
                1:if(event_word!==32'h00803000)$fatal(1,"C3 release");
                2:if(event_word!==32'h0090487f)$fatal(1,"Rightmost full-width C5/configured velocity");
                3:if(event_word!==32'h00804800)$fatal(1,"C5 release");
                default:$fatal(1,"Unexpected keyboard MIDI");
            endcase
        end else case(event_count)
            0:if(event_word!==32'h00B01B01)$fatal(1,"Preset button event");
            1:if(event_word!==32'h00903064)$fatal(1,"Touch C3 note-on event");
            2:if(event_word!==32'h00803000)$fatal(1,"Touch release event");
            3:if(event_word!==32'h00B01B01)$fatal(1,"Explicit ROM load selected wrong preset");
            default:$fatal(1,"Held control generated duplicate events");
        endcase
        event_count=event_count+1;
    end
    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        // The unmodified piano1 reset sequencer is already hardware proven.
        // Skip its 177 ms only in this firmware/I2C regression.
        force dut.reset_ready=1'b1;
        wait(present);
        if(volume!==5)$fatal(1,"Power-up volume must be 5");
        if($test$plusargs("algo_preview"))begin
            #10000000;touch_kind=12;wait(menu_page==1);#30000000;
            $display("PASS ALGO rectangle menu capture from real firmware");$finish;
        end
        if($test$plusargs("gesture"))begin
            if(gesture_config!==0)$fatal(1,"Gesture controls must default OFF");
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=103;wait(menu_page==13);#10000000;
            touch_kind=0;#8000000;touch_kind=111;wait(menu_page==14);#10000000;
            touch_kind=0;#8000000;touch_kind=115;#10000000;
            touch_kind=0;#8000000;touch_kind=131;#10000000;
            touch_kind=0;#8000000;touch_kind=133;#10000000;
            if(gesture_config!==0)$fatal(1,"Control armed while recognition OFF");
            touch_kind=0;#8000000;touch_kind=132;wait(gesture_config==1);#10000000;
            touch_kind=0;#8000000;touch_kind=133;wait(gesture_config==3);#10000000;
            touch_kind=0;#8000000;touch_kind=134;wait(gesture_config==5);#10000000;
            if(!test_composer.perform_mode)$fatal(1,"PERFORM mode not committed");
            touch_kind=0;#8000000;touch_kind=133;wait(gesture_config==7);#10000000;
            touch_kind=0;#8000000;touch_kind=134;wait(gesture_config==1);#10000000;
            if(test_composer.perform_mode)$fatal(1,"BASIC mode not restored");
            touch_kind=0;#8000000;touch_kind=133;wait(gesture_config==3);#10000000;
            gesture_model=32'h0001246c;
            #120000000;
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#10000000;
            if(gesture_config!==3||!composer_status[0])$fatal(1,"Page change lost armed composer");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=103;wait(menu_page==13);#10000000;
            touch_kind=0;#8000000;touch_kind=111;wait(menu_page==14);#10000000;
            touch_kind=0;#8000000;touch_kind=132;wait(gesture_config==0);#10000000;
            touch_kind=0;#8000000;touch_kind=132;wait(gesture_config==1);#10000000;
            touch_kind=0;#8000000;touch_kind=133;wait(gesture_config==3);#10000000;
            touch_kind=0;#8000000;touch_kind=115;#10000000;
            touch_kind=0;#8000000;touch_kind=122;wait(menu_page==13);#10000000;
            if(gesture_config!==1||composer_status[0]||composer_ons)$fatal(1,"Mode exit did not disarm or UI leaked notes");
            $display("PASS real RV32I/I2C gesture page: OFF defaults, recognition/control isolation, status, cross-page persistence, mode exit disarm");$finish;
        end
        if($test$plusargs("composer"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=103;wait(menu_page==13);#10000000;
            touch_kind=0;#8000000;touch_kind=111;wait(menu_page==14);#10000000;
            if(!composer_status[0]||aux_words[1023]!==1||aux_words[0]!==16'h0021)$fatal(1,"Composer entry/patch capture");
            if($test$plusargs("composer_preview"))begin #30000000;$display("PASS composer preview from real firmware");$finish;end
            touch_kind=0;#8000000;touch_kind=112;wait(composer_status[1]);#10000000;
            touch_kind=0;#8000000;touch_kind=114;wait(test_composer.density>110&&test_composer.direction>100);#5000000;
            touch_kind=0;#8000000;touch_kind=113;wait(test_composer.theme_recording);#5000000;
            touch_kind=0;#8000000;touch_kind=2;wait(test_composer.seed_count==1);#5000000;
            touch_kind=0;#8000000;touch_kind=129;wait(test_composer.seed_count==2);#5000000;
            touch_kind=0;#8000000;touch_kind=130;wait(test_composer.seed_count==3);#5000000;
            touch_kind=0;#8000000;touch_kind=113;wait(!test_composer.theme_recording);#5000000;
            touch_kind=0;#8000000;touch_kind=112;wait(composer_status[1]);#8000000;
            touch_kind=0;#8000000;touch_kind=115;#8000000;
            touch_kind=0;#8000000;touch_kind=117;wait(test_composer.step_us<125000);#5000000;
            touch_kind=0;#8000000;touch_kind=118;wait(test_composer.key==1);#5000000;
            touch_kind=0;#8000000;touch_kind=125;wait(test_composer.form==1);#5000000;
            if(!composer_status[1]||aux_words[0]!==16'h0021)$fatal(1,"Composer live edits changed transport/patch");
            touch_kind=0;#8000000;touch_kind=115;#8000000;
            touch_kind=0;#8000000;touch_kind=123;wait(test_composer.record_mode==1);touch_kind=0;
            wait(test_composer.record_mode==2);#1000000;touch_kind=124;#12000000;touch_kind=0;
            wait(test_composer.record_mode==0);#5000000;
            if(!test_composer.rhythm_valid)$fatal(1,"Touch TAP did not record rhythm");
            touch_kind=120;wait(test_composer.ending);touch_kind=0;wait(!test_composer.running);#1000000;
            if(test_composer.active||composer_ons<4||test_composer.misses)$fatal(1,"Composer audio state/end/deadline");
            touch_kind=115;#8000000;touch_kind=0;#8000000;touch_kind=122;wait(menu_page==13);#8000000;
            if(composer_status[3:0]!=0)$fatal(1,"EXIT did not flush composer");
            $display("PASS real RV32I/I2C composer: entry/backing patch, XY, three-note theme, live BPM/key/form edits, count-in/touch rhythm, cadence END, exit and zero missed steps");$finish;
        end
        if($test$plusargs("ai"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=103;wait(menu_page==13);#10000000;
            touch_kind=0;#8000000;touch_kind=104;wait(ai_status[0]);#5000000;
            if(aux_words[1023]!==1||aux_words[0]!==16'h0021)$fatal(1,"AI did not snapshot BACKING");
            if(!test_ai.config_word[3]||test_ai.settings!==16'h3c03)$fatal(1,"V2 follow/split/adaptive defaults not committed");
            if($test$plusargs("ai_preview"))begin
                #30000000;
                $display("PASS AI menu capture from real RV32I firmware");$finish;
            end
            pr_data=16'h002a;
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(!ai_status[0])$fatal(1,"Page exit stopped AI");
            touch_kind=0;#8000000;touch_kind=2;#10000000;touch_kind=0;#10000000;
            if(!ai_status[0]||aux_words[0]!==16'h0021)$fatal(1,"LIVE playing/patch change overwrote AI backing");
            touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=103;wait(menu_page==13);#5000000;
            touch_kind=0;#8000000;touch_kind=105;wait(test_ai.step_us<125000);#5000000;
            touch_kind=0;#8000000;touch_kind=106;wait(test_ai.config_word[7:4]==1);#5000000;
            touch_kind=0;#8000000;touch_kind=107;wait(test_ai.config_word[1]);#5000000;
            touch_kind=0;#8000000;touch_kind=108;wait(!test_ai.settings[0]);#5000000;
            touch_kind=0;#8000000;touch_kind=109;wait(test_ai.settings[14:8]==61);#5000000;
            touch_kind=0;#8000000;touch_kind=110;wait(!test_ai.config_word[3]&&!test_ai.config_word[2]);#5000000;
            if(!ai_status[0])$fatal(1,"AI parameter edit stopped transport");
            touch_kind=0;#8000000;touch_kind=104;wait(ai_status[2:0]==0);#5000000;
            touch_kind=0;#8000000;touch_kind=104;wait(ai_status[0]);#5000000;
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=67;wait(menu_page==10);#5000000;
            touch_kind=0;#8000000;touch_kind=68;wait(dut.arp_config[0]);#5000000;
            if(ai_status[2:0]!=0)$fatal(1,"ARP did not stop/flush AI");
            if(ai_note_ons<1)$fatal(1,"Trained policy never generated a bass event");
            $display("PASS real UI AI entry/start/stop, compiled backing snapshot, LIVE independence, tempo/key/density edits, ARP mutual exclusion and learned MIDI");$finish;
        end
        if($test$plusargs("glide_time"))begin
            touch_kind=0;#10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=101;#10000000;
            touch_kind=0;#8000000;touch_kind=14;wait(model_glide_ms==171);#5000000;
            touch_kind=0;#8000000;
            if(aux_words[1021]==0||aux_count<6)$fatal(1,"Glide reciprocal not sent");
            touch_kind=23;wait(model_glide_ms>400);#10000000;touch_kind=0;#8000000;
            if(model_glide_ms<10||model_glide_ms>1000)$fatal(1,"Glide slider range");
            if(event_count!=0)$fatal(1,"Glide time edit changed enable / emitted notes");
            $display("PASS real UI GLIDE MS selection, tap adjustment, slider, raw reciprocal upload and enable isolation");$finish;
        end
        if($test$plusargs("rename"))begin
            #10000000;touch_kind=22;wait(menu_page==6);#10000000;
            touch_kind=0;#8000000;touch_kind=24;
            wait(captured_cells[9*128+86][7:0]=="B");#5000000;
            touch_kind=0;#8000000;touch_kind=23;
            wait(captured_cells[13*128+34][7:0]=="B");#5000000;
            touch_kind=0;#8000000;touch_kind=100;
            wait(captured_cells[13*128+34][7:0]=="C");#5000000;
            touch_kind=0;#8000000;touch_kind=39;
            wait(captured_cells[9*128+86][7:0]=="C");#5000000;
            if(captured_cells[3*128+8][7:0]!="C")$fatal(1,"Rename missed current header");
            touch_kind=0;#8000000;touch_kind=25;#10000000;
            touch_kind=0;#8000000;touch_kind=45;wait(cmd_64>=6&&cmd_65>=4);#10000000;
            if(captured_cells[9*128+86][7:0]!="C"||captured_cells[3*128+8][7:0]!="C")$fatal(1,"Reload lost renamed slot metadata");
            if(event_count||!dut.u_sd_spi.cs_n)$fatal(1,"Rename changed MIDI or started SD I/O");
            $display("PASS real UI rename immediately updates USER row/header, persists in RAM reload, restores parameters and performs no SD write");$finish;
        end
        if($test$plusargs("sd"))begin
            #10000000;touch_kind=22;wait(menu_page==6);#10000000;
            touch_kind=0;#8000000;touch_kind=96;#12000000;
            if(captured_cells[9*128+14][7:0]!="R")$fatal(1,"SD bank overwrite confirmation missing");
            touch_kind=0;#8000000;touch_kind=98;
            wait(!dut.u_sd_spi.cs_n);wait(dut.u_sd_spi.cs_n);#20000000;
            if(captured_cells[7*128+56][7:0]!="N")$fatal(1,"Missing SD card error not shown");
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(event_count)$fatal(1,"Failed SD read changed sound");
            $display("PASS real UI SD read confirmation, no-card timeout message and responsive return without MIDI changes");$finish;
        end
        if($test$plusargs("poly32"))begin
            #12000000;
            if(captured_cells[3*128+58][7:0]!="3"||captured_cells[3*128+59][7:0]!="2"||
                captured_cells[3*128+61][7:0]!="3"||captured_cells[3*128+62][7:0]!="2")$fatal(1,"Full 32/32 header truncated");
            if(captured_cells[3*128+5][7:0]!="1"||captured_cells[3*128+6][7:0]!="2"||captured_cells[3*128+7][7:0]!="8")$fatal(1,"Extended voices corrupted preset 128");
            model_voices=31;#10000000;if(captured_cells[3*128+59][7:0]!="1")$fatal(1,"31 voice header");
            model_voices=32;#10000000;if(captured_cells[3*128+59][7:0]!="2")$fatal(1,"32 voice header");
            touch_kind=17;wait(menu_page==7);#10000000;touch_kind=0;#8000000;touch_kind=93;wait(menu_page==12);#12000000;
            if(captured_cells[6*128+24][7:0]!="3"||captured_cells[6*128+25][7:0]!="2")$fatal(1,"Telemetry capacity stale");
            if(event_count!=0)$fatal(1,"Polyphony UI emitted MIDI");
            $display("PASS real UI 31/32 voices, capacity 32, preset 128 isolation and telemetry page");$finish;
        end
        if($test$plusargs("metrics"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=93;wait(menu_page==12);#12000000;
            if(perf_snaps<1||captured_cells[9*128+4][7:0]!="V")$fatal(1,"Metrics page / MMIO did not render");
            $display("METRICS_CAPTURE_US=%0d",$time/1000);
            touch_kind=0;#8000000;touch_kind=94;#16000000;freeze_snaps=perf_snaps;
            touch_kind=0;#520000000;if(perf_snaps!=freeze_snaps)$fatal(1,"Frozen metrics kept sampling");
            touch_kind=95;#16000000;if(perf_clears!=1)$fatal(1,"Counter clear button");
            touch_kind=0;#8000000;touch_kind=94;#520000000;
            if(perf_snaps<=freeze_snaps+1)$fatal(1,"Metrics refresh did not resume");
            touch_kind=0;#8000000;touch_kind=21;wait(menu_page==7);#5000000;
            if(event_count!=0)$fatal(1,"Telemetry buttons emitted MIDI");
            $display("PASS real UI telemetry entry, MMIO, freeze/resume, clear, return and MIDI isolation");$finish;
        end
        if($test$plusargs("seq"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=77;wait(menu_page==11);#10000000;
            if(captured_cells[1160][7:0]!="C")$fatal(1,"Factory sequence grid not loaded");
            touch_kind=0;#8000000;touch_kind=87;wait(dut.u_sequencer.requested_pattern==1);#5000000;
            touch_kind=0;#8000000;touch_kind=88;wait(dut.u_sequencer.requested_length==15);#5000000;
            touch_kind=0;#8000000;touch_kind=79;wait(dut.u_sequencer.recording);#5000000;
            if($test$plusargs("glide_delay")&&model_glide)$fatal(1,"Sequence recording entered mono mode");
            touch_kind=0;#8000000;touch_kind=2;wait(dut.u_sequencer.edit_address==17);#5000000;
            touch_kind=0;#12000000;touch_kind=51;wait(dut.u_sequencer.edit_address==18);#5000000;
            touch_kind=0;#12000000;
            if(dut.u_sequencer.steps[16]!==32'h80006430||dut.u_sequencer.steps[17]!==32'h80006448)$fatal(1,"Touch step recording / cache cursor interference");
            touch_kind=80;wait(dut.u_sequencer.edit_address==19);#5000000;
            touch_kind=0;#8000000;touch_kind=81;wait(dut.u_sequencer.edit_address==20);#5000000;
            if(dut.u_sequencer.steps[18]!==0||dut.u_sequencer.steps[19]!==32'h40000000)$fatal(1,"REST/TIE step entry");
            touch_kind=0;#8000000;touch_kind=79;wait(!dut.u_sequencer.recording);#5000000;
            // Model a different LIVE patch after recording. Playback must
            // upload the recording's compiled snapshot, not this new value.
            pr_data=16'h002a;
            if($test$plusargs("glide_delay")&&!model_glide)$fatal(1,"Sequence STOP lost original glide mode");
            touch_kind=0;#8000000;touch_kind=85;wait(dut.u_sequencer.steps[20]==32'h8000603d);#5000000;
            touch_kind=0;#8000000;touch_kind=86;wait(dut.u_sequencer.steps[20]==32'h8000613d);#5000000;
            touch_kind=0;#8000000;touch_kind=78;wait(seq_ons>=1);#5000000;
            if(!dut.u_sequencer.running)$fatal(1,"Sequence START");
            if(aux_words[0]!==16'h0021||aux_words[9]!==16'h0021||aux_words[64]!==16'h0021||aux_words[1023]!==1)
                $fatal(1,"Recorded BACKING patch was replaced by current LIVE parameters");
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(!dut.u_sequencer.running)$fatal(1,"Page exit stopped sequence");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=77;wait(menu_page==11);#5000000;
            touch_kind=0;#8000000;touch_kind=83;#5000000;
            touch_kind=0;#8000000;touch_kind=89;wait(dut.seq_timing[31:0]<125000);#5000000;
            touch_kind=0;#8000000;touch_kind=90;wait(dut.seq_timing[31:0]<80000);#5000000;
            touch_kind=0;#8000000;touch_kind=91;wait(dut.seq_timing[95:64]>dut.seq_timing[31:0]*70/100);#5000000;
            touch_kind=0;#8000000;touch_kind=92;wait(dut.seq_timing[31:0]>dut.seq_timing[63:32]);#5000000;
            if(!dut.u_sequencer.running)$fatal(1,"Live tempo/rate/gate/swing edit stopped sequence");
            touch_kind=0;#8000000;touch_kind=78;wait(!dut.u_sequencer.running);#5000000;
            touch_kind=0;#8000000;touch_kind=82;#5000000;
            if(dut.u_sequencer.steps[16]!==32'h80006430)$fatal(1,"CLEAR lacked confirmation");
            touch_kind=0;#8000000;touch_kind=82;wait(dut.u_sequencer.steps[16]==0);#5000000;
            if(dut.u_sequencer.steps[20]!==0||dut.u_sequencer.steps[0]!==32'h8000603c)$fatal(1,"CLEAR bank isolation");
            touch_kind=0;#8000000;touch_kind=78;wait(dut.u_sequencer.running);#5000000;
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=67;wait(menu_page==10);#5000000;
            touch_kind=0;#8000000;touch_kind=68;wait(dut.arp_config[0]);#5000000;
            if(dut.u_sequencer.running||dut.u_sequencer.recording)$fatal(1,"Enabling ARP failed to stop sequence");
            if($test$plusargs("glide_delay")&&model_glide)$fatal(1,"SEQ to ARP left queued mono restoration enabled");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=77;wait(menu_page==11);#5000000;
            touch_kind=0;#8000000;touch_kind=78;wait(dut.u_sequencer.running);#5000000;
            if(dut.arp_config[0])$fatal(1,"Starting sequence failed to disable ARP");
            if($test$plusargs("glide_delay")&&model_glide)$fatal(1,"ARP to SEQ left queued mono restoration enabled");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=61;wait(menu_page==9);#5000000;
            if(dut.u_sequencer.running||dut.u_sequencer.recording||dut.u_sequencer.active)$fatal(1,"Practice failed to stop sequence");
            if($test$plusargs("glide_delay")&&model_glide)$fatal(1,"SEQ to practice failed to disable restored glide");
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(dut.u_sequencer.running)$fatal(1,"Leaving practice restarted sequence");
            if($test$plusargs("glide_delay")&&!model_glide)$fatal(1,"Cross-tool mode changes lost original glide");
            $display("PASS real UI SEQ grid, bank/length, touch record/read cursor, REST/TIE, edit/transport, cross-page, timing, clear and ARP/practice mutual exclusion");$finish;
        end
        if($test$plusargs("arp"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=67;wait(menu_page==10);#10000000;
            if(captured_cells[775][7:0]!="A")$fatal(1,"ARP transport missing");
            if($test$plusargs("repeat"))begin
                touch_kind=0;#8000000;touch_kind=70;
                wait(dut.arp_config[63:32]==60000000/(121*2));#50000000;
                if(dut.arp_config[63:32]!=60000000/(121*2))$fatal(1,"ARP short press repeated");
                // Advance the real firmware timer to test holds without
                // simulating tens of millions of idle clocks.
                @(negedge clk);dut.microseconds=dut.microseconds+410000;
                wait(dut.arp_config[63:32]==60000000/(122*2));
                @(negedge clk);dut.microseconds=dut.microseconds+50000;
                wait(dut.arp_config[63:32]==60000000/(123*2));
                touch_kind=0;#10000000;
                @(negedge clk);dut.microseconds=dut.microseconds+200000;
                #10000000;if(dut.arp_config[63:32]!=60000000/(123*2))$fatal(1,"Released button repeated");
                touch_kind=72;wait(dut.arp_config[5:3]==1);#30000000;
                if(dut.arp_config[5:3]!=1)$fatal(1,"Right-side ARP button retriggered");
                touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#10000000;
                touch_kind=0;#8000000;touch_kind=77;wait(menu_page==11);#10000000;
                touch_kind=0;#8000000;touch_kind=83;#10000000;
                touch_kind=0;#8000000;touch_kind=90;
                wait(dut.seq_timing[31:0]==60000000/(123*8));#50000000;
                if(dut.seq_timing[31:0]!=60000000/(123*8))$fatal(1,"SEQ right-side short press repeated");
                @(negedge clk);dut.microseconds=dut.microseconds+410000;
                wait(dut.seq_timing[31:0]==60000000/(123*3));
                $display("PASS real UI ARP/SEQ tap one step, right-hand controls, 450 ms hold, 50 ms repeat and release");$finish;
            end
            touch_kind=0;#8000000;touch_kind=68;wait(dut.arp_config[0]);#5000000;
            if(dut.arp_config[63:32]!=250000||dut.arp_config[127:96]!=175000)$fatal(1,"ARP default timing");
            touch_kind=0;#8000000;touch_kind=69;wait(dut.arp_config[1]);#5000000;
            touch_kind=0;#8000000;touch_kind=70;wait(dut.arp_config[63:32]<250000);#5000000;
            touch_kind=0;#8000000;touch_kind=71;wait(dut.arp_config[63:32]<150000);#5000000;
            touch_kind=0;#8000000;touch_kind=72;wait(dut.arp_config[5:3]==1);#5000000;
            touch_kind=0;#8000000;touch_kind=73;wait(dut.arp_config[127:96]>dut.arp_config[63:32]*70/100);#5000000;
            touch_kind=0;#8000000;touch_kind=74;wait(dut.arp_config[2]);#5000000;
            touch_kind=0;#8000000;touch_kind=75;wait(dut.arp_config[63:32]>dut.arp_config[95:64]);#5000000;
            touch_kind=0;#8000000;touch_kind=2;wait(test_arp_notes[48]);#5000000;
            touch_kind=0;#8000000;
            if(!test_arp_notes[48])$fatal(1,"UI HOLD failed");
            // Reproduce field failure: parameter writes also publish the
            // stopped sequencer's timing; these must not suspend the ARP.
            touch_kind=70;wait(dut.arp_config[63:32]<240000);#10000000;
            touch_kind=0;#8000000;
            if(!test_arp_notes[48]||!test_arp_status[2])$fatal(1,"HOLD tempo edit cleared chord");
            touch_kind=72;#15000000;touch_kind=0;#8000000;
            if(!test_arp_notes[48]||!test_arp_status[2])$fatal(1,"HOLD order edit cleared chord");
            touch_kind=11;wait(menu_page==0);wait(dut.arp_config[16]);#5000000;
            touch_kind=0;#8000000;touch_kind=2;wait(test_arp.live_notes[48]);#5000000;
            if(test_arp_notes!=(128'd1<<48))$fatal(1,"PLAY solo changed background chord");
            touch_kind=0;#8000000;if(test_arp.live_notes!=0||!test_arp_notes[48])$fatal(1,"Solo release changed ARP");
            touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=67;wait(menu_page==10);wait(!dut.arp_config[16]);#5000000;
            touch_kind=0;#8000000;
            touch_kind=76;wait(test_arp_notes==0);#5000000;
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(!dut.arp_config[0])$fatal(1,"Leaving ARP disabled playback");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=61;wait(menu_page==9);wait(!test_arp_status[1]);#5000000;
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);wait(test_arp_status[1]);#5000000;
            if(test_arp_notes!=0)$fatal(1,"Leaving lesson restarted old chord");
            $display("PASS real UI ARP entry, defaults, HOLD, tempo/rate/order/gate/velocity/swing, keyboard, STOP, persistent enable and practice suspend");$finish;
        end
        if($test$plusargs("lesson"))begin
            #10000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=61;wait(menu_page==9);#10000000;
            if(octave!=0||!dut.lesson_state[16])$fatal(1,"Lesson entry failed");
            if(captured_cells[774][7:0]!="M")$fatal(1,"Lesson transport not drawn");
            touch_kind=0;#8000000;touch_kind=2;wait(event_count==2);#5000000;
            touch_kind=0;wait(event_count==3);#8000000;
            touch_kind=65;wait(dut.u_lesson.speed==125);#5000000;
            touch_kind=0;#8000000;touch_kind=66;wait(dut.u_lesson.speed==100);#5000000;
            touch_kind=0;#8000000;touch_kind=62;wait(dut.u_lesson.demo);#5000000;
            touch_kind=0;#8000000;touch_kind=63;wait(dut.u_lesson.running);#5000000;
            touch_kind=0;#8000000;touch_kind=63;wait(!dut.u_lesson.running);#5000000;
            touch_kind=0;#8000000;touch_kind=64;#5000000;
            if(dut.u_lesson.position!=0)$fatal(1,"Restart did not reset song");
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            if(dut.lesson_state[16])$fatal(1,"Exit did not disable lesson");
            $display("PASS real UI lesson entry, full keyboard, mode, transport, speed, restart, exit");$finish;
        end
        if(performance_case)begin
            #10000000;touch_kind=59;wait(model_preset==127);#10000000;
            if(captured_cells[389][7:0]!="1"||captured_cells[390][7:0]!="2"||captured_cells[391][7:0]!="8")$fatal(1,"128 preset header truncated");
            if(captured_cells[392][7:0]!="E"||captured_cells[393][7:0]!="X")$fatal(1,"High-bank name aliased to bank 0");
            touch_kind=0;#8000000;touch_kind=1;wait(model_preset==0);#5000000;
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#8000000;touch_kind=55;#5000000;
            touch_kind=0;#8000000;touch_kind=14;wait(model_glide);#5000000;
            touch_kind=0;#8000000;touch_kind=60;wait(!model_glide);#5000000;
            touch_kind=0;#8000000;touch_kind=22;wait(menu_page==6);#5000000;
            touch_kind=0;#8000000;touch_kind=56;#5000000;
            touch_kind=0;#8000000;touch_kind=58;#5000000;
            touch_kind=0;#8000000;touch_kind=43;wait(model_preset==127);#5000000;
            touch_kind=0;#8000000;touch_kind=11;wait(menu_page==0);#5000000;
            touch_kind=0;#8000000;touch_kind=2;wait(event_count==6);#5000000;
            touch_kind=0;wait(event_count==7);#5000000;
            $display("PASS real UI 128 preset wrap/header/last page, mono glide toggle and keyboard isolation");$finish;
        end
        if($test$plusargs("spectrum"))begin
            #10000000;touch_kind=52;wait(spectrum_enable);#5000000;
            if(visual_mode)$fatal(1,"FFT set XY mode bit");
            touch_kind=0;#8000000;touch_kind=6;wait(visual_mode);#5000000;
            if(spectrum_enable)$fatal(1,"XY left FFT enabled");
            touch_kind=0;#8000000;touch_kind=53;wait(!visual_mode);#5000000;
            if(spectrum_enable)$fatal(1,"WAVE left FFT enabled");
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=50;wait(menu_page==0&&spectrum_enable);#5000000;
            touch_kind=0;#8000000;touch_kind=17;wait(menu_page==7);#5000000;
            touch_kind=0;#8000000;touch_kind=54;#5000000;
            touch_kind=0;#8000000;touch_kind=14;wait(!spectrum_enable);#5000000;
            if(visual_mode||event_count!=0)$fatal(1,"DISPLAY cycle wrap or spurious MIDI");
            $display("PASS real UI WAVE/XY/FFT, SETUP spectrum shortcut, DISPLAY cycle and MIDI isolation");$finish;
        end
        if($test$plusargs("keyboard"))begin
            #10000000;touch_kind=2;wait(event_count==1);#5000000;
            touch_kind=0;wait(event_count==2);#5000000;
            touch_kind=17;wait(menu_page==7);#10000000;
            touch_kind=0;#10000000;touch_kind=48;#10000000;
            touch_kind=0;#10000000;touch_kind=37;#10000000;
            touch_kind=0;#10000000;touch_kind=49;#10000000;
            touch_kind=0;#10000000;touch_kind=14;wait(dut.headphone_select);#10000000;
            touch_kind=0;#10000000;touch_kind=11;wait(menu_page==0);#10000000;
            touch_kind=0;#10000000;touch_kind=51;wait(event_count==3);#5000000;
            touch_kind=0;wait(event_count==4);#5000000;
            $display("PASS full-width edge keys, default/custom velocity, volume 5 and headphone selection");$finish;
        end
        if($test$plusargs("ui_tail"))begin
            touch_kind=0;#10000000;
            touch_kind=15;wait(menu_page==2);#10000000;
            touch_kind=0;#8000000;touch_kind=26;#5000000;
            touch_kind=0;#8000000;
            touch_kind=22;wait(menu_page==6);#5000000;
            touch_kind=0;#8000000;touch_kind=42;#5000000;
            touch_kind=0;#8000000;touch_kind=43;#5000000;
            touch_kind=0;#8000000;touch_kind=44;#5000000;
            touch_kind=0;#8000000;
            if(event_count!=0)$fatal(1,"Cancelled edited preset load emitted MIDI");
            touch_kind=43;#5000000;touch_kind=0;#8000000;
            touch_kind=45;wait(event_count==1);#5000000;
            $display("PASS edited preset load cancel/confirm with real UI firmware");
            $finish;
        end
        wait(event_count==1);#10000000;
        if(event_count!=1)$fatal(1,"Held preset repeated");
        touch_kind=2;wait(event_count==2);#5000000;
        touch_kind=4;#5000000;
        if(event_count!=2)$fatal(1,"Second finger retriggered same key");
        touch_kind=5;#5000000;
        if(event_count!=2)$fatal(1,"First finger release stopped shared key");
        touch_kind=3;#5000000;
        if(event_count!=2)$fatal(1,"No-fresh-frame incorrectly released key");
        touch_kind=0;wait(event_count==3);#1000000;
        touch_kind=6;wait(visual_mode);#5000000;
        touch_kind=0;#5000000;
        touch_kind=7;wait(menu_page==7);#5000000;
        touch_kind=0;#5000000;touch_kind=46;#5000000;
        touch_kind=0;#5000000;touch_kind=14;wait(xy_delay==25);#5000000;
        touch_kind=0;#5000000;touch_kind=11;wait(menu_page==0);#5000000;
        if(xy_delay!=25)$fatal(1,"Held delay button repeated");
        touch_kind=0;#5000000;
        touch_kind=8;wait(octave==-1);#5000000;
        if(!visual_mode||xy_delay!=25)$fatal(1,"Negative octave overwrote view/delay bits");
        if(!display_auto_gain)$fatal(1,"Visual AGC not enabled by default");
        touch_kind=0;#5000000;
        touch_kind=7;wait(menu_page==7);#5000000;
        touch_kind=0;#5000000;touch_kind=47;#5000000;
        touch_kind=0;#5000000;touch_kind=14;wait(!display_auto_gain);#5000000;
        touch_kind=0;#5000000;touch_kind=14;wait(display_auto_gain);#5000000;
        touch_kind=0;#5000000;touch_kind=11;wait(menu_page==0);#5000000;
        // ---- Phase 1.1 regression: universal tabs, perf chrome, themes ----
        touch_kind=0;#8000000;
        if(menu_page!==4'd0)$fatal(1,"Performance page should not show the menu");
        if(!dut.text_enable)$fatal(1,"Character layer was never enabled");
        if(text_cells<200)$fatal(1,"Performance chrome was not drawn");
        $display("M1 perf chrome at %t",$time);
        touch_kind=12;wait(menu_page==4'd1);#60000000;
        if(cmd_69<5)$fatal(1,"ALGO tab did not read patch parameters");
        $display("M2 algo at %t",$time);
        touch_kind=0;#8000000;
        touch_kind=13;#5000000;
        touch_kind=0;#8000000;
        touch_kind=14;#20000000;
        touch_kind=0;#10000000;
        if(cmd_60<1)$fatal(1,"Algorithm edit did not send command 0x60");
        $display("M3 algo edit at %t",$time);
        touch_kind=0;#30000000;
        touch_kind=11;wait(menu_page==4'd0);#8000000;
        touch_kind=11;#20000000;
        if(menu_page!==4'd0)$fatal(1,"PERF tab re-entered the menu while held");
        touch_kind=0;#8000000;
        $display("M4 perf stable at %t",$time);
        touch_kind=15;wait(menu_page==4'd2);#5000000;
        touch_kind=0;#8000000;
        touch_kind=16;#5000000;
        touch_kind=0;#8000000;
        if(cmd_69<20)$fatal(1,"OSC page did not read operator fields");
        $display("M5 osc reads at %t",$time);
        touch_kind=0;#30000000;
        touch_kind=17;wait(menu_page==4'd7);#5000000;
        touch_kind=0;#8000000;
        if(pal_writes<16)$fatal(1,"Theme palette was not written");
        touch_kind=18;#5000000;
        touch_kind=0;#8000000;
        if(pal_writes<32)$fatal(1,"Theme cycle did not rewrite the palette");
        if(dut.background_color!==24'hFFFFFF)$fatal(1,"Background choice did not wrap BLACK to WHITE");
        $display("M6 theme at %t",$time);
        touch_kind=19;wait(menu_page==4'd3);#5000000;
        if(cmd_69<8)$fatal(1,"EG page did not read the envelope");
        touch_kind=0;#8000000;
        touch_kind=13;#5000000;
        touch_kind=0;#8000000;
        touch_kind=31;#5000000;
        touch_kind=0;#8000000;
        if(cmd_63<1)$fatal(1,"EG edit did not send command 0x63");
        $display("M7 eg edit at %t",$time);
        touch_kind=20;wait(menu_page==4'd4);#5000000;
        touch_kind=0;#8000000;
        touch_kind=13;#5000000;
        touch_kind=0;#8000000;
        touch_kind=14;#5000000;
        touch_kind=0;#8000000;
        if(cmd_60<2)$fatal(1,"LFO edit did not send command 0x60");
        $display("M8 lfo edit at %t",$time);
        touch_kind=12;wait(menu_page==4'd1);#30000000;
        touch_kind=0;#8000000;
        touch_kind=28;#5000000;
        touch_kind=0;#8000000;
        touch_kind=29;#5000000;
        touch_kind=0;#8000000;
        if(cmd_60<3)$fatal(1,"ALGO transpose edit did not send 0x60");
        $display("M9 transpose at %t",$time);
        touch_kind=19;wait(menu_page==4'd3);#5000000;
        touch_kind=0;#8000000;
        touch_kind=21;#5000000;
        touch_kind=0;#8000000;
        touch_kind=13;#5000000;
        touch_kind=0;#8000000;
        touch_kind=31;#5000000;
        touch_kind=0;#8000000;
        if(cmd_65<1)$fatal(1,"Pitch EG edit did not send 0x65");
        $display("M10 pitch eg at %t",$time);
        touch_kind=15;wait(menu_page==4'd2);#5000000;
        touch_kind=0;#8000000;
        touch_kind=26;#5000000;
        touch_kind=0;#8000000;
        touch_kind=27;#5000000;
        touch_kind=0;#8000000;
        if(cmd_62<1)$fatal(1,"OSC enable toggle did not send 0x62");
        $display("M11 enable at %t",$time);
        touch_kind=22;wait(menu_page==4'd6);#5000000;
        touch_kind=0;#8000000;
        touch_kind=23;#5000000;
        touch_kind=0;#8000000;
        touch_kind=14;#5000000;
        touch_kind=0;#8000000;
        touch_kind=24;#5000000;
        touch_kind=0;#8000000;
        if(cmd_69<60)$fatal(1,"User-slot save did not snapshot the patch");
        touch_kind=25;#5000000;
        touch_kind=0;#8000000;touch_kind=45;#8000000;
        touch_kind=0;#8000000;
        if(cmd_64<1)$fatal(1,"User-slot load did not restore key scaling");
        if(cmd_65<5)$fatal(1,"User-slot load did not restore the pitch EG");
        $display("M12 name/slot at %t",$time);
        // ---- FX page: readback and 0x70 writes ----
        touch_kind=32;wait(menu_page==4'd5);#5000000;
        if(cmd_69<30)$fatal(1,"FX page did not read the effect registers");
        touch_kind=0;#8000000;
        touch_kind=33;#5000000;
        touch_kind=0;#8000000;
        touch_kind=34;#5000000;
        touch_kind=0;#8000000;
        touch_kind=35;#5000000;
        touch_kind=0;#8000000;
        if(cmd_70<1)$fatal(1,"FX edit did not send command 0x70");
        touch_kind=32;wait(menu_page==4'd5);#5000000;
        touch_kind=0;#8000000;
        $display("M13 fx page at %t",$time);
        touch_kind=17;wait(menu_page==7);#5000000;
        touch_kind=0;#8000000;touch_kind=36;#5000000;
        touch_kind=0;#8000000;touch_kind=37;#5000000;
        touch_kind=0;#8000000;
        if(dut.background_color!==24'hFFFFFF)$fatal(1,"Accent changed independent background");
        if(dut.wave_color!==24'h647A90)$fatal(1,"Accent slider did not reach SLATE");
        touch_kind=48;#5000000;
        touch_kind=0;#8000000;touch_kind=37;#5000000;
        touch_kind=0;#8000000;
        touch_kind=49;#5000000;
        touch_kind=0;#8000000;touch_kind=14;#5000000;
        touch_kind=0;#8000000;
        if(!dut.headphone_select)$fatal(1,"Headphone output selection did not publish");
        touch_kind=50;#5000000;
        touch_kind=0;#8000000;touch_kind=39;#5000000;
        touch_kind=0;#8000000;
        if(event_count!=3)$fatal(1,"Settings or spectrum entry emitted MIDI");
        touch_kind=15;wait(menu_page==2);#10000000;
        touch_kind=0;#8000000;touch_kind=26;#5000000;
        touch_kind=0;#8000000;
        touch_kind=22;wait(menu_page==6);#5000000;
        touch_kind=0;#8000000;touch_kind=42;#5000000;
        touch_kind=0;#8000000;touch_kind=43;#5000000;
        touch_kind=0;#8000000;touch_kind=44;#5000000;
        touch_kind=0;#8000000;
        if(event_count!=3)$fatal(1,"Cancelled ROM load changed the synth");
        touch_kind=43;#5000000;touch_kind=0;#8000000;
        touch_kind=45;wait(event_count==4);#5000000;
        $display("M14 independent colors, reserved tools and explicit ROM load at %t",$time);
        $fclose(palette_fd);$fclose(cell_fd);$fclose(eg_fd);$fclose(algo_fd);$fclose(eg6_fd);
        $display("PASS real UI firmware, I2C, menu pages, EG/LFO/pitch, name/slots, FX page");$finish;
    end
    initial if($test$plusargs("ui_debug"))forever begin
        #10000000;
        $display("UI DEBUG kind=%0d page=%0d events=%0d pc=%h ctrl=%h",touch_kind,menu_page,event_count,dut.u_cpu.r_pc,dut.ui_state);
        $fflush();
    end
    initial begin #1800000000;$fclose(palette_fd);$fclose(cell_fd);$fclose(eg_fd);$fclose(algo_fd);$fclose(eg6_fd);$fatal(1,"Touch UI timeout PC=%h",dut.address);end
endmodule














