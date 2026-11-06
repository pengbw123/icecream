`timescale 1ns/1ps
module tb_es8388_output;
    reg clk=0;
    always #10 clk=~clk;
    reg reset_n=0;
    tri1 scl,sda;
    reg slave_sda_low=0,slave_scl_low=0;
    assign sda=slave_sda_low?1'b0:1'bz;
    assign scl=slave_scl_low?1'b0:1'bz;
    wire ready,error,mclk,bclk,lrclk,data;
    wire src_bclk,src_lrclk,src_data,tick;
    reg signed [15:0] pcm=16'sh1537;
    i2s_tx tx(.clk(clk),.reset_n(reset_n),.sample_left(pcm),.sample_right(pcm),
        .sample_tick(tick),.i2s_bclk(src_bclk),.i2s_lrclk(src_lrclk),.i2s_din(src_data));
    es8388_output #(.I2C_QUARTER_CLOCKS(8),.POWERUP_CLOCKS(20),
        .SETTLE_CLOCKS(100),.RETRY_CLOCKS(80)) dut (
        .clk(clk),.reset_n(reset_n),.i2s_bclk(src_bclk),.i2s_lrclk(src_lrclk),.i2s_data(src_data),
        .aud_mclk(mclk),.aud_bclk(bclk),.aud_lrclk(lrclk),.aud_dacdat(data),
        .codec_scl(scl),.codec_sda(sda),.ready(ready),.init_error(error));
    integer accepted=0,attempts=0,b,j;
    reg [7:0] bytes[0:2];
    reg injected=0,stretched=0;
    reg [7:0] regs[0:52];
    // Codec model: first address is NACKed, then valid ACKs and one stretch.
    initial forever begin : transaction
        @(negedge sda);
        if(scl===1'b1 && reset_n) begin : receive
            attempts=attempts+1;
            for(b=0;b<3;b=b+1) begin
                bytes[b]=0;
                for(j=7;j>=0;j=j-1) begin
                    @(posedge scl);bytes[b][j]=sda;
                end
                @(negedge scl);
                if(!injected) begin
                    injected=1;
                    @(posedge scl);@(negedge scl);
                    disable receive;
                end
                slave_sda_low=1;
                if(!stretched && b==1) begin
                    slave_scl_low=1;
                    repeat(30) @(posedge clk);
                    slave_scl_low=0;stretched=1;
                end
                @(posedge scl);@(negedge scl);slave_sda_low=0;
            end
            if(bytes[0]!==8'h20) $fatal(1,"wrong codec address %h",bytes[0]);
            if(bytes[1]>52) $fatal(1,"bad register %h",bytes[1]);
            regs[bytes[1]]=bytes[2];accepted=accepted+1;
        end
    end
    // Decode actual I2S slots rather than only checking output wires.
    reg [31:0] word;
    integer slot,channel,frame;
    initial begin
        wait(ready);
        for(frame=0;frame<3;frame=frame+1) begin
            for(channel=0;channel<2;channel=channel+1) begin
                if(channel==0) @(negedge lrclk);else @(posedge lrclk);
                @(posedge bclk); // standard I2S one-bit delay
                word=0;
                for(slot=0;slot<32;slot=slot+1) begin
                    @(posedge bclk);word={word[30:0],data};
                end
                if(word[31:16]!==pcm || word[15:0]!==0)
                    $fatal(1,"I2S data mismatch: %h expected %h",word,pcm);
            end
            @(negedge clk);pcm=pcm>>>1;
            repeat(3) @(posedge tick);
        end
        pcm=0;repeat(3) @(posedge tick);
        if(data!==0) $fatal(1,"master-volume silence not mirrored");
        $display("PASS ES8388 ACK retry, stretching, configuration, clocks and identical PCM");
        $finish;
    end
    integer mcycles=0,syscycles=0,last_mclk=0;
    always @(posedge clk) begin
        #1;
        if(reset_n) begin
            syscycles=syscycles+1;
            if(mclk!=last_mclk) begin
                if(mcycles!=0 && syscycles-mcycles!=2) $fatal(1,"wrong MCLK divider");
                mcycles=syscycles;
            end
            last_mclk=mclk;
            if(dut.clocks_enabled) begin
                if({bclk,lrclk,data}!=={src_bclk,src_lrclk,src_data}) $fatal(1,"I2S mirror mismatch");
                if(accepted<9) $fatal(1,"FPGA drives clocks before slave-mode ACK");
            end else if({bclk,lrclk}!==2'bzz) $fatal(1,"codec clock pins not released during reset");
        end
    end
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        wait(ready);#1;
        if(error || accepted!=30 || attempts!=31 || !stretched)
            $fatal(1,"initialization failed accepted=%0d attempts=%0d",accepted,attempts);
        if(regs[8]!==0 || regs[23]!==8'h18 || regs[24]!==2 || regs[4]!==8'h30 ||
           regs[39]!==8'hB8 || regs[42]!==8'hB8 || regs[25]!==8'h22 ||
           regs[26]!==0 || regs[27]!==0 || regs[46]!==8'h1e || regs[47]!==8'h1e)
            $fatal(1,"codec format/routing/gain mismatch");
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
