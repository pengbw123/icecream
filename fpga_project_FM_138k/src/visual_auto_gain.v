// Display-only range selection. No signal from this module feeds the audio
// mixer, effects, I2S, clip detector or true-level meter. Powers of two avoid DSPs.
module visual_auto_gain (
    input wire clk,reset_n,sample_tick,enabled,
    input wire signed [15:0] sample,
    output reg [3:0] gain_shift
);
    reg [15:0] peak;
    reg [5:0] release_div;
    wire [15:0] magnitude=sample[15] ? (~sample+16'd1) : sample;
    // Once per 64 audio samples: ~41 ms exponential release at 48.8 kHz.
    // Attack is immediate; minimum one-LSB decrement guarantees convergence.
    wire [15:0] decrement=(peak>>5)+16'd1;
    wire [15:0] released_peak=peak>decrement?peak-decrement:16'd0;
    integer k;
    always @* begin
        gain_shift=0;
        if(enabled)
            for(k=0;k<8;k=k+1)
                if(peak<(16'd8192>>k))gain_shift=k+1;
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin peak<=16'd32768;release_div<=0;end
        else if(sample_tick)begin
            release_div<=release_div+1'b1;
            if(magnitude>=peak)peak<=magnitude;
            else if(release_div==0)
                peak<=magnitude>released_peak?magnitude:released_peak;
        end
    end
endmodule
