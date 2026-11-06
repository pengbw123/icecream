`timescale 1ns/1ps
module tb_ai_cpu_benchmark;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    wire [31:0] address,write_data;wire write_en;wire [1:0] request;
    integer clocks=0,cases=0,i,which;
    reg [31:0] measured=0,received[0:7],expected[0:1295];
    reg [2:0] actions[0:161];
    wire [31:0] read_data=(address==32'h23000000)?clocks:0;
    RV32I #(.FIRMWARE_FILE("tmp/ai_cpu_benchmark/benchmark.hex")) cpu(
        .CLK(clk),.RST_X(reset_n),.w_stall(1'b0),.w_mic_addr(address),.w_data(read_data),
        .w_mic_wdata(write_data),.w_mic_mmuwe(write_en),.w_mic_ctrl(),.w_mic_req(request));
    always @(posedge clk)begin
        clocks<=clocks+1;
        if(reset_n&&write_en&&address[31:8]==24'h230000)begin
            if(address[7:2]>=2&&address[7:2]<10)received[address[7:2]-2]=write_data;
            if(address[7:2]==10)measured=write_data;
            if(address[7:2]==1)begin
                which=cases==0?0:161;
                for(i=0;i<8;i=i+1)if(received[i]!==expected[which*8+i])$fatal(1,"CPU integer logit mismatch case %d class %d",cases,i);
                if(write_data[10:8]!==actions[which])$fatal(1,"CPU argmax mismatch");
                $display("CPU_BASELINE case=%d clocks=%d ns=%d RTL_clocks=3664 speedup_x100=%d",cases,measured,measured*20,(measured*100)/3664);
                cases=cases+1;
                if(cases==2)begin $display("PASS existing 50MHz RV32I -Oz scalar C: both vectors and all logits equal to trained FPGA integer reference");$finish;end
            end
        end
    end
    initial begin
        $readmemh("src/generated/ai_bass/test_scores.mem",expected);
        $readmemh("src/generated/ai_bass/test_actions.mem",actions);
        repeat(4)@(negedge clk);reset_n=1;
    end
    initial begin #200000000;$fatal(1,"CPU baseline timeout");end
endmodule
