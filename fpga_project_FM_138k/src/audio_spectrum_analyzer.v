// Visual spectrum, entirely in the 50 MHz RTL domain. 1024 contiguous real
// samples, periodic Hann, bit-reversed input, radix-2 DIT, /2 at every stage.
// Capture pauses for the ~1 ms transform; it never blocks the audio path.
// Output: 64 log bands; units are 1/8 octave (~0.753 dB), 0=-72 dBFS, 96=0 dBFS.
// dBFS uses Hann coherent-gain correction; DC is deliberately omitted.
module audio_spectrum_analyzer (
    input wire clk, reset_n, sample_tick,
    input wire signed [15:0] audio_sample,
    output reg bin_write,
    output reg [5:0] bin_address,
    output reg [13:0] bin_data
);
    localparam CAPTURE=0,DRAIN=1,FFT_INIT=2,SET_ADDR=3,READ_A=4,LATCH_A=5,
        READ_B=6,MULTIPLY=7,ROTATE=8,WRITE_A=9,WRITE_B=10,
        BAND_START=11,SCAN_WAIT=12,SCAN_BIN=13,LOG_LEVEL=14,EMIT=15;
    reg [3:0] state;
    reg signed [17:0] real_mem[0:1023], imag_mem[0:1023];
    reg signed [15:0] hann[0:1023];
    reg [31:0] twiddle[0:511];
    reg [19:0] bands[0:63];
    initial begin
        $readmemh("src/generated/spectrum_hann.mem",hann);
        $readmemh("src/generated/spectrum_twiddle.mem",twiddle);
        $readmemh("src/generated/spectrum_bands.mem",bands);
    end
    function [9:0] reverse_bits(input [9:0] v);
        integer n;begin for(n=0;n<10;n=n+1)reverse_bits[n]=v[9-n];end
    endfunction
    function signed [17:0] saturate(input signed [19:0] v);
        begin if(v>20'sd131071)saturate=18'sd131071;
        else if(v< -20'sd131072)saturate=-18'sd131072;else saturate=v[17:0];end
    endfunction
    function [6:0] to_level(input [18:0] mag);
        integer n,msb,log8,fraction;
        begin
            msb=0;for(n=0;n<19;n=n+1)if(mag[n])msb=n;
            fraction=(msb>=3)?((mag>>(msb-3))&7):((mag<<(3-msb))&7);
            log8=msb*8+fraction;
            // Full-scale sine -> |FFT|=32768 with x4 input headroom scaling.
            if(mag<8 || log8<=24)to_level=0;
            else if(log8>=120)to_level=96;
            else to_level=log8-24;
        end
    endfunction
    reg [9:0] capture_index, capture_address, read_address;
    reg capture_pending;
    reg signed [15:0] window_q;
    reg signed [31:0] window_product;
    reg signed [17:0] rq,iq,ar,ai;
    reg [3:0] stage;
    reg [9:0] group_base, offset;
    wire [10:0] half_size=11'd1<<stage;
    wire [9:0] address_a=group_base+offset;
    wire [9:0] address_b=address_a+half_size[9:0];
    wire [9:0] twiddle_address=offset<<(9-stage);
    reg signed [15:0] cos_q,sin_q;
    reg signed [33:0] rc,is_,ic,rs;
    wire signed [34:0] rot_r=$signed({rc[33],rc})+$signed({is_[33],is_});
    wire signed [34:0] rot_i=$signed({ic[33],ic})-$signed({rs[33],rs});
    reg signed [18:0] tr,ti;
    wire signed [19:0] sum_r=$signed(ar)+$signed(tr),sum_i=$signed(ai)+$signed(ti);
    wire signed [19:0] dif_r=$signed(ar)-$signed(tr),dif_i=$signed(ai)-$signed(ti);
    // One synchronous read and one write per RAM. No array clearing: all 1024
    // locations are overwritten before the first transform after reset.
    always @(posedge clk)begin
        window_q<=hann[capture_index];
        {cos_q,sin_q}<=twiddle[twiddle_address[8:0]];
        rq<=real_mem[read_address];iq<=imag_mem[read_address];
        if(reset_n)begin
            if(capture_pending)begin
                real_mem[capture_address]<=window_product>>>13;
                imag_mem[capture_address]<=0;
            end else if(state==WRITE_A)begin
                real_mem[address_a]<=saturate(sum_r>>>1);
                imag_mem[address_a]<=saturate(sum_i>>>1);
            end else if(state==WRITE_B)begin
                real_mem[address_b]<=saturate(dif_r>>>1);
                imag_mem[address_b]<=saturate(dif_i>>>1);
            end
        end
    end
    reg [5:0] band_index;
    reg [9:0] band_end;
    wire [17:0] abs_r=rq[17]?-rq:rq, abs_i=iq[17]?-iq:iq;
    // max + min/2 is a bounded visual magnitude approximation (~1 dB).
    wire [18:0] magnitude=abs_r>=abs_i?{1'b0,abs_r}+{2'b0,abs_i[17:1]}:
                                                   {1'b0,abs_i}+{2'b0,abs_r[17:1]};
    reg [18:0] band_max;
    reg [6:0] target;
    reg [6:0] smooth[0:63],peak[0:63];
    reg [3:0] hold_count[0:63];
    reg history_valid;
    reg [6:0] next_smooth,next_peak;
    reg [3:0] next_hold;
    always @*begin
        next_smooth=target;
        next_peak=target;next_hold=12;
        if(history_valid)begin
            if(smooth[band_index]>target)next_smooth=smooth[band_index]-1'b1;
            if(peak[band_index]>target)begin
                if(hold_count[band_index]!=0)begin next_peak=peak[band_index];next_hold=hold_count[band_index]-1'b1;end
                else begin next_peak=peak[band_index]-1'b1;next_hold=0;end
            end
        end
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=CAPTURE;capture_index<=0;capture_address<=0;capture_pending<=0;
            window_product<=0;read_address<=0;stage<=0;group_base<=0;offset<=0;
            ar<=0;ai<=0;rc<=0;is_<=0;ic<=0;rs<=0;tr<=0;ti<=0;
            band_index<=0;band_end<=0;band_max<=0;target<=0;history_valid<=0;
            bin_write<=0;bin_address<=0;bin_data<=0;
        end else begin
            bin_write<=0;capture_pending<=0;
            case(state)
                CAPTURE:if(sample_tick)begin
                    window_product<=$signed(audio_sample)*$signed(window_q);
                    capture_address<=reverse_bits(capture_index);capture_pending<=1;
                    if(capture_index==1023)begin capture_index<=0;state<=DRAIN;end
                    else capture_index<=capture_index+1'b1;
                end
                DRAIN:state<=FFT_INIT;
                FFT_INIT:begin stage<=0;group_base<=0;offset<=0;state<=SET_ADDR;end
                SET_ADDR:begin read_address<=address_a;state<=READ_A;end
                READ_A:state<=LATCH_A;
                LATCH_A:begin ar<=rq;ai<=iq;read_address<=address_b;state<=READ_B;end
                READ_B:state<=MULTIPLY;
                MULTIPLY:begin rc<=rq*cos_q;is_<=iq*sin_q;ic<=iq*cos_q;rs<=rq*sin_q;state<=ROTATE;end
                ROTATE:begin tr<=rot_r>>>15;ti<=rot_i>>>15;state<=WRITE_A;end
                WRITE_A:state<=WRITE_B;
                WRITE_B:begin
                    state<=SET_ADDR;
                    if({1'b0,offset}+1'b1==half_size)begin
                        offset<=0;
                        if({1'b0,group_base}+(half_size<<1)>=1024)begin
                            group_base<=0;
                            if(stage==9)begin band_index<=0;state<=BAND_START;end
                            else stage<=stage+1'b1;
                        end else group_base<=group_base+(half_size<<1);
                    end else offset<=offset+1'b1;
                end
                BAND_START:begin read_address<=bands[band_index][19:10];band_end<=bands[band_index][9:0];band_max<=0;state<=SCAN_WAIT;end
                SCAN_WAIT:state<=SCAN_BIN;
                SCAN_BIN:begin
                    if(magnitude>band_max)band_max<=magnitude;
                    if(read_address==band_end)state<=LOG_LEVEL;
                    else begin read_address<=read_address+1'b1;state<=SCAN_WAIT;end
                end
                LOG_LEVEL:begin target<=to_level(band_max);state<=EMIT;end
                EMIT:begin
                    smooth[band_index]<=next_smooth;peak[band_index]<=next_peak;hold_count[band_index]<=next_hold;
                    bin_write<=1;bin_address<=band_index;bin_data<={next_peak,next_smooth};
                    if(band_index==63)begin history_valid<=1;state<=CAPTURE;end
                    else begin band_index<=band_index+1'b1;state<=BAND_START;end
                end
                default:state<=CAPTURE;
            endcase
        end
    end
endmodule
