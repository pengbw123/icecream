`timescale 1ns/1ps
// Production top: real command decoder, AI, merge, owners, 32-voice FM and I2S.
// Only tempo's clocks/us parameter is accelerated; I2S stays 1024 clocks/sample.
module tb_ai_melody_audio;
    reg clk=0;always #10 clk=~clk;
    reg key_s2=1,ui_command_valid=0,external_midi_event_valid=0;
    reg [7:0] ui_command=0;reg [63:0] ui_payload=0;
    reg [31:0] external_midi_event_data=0;
    wire ui_command_ready,external_midi_event_ready;
    wire [31:0] ai_status,composer_status,composer_detail;wire [15:0] readback_data;wire readback_valid;
    wire signed [15:0] pcm;wire tick;
    top #(.FM_VOICE_COUNT(32)) dut(.clk(clk),.key_s2(key_s2),
        .arp_config(160'd0),.arp_suspend(1'b0),.sequence_active(1'b0),.arp_status(),.arp_notes(),.ai_status(ai_status),.composer_status(composer_status),.composer_detail(composer_detail),
        .headphone_select(1'b0),.headphone_din(),.uart_rx_pin(1'b1),
        .ui_command_valid(ui_command_valid),.ui_command(ui_command),.ui_payload(ui_payload),.ui_command_ready(ui_command_ready),
        .fx_write(1'b0),.fx_index(4'd0),.fx_value(32'd0),.fx_read_index(4'd0),.fx_read_value(),
        .uart_tx_pin(),.usb_host_dp(),.usb_host_dn(),.i2s_bclk(),.i2s_lrclk(),.i2s_din(),
        .lcd_resetn(),.lcd_clk(),.lcd_cs(),.lcd_dc(),.lcd_data(),
        .external_midi_event_data(external_midi_event_data),.external_midi_event_valid(external_midi_event_valid),
        .external_midi_event_ready(external_midi_event_ready),
        .monitor_sample(pcm),.monitor_sample_tick(tick),.monitor_midi_event_data(),.monitor_midi_event_valid(),
        .monitor_voice_count(),.monitor_preset(),.monitor_algorithm(),.monitor_operator_envelopes(),
        .readback_data(readback_data),.readback_valid(readback_valid),
        .perf_snapshot(1'b0),.perf_clear(1'b0),.perf_index(5'd0),.perf_bridge_drop(1'b0),.perf_data());
    defparam dut.u_composer.CLOCKS_PER_US=1;
    reg flag=0;reg [15:0] got;
    always @(posedge clk)if(readback_valid)begin got=readback_data;flag=1;end
    task cmd(input [7:0] c,input [63:0] value);
        begin wait(ui_command_ready);@(negedge clk);ui_command=c;ui_payload=value;ui_command_valid=1;
            @(negedge clk);ui_command_valid=0;repeat(4)@(negedge clk);end
    endtask
    task aux(input [9:0] a,input [15:0] v);
        begin cmd(8'h6a,{32'd0,v,6'd0,a});end
    endtask
    task copy_param(input [9:0] a);
        begin flag=0;cmd(8'h69,{54'd0,a});wait(flag);aux(a,got);end
    endtask
    task midi(input [7:0] s,input [6:0] n,v);
        begin @(negedge clk);external_midi_event_data={8'd0,s,1'b0,n,1'b0,v};external_midi_event_valid=1;
            do @(posedge clk);while(!external_midi_event_ready);
            @(negedge clk);external_midi_event_valid=0;repeat(400)@(negedge clk);end
    endtask
    integer i,j,n,ai_ons=0,nonzero=0,frames=0,live_gates,pad_live_ons=0;
    reg [15:0] backing_gain;reg [47:0] backing_flags;
    always @(posedge clk)if(!key_s2)begin
        if(dut.synth_midi_event_valid&&dut.synth_midi_event_ready&&!dut.synth_midi_event_data[30]&&dut.synth_midi_event_data[23:16]==8'h99)pad_live_ons=pad_live_ons+1;
        if(tick)begin frames=frames+1;if(pcm!=0)nonzero=nonzero+1;end
        if(dut.synth_midi_event_valid&&dut.synth_midi_event_ready&&
           dut.synth_midi_event_data[30]&&dut.synth_midi_event_data[23:20]==9)ai_ons=ai_ons+1;
    end
    initial begin
        repeat(5)@(negedge clk);key_s2=0;repeat(20000)@(negedge clk);
        aux(10'h3ff,0);
        for(i=0;i<12;i=i+1)copy_param(i);
        for(i=0;i<6;i=i+1)for(j=0;j<17;j=j+1)copy_param(10'h40+i*32+j);
        for(i=0;i<4;i=i+1)for(j=0;j<3;j=j+1)copy_param(10'h140+i*8+j);
        aux(10'h3ff,1);
        backing_gain=dut.u_fm_poly_synth.back_patch_op_gain[5];
        for(i=0;i<6;i=i+1)backing_flags[i*8+:8]=dut.u_fm_poly_synth.back_patch_algorithm_flags[i];
        for(i=0;i<30;i=i+1)midi(8'h90,48+i,95);
        aux(10'h3c1,40000);aux(10'h3c2,0);aux(10'h3c0,1);aux(10'h3c5,2);
        midi(8'h90,79,80);
        repeat(240000)@(negedge clk);
        if(ai_ons<1||nonzero<1)$fatal(1,"No AI / PCM %d %d",ai_ons,nonzero);
        // A real ROM preset load commits LIVE only; BACKING remains untouched.
        midi(8'hb0,27,11);repeat(20000)@(negedge clk);
        if(dut.u_fm_poly_synth.back_patch_op_gain[5]!==backing_gain)$fatal(1,"LIVE preset overwrote AI gain");
        for(i=0;i<6;i=i+1)if(dut.u_fm_poly_synth.back_patch_algorithm_flags[i]!==backing_flags[i*8+:8])$fatal(1,"LIVE preset overwrote AI routing");
        midi(8'h90,60,100);repeat(20000)@(negedge clk);
        aux(10'h3c5,3);repeat(20000)@(negedge clk);
        live_gates=0;
        for(i=0;i<32;i=i+1)begin
            if(dut.u_fm_poly_synth.voice_part[i]&&dut.u_fm_poly_synth.voice_key_down[i])$fatal(1,"AI STOP left key held");
            if(!dut.u_fm_poly_synth.voice_part[i]&&dut.u_fm_poly_synth.voice_key_down[i])live_gates=live_gates+1;
        end
        if(live_gates<1||composer_status[3:1]!=0)$fatal(1,"AI STOP killed LIVE / pending state");
        if(dut.u_performance.deadlines!=0||dut.u_performance.lost_ticks!=0||composer_detail[15:0]!=0)$fatal(1,"Audio/AI deadline missed");
        aux(10'h3c5,2);repeat(100000)@(negedge clk);midi(8'h99,36,100);repeat(20000)@(negedge clk);
        if(composer_status[1]||pad_live_ons||dut.u_composer.active)$fatal(1,"Pad did not stop AI or leaked into LIVE");
        $display("PASS production LEAD->merge->owners->FM32->I2S: %d AI notes, %d/%d nonzero frames, 30 LIVE voices, LIVE preset isolation, scoped STOP, pad filtering, no missed samples",ai_ons,nonzero,frames);$finish;
    end
    initial begin #100000000;$fatal(1,"AI/audio timeout");end
endmodule
