`timescale 1ns/1ps
module tb_ov5640_config;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,heartbeat=0,frame_toggle=0,present=1,wrong_id=0,corrupt=0,hold_scl=0,hold_sda=0;
    tri1 scl,sda;wire stretch,ready,sensor_reset_n;wire [2:0] fault;wire [15:0] chip_id;
    assign scl=(hold_scl||stretch)?1'b0:1'bz;assign sda=hold_sda?1'b0:1'bz;
    ov5640_config #(.QUARTER_CLOCKS(4),.RESET_CLOCKS(20),.BOOT_CLOCKS(50),
        .SOFT_RESET_CLOCKS(30),.RETRY_CLOCKS(100),.WATCHDOG_CLOCKS(25000)) dut(
        .clk(clk),.reset_n(reset_n),.frame_toggle(frame_toggle),.camera_reset_n(sensor_reset_n),
        .scl(scl),.sda(sda),.ready(ready),.fault(fault),.chip_id(chip_id));
    defparam dut.u_bus.TIMEOUT_QUARTERS=100;
    ov5640_sccb_model model(.scl(scl),.sensor_reset_n(sensor_reset_n),.present(present),
        .wrong_id(wrong_id),.corrupt_readback(corrupt),.nack_first(1'b1),.stretch_first(1'b1),.sda(sda),.stretch_low(stretch));
    integer beat_count=0;
    always @(negedge clk)if(heartbeat)begin beat_count=beat_count+1;if(beat_count==100)begin frame_toggle=~frame_toggle;beat_count=0;end end
    task reset;begin @(negedge clk);reset_n=0;repeat(5)@(negedge clk);reset_n=1;end endtask
    task success;begin wait(ready);#1;
        if(fault||chip_id!==16'h5640||model.registers[16'h3809]!==8'h40||model.registers[16'h380b]!==8'hf0||
           model.registers[16'h4300]!==8'h61||!model.stretched)$fatal(1,"Mode/ID/config verification failed");
    end endtask
    initial begin
        reset;wait(fault==1);success;
        if(model.writes!=252||model.reads!=15||model.registers[16'h5001]!==8'ha3||model.registers[16'h460c]!==8'h22||model.registers[16'h3035]!==8'h41)$fatal(1,"Incomplete QVGA configuration writes=%d reads=%d",model.writes,model.reads);
        // A first stable stream delayed beyond the ordinary running timeout
        // must get its startup grace, but startup must still be bounded.
        repeat(50000)@(negedge clk);
        if(!ready||fault)$fatal(1,"Startup reset before sensor/warmup could settle");
        heartbeat=1;repeat(200)@(negedge clk);
        heartbeat=0;repeat(24000)@(negedge clk);
        if(!ready||fault)$fatal(1,"Running watchdog fired early");
        repeat(1100)@(negedge clk);
        if(ready||fault!=4)$fatal(1,"First valid stream did not arm running watchdog");
        heartbeat=0;success;
        repeat(120000)@(negedge clk);
        if(!ready||fault)$fatal(1,"Startup grace fired early after retry");
        repeat(5100)@(negedge clk);
        if(ready||fault!=4)$fatal(1,"Startup without any stream did not time out");
        heartbeat=1;success;
        wrong_id=1;reset;wait(fault==2);if(ready)$fatal(1,"Wrong ID accepted");wrong_id=0;success;
        corrupt=1;reset;wait(fault==3);if(ready)$fatal(1,"Wrong mode readback accepted");corrupt=0;success;
        present=0;reset;wait(fault==1);if(ready)$fatal(1,"Absent camera accepted");present=1;success;
        hold_scl=1;reset;wait(fault==1);if(!dut.u_bus.failed)$fatal(1,"Stuck SCL timeout missing");hold_scl=0;success;
        hold_sda=1;reset;wait(fault==1);hold_sda=0;success;
        $display("PASS OV5640 physical SCCB: repeated START/IDs, 252 writes, 13 mode readbacks, master NACK, retry/stretch, wrong ID/mode, absent/stuck bus, delayed startup grace, bounded no-stream retry and running watchdog recovery");$finish;
    end
    initial begin #80000000;$fatal(1,"Config timeout state=%d bus=%d fault=%d writes=%d reads=%d",dut.state,dut.u_bus.state,fault,model.writes,model.reads);end
endmodule
