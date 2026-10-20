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
    touch_ui_controller dut(.clk(clk),.reset_n(reset_n),.tp_scl(scl),.tp_sda(sda),
        .tp_int(int_pin),.tp_rst(rst_pin),.uart_tx(uart),.midi_event_data(event_word),
        .midi_event_valid(valid),.midi_event_ready(1'b1),.monitor_event(32'd0),
        .monitor_event_valid(1'b0),.preset_index(5'd0),.algorithm(5'd4),.active_voices(5'd0),
        .touch_present(present),.keyboard_octave(octave),.master_volume(volume),
        .visual_mode(visual_mode),.xy_delay_samples(xy_delay),.display_auto_gain(display_auto_gain),
        .command_ready(1'b1),.fx_read_value(32'd0));
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
            if(touch_kind==6)begin px=750;py=360;end
            if(touch_kind==7)begin px=750;py=420;end
            if(touch_kind==8)begin px=650;py=210;end
            if(touch_kind==9)begin px=750;py=460;end
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
        $display("PASS real UI firmware, I2C, held control, shared-key fingers and final release");$finish;
    end
    initial begin #180000000;$fatal(1,"Touch UI timeout PC=%h",dut.address);end
endmodule
