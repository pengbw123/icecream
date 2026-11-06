// ACG720 headphone output. The existing final I2S stream already contains
// master volume; the codec's digital and analogue gains stay at 0 dB.
// 50 MHz / 4 = 12.5 MHz MCLK = 256 * 48.828125 kHz LRCK.
module es8388_output #(
    parameter integer I2C_QUARTER_CLOCKS = 125,
    parameter integer POWERUP_CLOCKS = 500000,
    parameter integer SETTLE_CLOCKS = 25000000,
    parameter integer RETRY_CLOCKS = 1000000
) (
    input wire clk, reset_n,
    input wire i2s_bclk, i2s_lrclk, i2s_data,
    output wire aud_mclk, aud_bclk, aud_lrclk, aud_dacdat,
    inout wire codec_scl, codec_sda,
    output reg ready,
    output reg init_error
);
    reg [1:0] mclk_div;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) mclk_div <= 0;
        else mclk_div <= mclk_div + 1'b1;
    assign aud_mclk = mclk_div[1];
    // ES8388 powers up in master mode. Release these pins until its slave
    // mode write has ACKed, avoiding two clock drivers during power-up/reset.
    reg clocks_enabled;
    assign aud_bclk = clocks_enabled ? i2s_bclk : 1'bz;
    assign aud_lrclk = clocks_enabled ? i2s_lrclk : 1'bz;
    assign aud_dacdat = i2s_data;

    // Derived from the board's ch35 sequence and ES8388 rev5 register map.
    // Slave I2S, 16 data bits in 32-bit slots, shared LRCK, DAC-only routing.
    // Keep mute/output attenuation until reference and DAC bias have settled.
    function [15:0] setting;
        input [5:0] n;
        begin
            case(n)
                0: setting=16'h0080; // reset configuration registers
                1: setting=16'h0006;
                2: setting=16'h0150; // analogue bias/reference on
                3: setting=16'h02F3; // hold digital converters in reset
                4: setting=16'h1926; // DAC soft ramp, mute
                5: setting=16'h04C0; // DAC/output drivers off during setup
                6: setting=16'h0036; // common Fs, DAC master-clock source
                7: setting=16'h03FF; // ADC and microphone path off
                8: setting=16'h0800; // codec SLAVE: FPGA drives BCLK/LRCK
                9: setting=16'h0D02; // 256 Fs
               10: setting=16'h1718; // standard I2S, 16-bit samples
               11: setting=16'h1802; // single-speed, 256 Fs
               12: setting=16'h0500;
               13: setting=16'h0600;
               14: setting=16'h1A00; // left digital gain 0 dB
               15: setting=16'h1B00; // right digital gain 0 dB
               16: setting=16'h1C08; // no de-emphasis, click-free power
               17: setting=16'h1D00; // no stereo enhancement
               18: setting=16'h2600;
               19: setting=16'h27B8; // left DAC only, analogue bypass off
               20: setting=16'h2AB8; // right DAC only, analogue bypass off
               21: setting=16'h2B80; // ADC/DAC share external LRCK
               22: setting=16'h2D00;
               23: setting=16'h2E00; // OUT1 initially -45 dB
               24: setting=16'h2F00;
               25: setting=16'h0200; // release converter clocks/reset
               26: setting=16'h0430; // power DAC and OUT1, OUT2 stays off
               27: setting=16'h2E1E; // fixed left OUT1 gain 0 dB
               28: setting=16'h2F1E; // fixed right OUT1 gain 0 dB
               29: setting=16'h1922; // unmute only after all writes ACK
              default: setting=16'h1926;
            endcase
        end
    endfunction
    reg start;
    wire done, failed;
    reg [5:0] index;
    wire [15:0] reg_setting=setting(index);
    es8388_i2c_write #(.QUARTER_CLOCKS(I2C_QUARTER_CLOCKS)) u_i2c (
        .clk(clk),.reset_n(reset_n),.start(start),
        .reg_addr(reg_setting[15:8]),.reg_data(reg_setting[7:0]),
        .scl(codec_scl),.sda(codec_sda),.done(done),.failed(failed)
    );
    reg [2:0] state;
    reg [25:0] wait_count;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=0; wait_count<=POWERUP_CLOCKS-1;
            index<=0; start<=0; ready<=0; init_error<=0; clocks_enabled<=0;
        end else begin
            start<=0;
            case(state)
                0: if (wait_count!=0) wait_count<=wait_count-1'b1;
                   else state<=1;
                1: begin start<=1; state<=2; end
                2: if(done) begin
                    if(failed) begin
                        init_error<=1; index<=0; clocks_enabled<=0;
                        wait_count<=RETRY_CLOCKS-1; state<=0;
                    end else if(index==29) begin
                        ready<=1; init_error<=0; state<=4;
                    end else begin
                        if(index==8) clocks_enabled<=1;
                        index<=index+1'b1;
                        if(index==25) begin
                            wait_count<=SETTLE_CLOCKS-1; state<=3;
                        end else state<=1;
                    end
                end
                3: if(wait_count!=0) wait_count<=wait_count-1'b1;
                   else state<=1;
                default: state<=4;
            endcase
        end
    end
