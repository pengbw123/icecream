`timescale 1ns/1ps
module tb_lesson_player;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,cw=0,hv=0,ready=1,bank=0,sw=0;
    reg [31:0] cd=0,he=0,sd=0;
    reg [6:0] sa=0;
    reg [7:0] count=42;
    reg [15:0] ending=1664;
    wire [31:0] data,status,view;
    wire valid;
    lesson_player #(.CLOCKS_PER_MS(1)) dut(.clk(clk),.reset_n(reset_n),
        .control_write(cw),.control_data(cd),.human_event(he),.human_valid(hv),
        .score_bank(bank),.score_count(count),.score_end(ending),.score_write(sw),.score_address(sa),.score_data(sd),
        .midi_data(data),.midi_valid(valid),.midi_ready(ready),.status(status),.view_state(view));
    integer ons=0,offs=0;
    reg [127:0] held=0;
    always @(posedge clk)if(valid&&ready)begin
        if(!data[31])$fatal(1,"Demo owner tag missing");
        if(data[23:20]==9)begin
            if(held!=0)$fatal(1,"Overlapping melody note");
            held[data[14:8]]<=1;ons=ons+1;
        end else begin
            if(!held[data[14:8]])$fatal(1,"Unmatched Note Off");
            held[data[14:8]]<=0;offs=offs+1;
        end
    end
    task command(input [31:0] v);begin @(negedge clk);cd=v;cw=1;@(negedge clk);cw=0;end endtask
    task human(input [6:0] n,input [6:0] velocity);begin
        @(negedge clk);he={8'd0,8'h90,1'b0,n,1'b0,velocity};hv=1;
        @(negedge clk);hv=0;
    end endtask
    integer p,i,n;
    initial begin
        #100;reset_n=1;command(32'h640b); // enable, run, restart, WAIT.
        wait(status[3]);p=view[15:0];
        repeat(500)@(negedge clk);
        if(view[15:0]!=p||p!=128)$fatal(1,"Wait did not freeze at first onset");
        human(62,100);repeat(20)@(negedge clk);
        if(status[31:24]!=0)$fatal(1,"Wrong note advanced lesson");
        human(60,100);wait(status[31:24]==1);
        wait(status[3]);repeat(400)@(negedge clk);
        if(status[31:24]!=1)$fatal(1,"Held repeated note advanced without new press");
        human(60,0);repeat(20)@(negedge clk);
        if(status[31:24]!=1)$fatal(1,"Velocity-zero Note On accepted as hit");
        human(60,100);wait(status[31:24]==2);
        command(32'h6401);p=view[15:0];repeat(200)@(negedge clk);
        if(view[15:0]!=p)$fatal(1,"Pause advanced timeline");
        // Demo restart. Backpressure must keep the onset and pending data stable.
        ready=0;command(32'h640f);wait(valid);p=view[15:0];n=data;
        repeat(300)@(negedge clk);
        if(view[15:0]!=p||data!==n)$fatal(1,"Backpressure corrupted demo");
        command(32'h6405);repeat(20)@(negedge clk);
        if(valid||held!=0||status[31:24]!=0)$fatal(1,"Paused pending note leaked or skipped");
        ready=1;command(32'h640f);wait(ons==1);command(32'h6405);
        wait(offs==1);@(negedge clk);if(held!=0)$fatal(1,"Pause did not drain Note Off");
        command(32'h960f); // 150%, complete song with occasional downstream stalls.
        wait(status[4]);repeat(5)@(negedge clk);
        if(ons!=43||offs!=43||held!=0)$fatal(1,"Demo count mismatch on=%0d off=%0d",ons,offs);
        command(0);repeat(10)@(negedge clk);
        // Upload bank and metadata are independent of immutable factory ROM.
        @(negedge clk);sa=0;sd={16'd4,9'd8,7'd72};sw=1;
        @(negedge clk);sw=0;bank=1;count=1;ending=16;
        command(32'h640f);wait(ons==44);if(!held[72])@(negedge clk);
        command(0);wait(offs==44);repeat(10)@(negedge clk);
        if(held!=0||status[0])$fatal(1,"Page exit left a stuck demo note");
        bank=0;count=42;ending=1664;command(32'h640b);wait(status[3]);
        if(status[14:8]!=60)$fatal(1,"Factory score not restored");
        $display("PASS lesson wait/wrong/repeated/zero/pause/backpressure/restart/demo/end/upload/exit");$finish;
    end
    initial begin #100000000;$fatal(1,"Lesson timeout status=%h view=%h",status,view);end
endmodule
