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
    wire visual_mode;
    wire display_auto_gain;
    wire [6:0] xy_delay;
    wire [3:0] menu_page;
    reg [15:0] pr_data=16'h0021;
    reg pr_valid=0;
    integer cmd_69=0,cmd_60=0,cmd_61=0,cmd_62=0,cmd_63=0,cmd_64=0,cmd_65=0,cmd_70=0,text_cells=0,pal_writes=0;
    touch_ui_controller dut(.clk(clk),.reset_n(reset_n),.tp_scl(scl),.tp_sda(sda),
        .tp_int(int_pin),.tp_rst(rst_pin),.uart_tx(uart),.midi_event_data(event_word),
        .midi_event_valid(valid),.midi_event_ready(1'b1),.monitor_event(32'd0),
        .monitor_event_valid(1'b0),.preset_index(5'd0),.algorithm(5'd4),.active_voices(5'd0),
        .touch_present(present),.keyboard_octave(octave),.master_volume(volume),
        .visual_mode(visual_mode),.xy_delay_samples(xy_delay),.display_auto_gain(display_auto_gain),
        .command_ready(1'b1),.fx_read_value(32'd0),
        .menu_page(menu_page),.patch_read_data(pr_data),.patch_read_valid(pr_valid));
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
    integer cell_fd,eg_fd,algo_fd,eg6_fd;
    reg [9:0] eg6_base;
    initial cell_fd=$fopen("tmp/menu_cells.txt","w");
    initial eg_fd=$fopen("tmp/eg_curve.txt","w");
    initial algo_fd=$fopen("tmp/algo_map.txt","w");
    initial eg6_fd=$fopen("tmp/eg6_panels.txt","w");
    always @(posedge clk)begin
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
        if(dut.text_write)text_cells<=text_cells+1;
        if(dut.palette_write)pal_writes<=pal_writes+1;
    end
    integer touch_kind=1;
    reg slave_low=0;
    assign sda=slave_low?1'b0:1'bz;
    integer state=0,bits=0,reg_bytes=0;
    reg [7:0] sh=0,send_byte;
    reg address_phase=1,reading=0,ack_master;
    reg [15:0] pointer=0;
    function [7:0] goodix_read(input [15:0] addr);
        integer px,py;
        begin
            px=touch_kind==1?750:40;py=touch_kind==1?100:450;
            if(touch_kind==6)begin px=750;py=310;end
            if(touch_kind==7)begin px=750;py=345;end
            if(touch_kind==8)begin px=650;py=210;end
            if(touch_kind==9)begin px=750;py=378;end
            if(touch_kind==10)begin px=100;py=8;end
            if(touch_kind==11)begin px=8;py=8;end
            if(touch_kind==12)begin px=104;py=8;end
            if(touch_kind==13)begin px=200;py=104;end
            if(touch_kind==14)begin px=750;py=450;end
            if(touch_kind==15)begin px=200;py=8;end
            if(touch_kind==17)begin px=720;py=8;end
            if(touch_kind==18)begin px=400;py=200;end
            if(touch_kind==19)begin px=338;py=8;end
            if(touch_kind==20)begin px=434;py=8;end
            if(touch_kind==21)begin px=700;py=72;end
            if(touch_kind==22)begin px=626;py=8;end
            if(touch_kind==23)begin px=130;py=104;end
            if(touch_kind==24)begin px=280;py=168;end
            if(touch_kind==25)begin px=440;py=168;end
            if(touch_kind==26)begin px=200;py=312;end
            if(touch_kind==27)begin px=750;py=450;end
            if(touch_kind==28)begin px=200;py=152;end
            if(touch_kind==29)begin px=750;py=450;end
            if(touch_kind==30)begin px=50;py=450;end
            if(touch_kind==31)begin px=750;py=450;end
            if(touch_kind==32)begin px=530;py=8;end
            if(touch_kind==33)begin px=30;py=72;end
            if(touch_kind==34)begin px=200;py=120;end
            if(touch_kind==35)begin px=750;py=450;end
            if(touch_kind==16)begin px=30;py=72;end
            case(addr)
                16'h8140:goodix_read="9";16'h8141:goodix_read="1";16'h8142:goodix_read="1";
                16'h8146:goodix_read=8'h20;16'h8147:goodix_read=8'h03;
                16'h8148:goodix_read=8'hE0;16'h8149:goodix_read=8'h01;
                16'h8047:goodix_read=8'h81;
                16'h814E:goodix_read=touch_kind==3?8'h00:touch_kind==0?8'h80:touch_kind==4?8'h82:8'h81;
                16'h814F:goodix_read=touch_kind==5?1:0;
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
                if(reading)begin send_byte=goodix_read(pointer);bits=7;slave_low=!send_byte[7];state=5;end
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
    integer event_count=0;
    always @(posedge clk)if(valid)begin
        $display("UI MIDI %h at %t",event_word,$time);
        case(event_count)
            0:if(event_word!==32'h00B01B01)$fatal(1,"Preset button event");
            1:if(event_word!==32'h00903064)$fatal(1,"Touch C3 note-on event");
            2:if(event_word!==32'h00803000)$fatal(1,"Touch release event");
            default:$fatal(1,"Held control generated duplicate events");
        endcase
        event_count=event_count+1;
    end
    initial begin
        repeat(10)@(negedge clk);reset_n=1;
        // The unmodified piano1 reset sequencer is already hardware proven.
        // Skip its 177 ms only in this firmware/I2C regression.
        force dut.reset_ready=1'b1;
        wait(present);wait(event_count==1);#10000000;
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
        touch_kind=7;wait(xy_delay==25);#5000000;
        if(xy_delay!=25)$fatal(1,"Held delay button repeated");
        touch_kind=0;#5000000;
        touch_kind=8;wait(octave==-1);#5000000;
        if(!visual_mode||xy_delay!=25)$fatal(1,"Negative octave overwrote view/delay bits");
        if(!display_auto_gain)$fatal(1,"Visual AGC not enabled by default");
        touch_kind=0;#5000000;
        touch_kind=9;wait(!display_auto_gain);#5000000;
        if(display_auto_gain)$fatal(1,"Held AGC button repeated");
        touch_kind=0;#5000000;
        touch_kind=9;wait(display_auto_gain);
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
        $fclose(cell_fd);$fclose(eg_fd);$fclose(algo_fd);$fclose(eg6_fd);
        $display("PASS real UI firmware, I2C, menu pages, EG/LFO/pitch, name/slots, FX page");$finish;
    end
    initial begin #900000000;$fclose(cell_fd);$fclose(eg_fd);$fclose(algo_fd);$fclose(eg6_fd);$fatal(1,"Touch UI timeout PC=%h",dut.address);end
endmodule














