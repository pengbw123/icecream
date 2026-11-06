`timescale 1ns/1ps
module tb_audio_xy_scope;
    reg clk=0;always #10 clk=~clk;
    reg pclk=0;always #15 pclk=~pclk;
    reg reset_n=0,tick=0,frame=0;
    reg signed [15:0] pcm=0;
    reg [14:0] address=0;
    wire pixel;
    audio_xy_scope dut(.clk(clk),.reset_n(reset_n),.sample_tick(tick),.audio_sample(pcm),
        .delay_samples(7'd24),.auto_gain(1'b1),.pixel_clk(pclk),.video_reset_n(reset_n),
        .frame_latch(frame),.pixel_address(address),.pixel_on(pixel));
    integer div=0,n=0,lit=0,i,q0=0,q1=0,q2=0,q3=0,ref_pointer=0;
    reg signed [15:0] reference_history[0:127];
    real phase;
    integer attack_case=0;
    always @(negedge clk)if(reset_n)begin
        div=(div+1)%1024;tick=div==0;
        if(tick)begin phase=n*6.283185307179586/96.0;
            pcm=$rtoi((attack_case&&n<200?100:28000)*$sin(phase));n=n+1;end
    end
    always @(posedge clk)if(reset_n && (dut.state==0||dut.drawing))
        if(dut.write_bank==dut.display_bank)$fatal(1,"XY bank collision");
    always @(posedge clk)if(reset_n && dut.drawing)
        if(dut.draw_x<16||dut.draw_x>240||dut.draw_y<8||dut.draw_y>120)
            $fatal(1,"XY trace outside headroom at %d,%d",dut.draw_x,dut.draw_y);
    always @(posedge clk)if(reset_n&&tick)begin
        if(n>24 && dut.delayed_sample!==reference_history[(ref_pointer+128-24)%128])
            $fatal(1,"XY delay is not exactly 24 samples");
        reference_history[ref_pointer]=pcm;ref_pointer=(ref_pointer+1)%128;
    end
    initial begin
        attack_case=$test$plusargs("attack");
        repeat(10)@(negedge clk);reset_n=1;
        wait(dut.state==6);
        if(dut.capture_gain!=0)$fatal(1,"Whole-snapshot peak ignored a loud attack");
        repeat(5)@(negedge pclk);frame=1;
        @(negedge pclk);frame=0;wait(dut.display_valid);
        for(i=0;i<32768;i=i+1)begin
            @(negedge pclk);address=i;@(posedge pclk);#1;
            if(pixel===1'bx)$fatal(1,"Uninitialized XY pixel published");
            if(pixel)begin
                lit=lit+1;
                if(i%256>=128)begin if(i/256>=64)q0=q0+1;else q1=q1+1;end
                else begin if(i/256>=64)q2=q2+1;else q3=q3+1;end
            end
        end
        if(lit<300||lit>3000)$fatal(1,"Unexpected circle occupancy %0d",lit);
        if(q0<50||q1<50||q2<50||q3<50)$fatal(1,"XY should fill all four quadrants");
        // quarter-period delay must spread into both diagonal quadrants.
        address={7'd64,8'd237};@(posedge pclk);#1;
        $display("PASS delay-XY capture, initialized bank, ownership and circle occupancy=%0d",lit);
        $finish;
    end
    initial begin #30000000;$fatal(1,"XY timeout");end
endmodule