endmodule

// Open-drain 100 kHz register writer, address 0x10 (board CE/AD0=0).
// ACK is checked for all three bytes. Stuck bus/clock stretching is bounded;
// the caller retries the complete muted power-up sequence after a failure.
module es8388_i2c_write #(
    parameter integer QUARTER_CLOCKS=125,
    parameter integer TIMEOUT_QUARTERS=4000
) (
    input wire clk, reset_n, start,
    input wire [7:0] reg_addr,reg_data,
    inout wire scl,sda,
    output reg done,failed
);
    reg scl_low,sda_low;
    assign scl=scl_low ? 1'b0:1'bz;
    assign sda=sda_low ? 1'b0:1'bz;
    reg [1:0] scl_sync,sda_sync;
    always @(posedge clk or negedge reset_n)
        if(!reset_n) begin scl_sync<=3; sda_sync<=3; end
        else begin scl_sync<={scl_sync[0],scl}; sda_sync<={sda_sync[0],sda}; end
    reg [15:0] divider;
    reg [15:0] timeout_count;
    reg [3:0] state;
    reg [1:0] phase,byte_index;
    reg [3:0] bit_index, recovery_pulses;
    reg recovering;
    reg [23:0] payload;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            scl_low<=0; sda_low<=0; done<=0; failed<=0;
            divider<=0; state<=0; phase<=0; byte_index<=0;
            bit_index<=0; payload<=0; timeout_count<=0;
            recovering<=0; recovery_pulses<=0;
        end else begin
            done<=0;
            if(state==0) begin
                divider<=0;
                if(start) begin
                    payload<={8'h20,reg_addr,reg_data};
                    failed<=0; state<=1; timeout_count<=0; recovering<=0;
                end
            end else if(divider==QUARTER_CLOCKS-1) begin
                divider<=0;
                // A slow or absent pull-up must not hang the audio system.
                if(timeout_count==TIMEOUT_QUARTERS-1) begin
                    scl_low<=0; sda_low<=0; failed<=1; done<=1; state<=0;
                end else begin
                    timeout_count<=timeout_count+1'b1;
                    case(state)
                        1: if(scl_sync[1]) begin
                            if(sda_sync[1]) begin
                                sda_low<=1; timeout_count<=0; state<=2;
                            end else begin
                                // S4 can interrupt a byte while the codec
                                // holds SDA low. Clock it out before START.
                                recovering<=1; recovery_pulses<=0; state<=8;
                            end
                        end
                        2: begin scl_low<=1; bit_index<=0; byte_index<=0;
                                 phase<=0; state<=3; end
                        3: case(phase)
                            0: begin
                                scl_low<=1;
                                sda_low<=(bit_index<8) ? ~payload[23]:1'b0;
                                phase<=1;
                            end
                            1: begin scl_low<=0; phase<=2; end
                            2: if(scl_sync[1]) begin
                                timeout_count<=0;
                                if(bit_index==8 && sda_sync[1]) failed<=1;
                                phase<=3;
                            end
                            3: begin
                                scl_low<=1; phase<=0;
                                if(bit_index==8) begin
                                    bit_index<=0;
                                    if(failed || byte_index==2) state<=4;
                                    else byte_index<=byte_index+1'b1;
                                end else begin
                                    payload<={payload[22:0],1'b0};
                                    bit_index<=bit_index+1'b1;
                                end
                            end
                        endcase
                        4: begin scl_low<=1; sda_low<=1; state<=5; end
                        5: begin scl_low<=0; state<=6; end
                        6: if(scl_sync[1]) begin sda_low<=0; state<=7; end
                        7: if(recovering) begin
                            recovering<=0; timeout_count<=0;
                            if(sda_sync[1] && scl_sync[1]) state<=1;
                            else begin failed<=1; done<=1; state<=0; end
                        end else begin done<=1; state<=0; end
                        8: begin scl_low<=1; sda_low<=0; state<=9; end
                        9: begin scl_low<=0; state<=10; end
                       10: if(scl_sync[1]) begin
                            timeout_count<=0;
                            if(sda_sync[1] || recovery_pulses==8) state<=4;
                            else begin recovery_pulses<=recovery_pulses+1'b1; state<=8; end
                        end
                        default: state<=0;
                    endcase
                end
            end else divider<=divider+1'b1;
        end
    end
endmodule
