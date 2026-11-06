`timescale 1ns/1ps
module tb_sunny_compiled_defaults;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0,bt_rx=1,start_button_n=1,stop_button_n=1;
    reg [31:0] live_midi_event=0;
    reg live_midi_valid=0;
    wire [31:0] key_midi_event=live_midi_event;
    wire key_midi_valid=live_midi_valid;
    wire [1:0] key_source=0;
    wire [31:0] auto_midi_event;
    wire auto_midi_valid,auto_playing,auto_flushing;
    wire auto_midi_ready=1;
    wire external_mode_busy=0,mode_lock;
    wire bt_tx,led_data,running,count_in,beat_active,initialized,mapping_missing,frame_done,reply_overflow;
    wire calibration_success;
    sunny_tutorial_system #(.CLK_HZ(100000),.UART_CLKS_PER_BIT(8),.LED_COUNT(6),
        .BIT_CYCLES(7),.T0H_CYCLES(2),.T1H_CYCLES(4),.RESET_CYCLES(32),.BUTTON_CYCLES(12),
        .DEFAULT_SPEED(75),.DEFAULT_COUNT_IN(2),.DEFAULT_TRANSPOSE(10),
        .MAP_FILE("sim/tutorial_profile_map_test.mem")) dut(.key_plan_ready(1'b0),.keyboard_disconnected(1'b0),.key_plan_active(),.key_plan_first(),.key_plan_valid(),.key_plan_notes(),.phone_request_valid(),.phone_request_payload(),.phone_request_ready(1'b0),.phone_response_valid(1'b0),.phone_response_token(16'd0),.phone_response_status(8'd0),.phone_response_value(8'd0),.phone_response_was_write(1'b0),.tone_success(),.*);
    task automatic tick;@(posedge clk);#1;endtask
    int cycles;
    initial begin
        repeat(3)tick();@(negedge clk);reset_n=1;
        while(!initialized)tick();
        @(negedge clk);start_button_n=0;
        while(!running)tick();
        @(negedge clk);start_button_n=1;
        cycles=0;
        while(count_in)begin tick();cycles++;if(cycles>106800)$fatal(1,"Compiled speed/count-in not used");end
        if(cycles<106600)$fatal(1,"Compiled count-in completed too early");
        repeat(6)tick();
        if(dut.expected_notes!=(128'd1<<77))$fatal(1,"Compiled +10 transpose not used");
        repeat(2500)tick();
        if(mapping_missing)$fatal(1,"Compiled map was not restored");
        @(negedge clk);stop_button_n=0;repeat(20)tick();
        if(running)$fatal(1,"Local STOP failed with compiled defaults");
        @(negedge clk);reset_n=0;repeat(3)tick();
        @(negedge clk);reset_n=1;stop_button_n=1;
        while(!initialized)tick();
        if(dut.speed_percent!=75||dut.count_in_beats!=2||dut.transpose!=10)
            $fatal(1,"Reset did not restore compiled settings");
        $display("SUNNY_COMPILED_DEFAULTS_OK speed=75 count-in=2 transpose=10 compiled-map reset");
        $finish;
    end
    initial begin #10000000;$fatal(1,"Defaults timeout");end
endmodule
