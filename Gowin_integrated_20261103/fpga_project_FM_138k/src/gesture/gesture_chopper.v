// 120 BPM sixteenth-note amplitude gate, 50% duty, 128-sample (~2.62 ms)
// linear attack/release at 48.828 kHz. Shift-add gain avoids another DSP.
module gesture_chopper #(parameter integer HALF_PERIOD=3052)(
    input wire clk,reset_n,sample_tick,enable,bypass,
    input wire signed [15:0] sample_in,
    output wire signed [15:0] sample_out,output wire gate_open
);
    reg [15:0] phase;
    reg gate;
    reg [7:0] gain;
    wire target=!enable||gate;
    wire signed [24:0] extended={{9{sample_in[15]}},sample_in};
    wire signed [24:0] a=(gain[0]?extended:25'sd0)+(gain[1]?(extended<<<1):25'sd0);
    wire signed [24:0] b=(gain[2]?(extended<<<2):25'sd0)+(gain[3]?(extended<<<3):25'sd0);
    wire signed [24:0] c=(gain[4]?(extended<<<4):25'sd0)+(gain[5]?(extended<<<5):25'sd0);
    wire signed [24:0] d=(gain[6]?(extended<<<6):25'sd0)+(gain[7]?(extended<<<7):25'sd0);
    wire signed [24:0] ab=a+b,cd=c+d;
    // Separate the gain tree from the downstream absolute-value/peak paths.
    // Two system clocks, not two audio samples; test bypass remains exact.
    reg signed [24:0] ab_pipe,cd_pipe,scaled;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin ab_pipe<=0;cd_pipe<=0;scaled<=0;end
        else begin ab_pipe<=ab;cd_pipe<=cd;scaled<=ab_pipe+cd_pipe;end
    end
    assign sample_out=bypass?sample_in:scaled[22:7];
    assign gate_open=gate;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin phase<=0;gate<=1;gain<=128;end
        else if(sample_tick)begin
            if(bypass||!enable)begin phase<=0;gate<=1;end
            else if(phase==HALF_PERIOD-1)begin phase<=0;gate<=!gate;end
            else phase<=phase+1'b1;
            if(bypass)gain<=128;
            else if(target&&gain<128)gain<=gain+1'b1;
            else if(!target&&gain!=0)gain<=gain-1'b1;
        end
    end
endmodule
