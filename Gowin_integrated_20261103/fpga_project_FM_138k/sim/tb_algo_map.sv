`timescale 1ns/1ps
// Real C lists and golden bitmap pixels; render each probed row one line ahead.
module tb_algo_map;
    reg pclk=0,wclk=0;always #15 pclk=~pclk;always #10 wclk=~wclk;
    reg reset_n=0,enable=0,we=0;
    reg [10:0] h=1;reg [9:0] v=0;
    reg [14:0] waddr=0;reg [7:0] wdata=0;
    wire ink;wire [1:0] cls;
    ui_algo_map dut(.pclk(pclk),.video_reset_n(reset_n),.h(h),.v(v),.enable(enable),
        .wclk(wclk),.we(we),.waddr(waddr),.wdata(wdata),.ink(ink),.cls(cls));
    reg [35:0] rects[0:16447];reg [23:0] samples[0:131071];
    task wr(input [14:0] a,input [7:0] d);
        begin @(negedge wclk);waddr=a;wdata=d;we=1;@(negedge wclk);we=0;end
    endtask
    task check(input integer x,input integer y,input [1:0] expected);
        begin @(negedge pclk);h=x;v=y;repeat(2)@(posedge pclk);#1;
            if(cls!==expected||ink!==(expected!=0))$fatal(1,"Pixel %d,%d got %d expected %d",x,y,cls,expected);
        end
    endtask
    integer max_cycles=0;
    task render_row(input integer y);
        integer t,finished;
        begin
            @(negedge pclk);v=159+y;finished=0;
            for(t=0;t<1056;t=t+1)begin
                h=t;@(posedge pclk);#1;
                if(!finished&&dut.ready&&dut.render_y==y)begin finished=1;if(t>max_cycles)max_cycles=t;end
                @(negedge pclk);
            end
            if(!dut.ready||dut.render_y!=y)$fatal(1,"Scanline deadline y=%d state=%d index=%d",y,dut.state,dut.rect_index);
            v=160+y;h=0;@(posedge pclk);#1;
            if(!dut.display_valid)$fatal(1,"Completed row not committed");
            @(negedge pclk);h=1;
        end
    endtask
    integer a,b,j,n,sp=0,points,base,y,have_row,graph_cycles;reg [35:0] r;reg [23:0] sample;
    initial begin
        $readmemh("tmp/algo_rect_test/rectangles.mem",rects);
        $readmemh("tmp/algo_rect_test/samples.mem",samples);
        repeat(4)@(negedge pclk);reset_n=1;
        for(a=0;a<64;a=a+1)begin
            enable=0;repeat(8)@(negedge pclk);h=1;v=0;
            n=rects[a*257];
            for(b=0;b<n;b=b+1)begin
                r=rects[a*257+b+1];
                for(j=0;j<5;j=j+1)wr(b*8+j,(r>>(8*j))&255);
            end
            wr(15'h7ff8,n&255);wr(15'h7ff9,n>>8);
            enable=1;repeat(8)@(negedge pclk);
            points=samples[sp];sp=sp+1;base=sp;
            for(y=0;y<256;y=y+1)begin
                have_row=0;
                for(b=0;b<points;b=b+1)if(samples[base+b][16:9]==y)have_row=1;
                if(have_row)begin
                    render_row(y);
                    for(b=0;b<points;b=b+1)begin
                        sample=samples[base+b];
                        if(sample[16:9]==y)check(144+sample[8:0],160+y,sample[18:17]);
                    end
                end
            end
            sp=base+points;
            check(143,415,0);check(656,415,0);check(144,159,0);check(144,416,0);
        end
        graph_cycles=max_cycles;
        enable=0;repeat(8)@(negedge pclk);check(377,366,0);
        for(b=0;b<256;b=b+1)begin
            r=(36'd1<<34);if(b==255)r=(36'd3<<34);
            for(j=0;j<5;j=j+1)wr(b*8+j,(r>>(8*j))&255);
        end
        wr(15'h7ff8,0);wr(15'h7ff9,1);enable=1;repeat(8)@(negedge pclk);
        render_row(0);check(144,160,3);check(145,160,0);
        reset_n=0;repeat(4)@(negedge pclk);check(144,160,0);
        $display("PASS 64 algorithm/custom scanline lists, golden pixels, two-clock pixel latency, graphs %d/1056 cycles, 256-entry stress %d/1056, disable/reset",graph_cycles,max_cycles);$finish;
    end
    initial begin #500000000;$fatal(1,"rectangle timeout");end
endmodule
