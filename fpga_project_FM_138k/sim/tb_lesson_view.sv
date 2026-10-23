`timescale 1ns/1ps
module tb_lesson_view;
    reg clk=0,pclk=0;always #10 clk=~clk;always #15 pclk=~pclk;
    reg reset_n=0,vr=0;
    reg [10:0] x=0;reg [9:0] y=0;
    wire latch=x==0&&y==480;
    reg [31:0] state=32'h00010080,event_word=0;
    reg ev=0;
    wire en8,ink8,en6,ink6;wire [23:0] c8,c6;
    lesson_view #(.WIDTH(800)) a(.clk(clk),.reset_n(reset_n),.pclk(pclk),.video_reset_n(vr),.frame_latch(latch),.x(x),.y(y),
        .state(state),.score_bank(1'b0),.score_count(8'd42),.score_write(1'b0),.score_address(7'd0),.score_data(32'd0),
        .midi_event(event_word),.midi_valid(ev),.background(24'h0e1116),.accent(24'h52b9d2),.enabled(en8),.ink(ink8),.color(c8));
    lesson_view #(.WIDTH(640)) b(.clk(clk),.reset_n(reset_n),.pclk(pclk),.video_reset_n(vr),.frame_latch(latch),.x(x),.y(y),
        .state(state),.score_bank(1'b0),.score_count(8'd42),.score_write(1'b0),.score_address(7'd0),.score_data(32'd0),
        .midi_event(event_word),.midi_valid(ev),.background(24'h0e1116),.accent(24'h52b9d2),.enabled(en6),.ink(ink6),.color(c6));
    integer frames=0,fd,fd6,bars=0;
    always @(negedge pclk)begin
        if(vr)begin
            if(x==1055)begin x=0;if(y==524)begin y=0;frames=frames+1;end else y=y+1'b1;end
            else x=x+1'b1;
        end
    end
    initial begin
        #100;reset_n=1;vr=1;
        @(negedge clk);event_word=32'h00903c64;ev=1;@(negedge clk);ev=0;
        wait(frames==3);
        fd=$fopen("tmp/lesson_rgb.ppm","w");$fwrite(fd,"P3\n800 480\n255\n");
        fd6=$fopen("tmp/lesson_hdmi.ppm","w");$fwrite(fd6,"P3\n640 480\n255\n");
        while(frames==3)begin
            @(posedge pclk);#1;
            if(x<800&&y<480)begin
                $fwrite(fd,"%0d %0d %0d\n",c8[23:16],c8[15:8],c8[7:0]);
                if(y>=128&&y<350&&c8==24'h52b9d2)bars=bars+1;
            end
            if(x<640&&y<480)$fwrite(fd6,"%0d %0d %0d\n",c6[23:16],c6[15:8],c6[7:0]);
            if(x==400&&y==300&&c8!==24'h52b9d2)$fatal(1,"C4 bar misaligned");
            if(x==613&&y==280&&c8!==24'h52b9d2)$fatal(1,"G4 bar misaligned");
            if(x==320&&y==300&&c6!==24'h52b9d2)$fatal(1,"HDMI C4 bar misaligned");
            if(x==400&&y==450&&c8!==24'h52b9d2)$fatal(1,"Pressed key not highlighted");
            if(x==10&&y==450&&c8!==24'hf5f8fb)$fatal(1,"Unpressed white key incorrect");
        end
        $fclose(fd);$fclose(fd6);
        if(bars<1000)$fatal(1,"Missing falling bars");
        vr=0;#100;vr=1;wait(frames==6);
        if(!en8||!en6)$fatal(1,"Snapshot did not recover after PLL loss");
        state=0;wait(frames==9);
        if(en8||en6)$fatal(1,"Exited lesson still displayed");
        $display("PASS RGB/HDMI lesson alignment, durations, keyboard, snapshot and PLL recovery");$finish;
    end
    initial begin #200000000;$fatal(1,"Lesson view timeout");end
endmodule
