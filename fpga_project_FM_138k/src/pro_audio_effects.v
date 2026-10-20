// Post-mix mono effects. FM core remains untouched. Register 0 bit0 is
// exact dry bypass, bits1/2/3/4 enable chorus/reverb/filter/distortion.
// Biquad coefficients are signed Q4.28, computed in the UI using RBJ tables.
module pro_audio_effects(
    input wire clk,reset_n,sample_tick,input wire signed [15:0] dry_sample,
    input wire config_write,input wire [3:0] config_index,input wire [31:0] config_value,
    input wire [3:0] read_index,output wire [31:0] read_value,
    input wire [31:0] midi_event,input wire midi_valid,
    output wire signed [15:0] sample_out
);
    reg [31:0] cfg[0:15];integer i;
    assign read_value=cfg[read_index];
    reg filter_clear;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            for(i=0;i<16;i=i+1)cfg[i]<=0;
            cfg[0]<=1;cfg[3]<=2;cfg[5]<=64;cfg[6]<=127;cfg[7]<=32'h10000000;
            filter_clear<=1;
        end else begin
            filter_clear<=0;
            if(config_write)begin cfg[config_index]<=config_value;
                if(config_index>=7&&config_index<=11)filter_clear<=1;
            end
            if(midi_valid&&midi_event[23:20]==4'hB)begin
                if(midi_event[14:8]==21)begin cfg[1]<={25'd0,midi_event[6:0]};cfg[0][1]<=midi_event[6:0]!=0;cfg[0][0]<=0;end
                if(midi_event[14:8]==24)begin cfg[2]<={25'd0,midi_event[6:0]};cfg[0][2]<=midi_event[6:0]!=0;cfg[0][0]<=0;end
            end
        end
    end
    function signed [15:0] sat;
        input signed [63:0] v;
        begin sat=v>32767?16'sd32767:v< -32768?-16'sd32768:v[15:0];end
    endfunction
    function signed [15:0] blend;
        input signed [15:0] a,b;input [6:0] amount;
        reg signed [24:0] aa,bb;
        begin aa=a*$signed({1'b0,8'd128-{1'b0,amount}});bb=b*$signed({1'b0,amount});
            blend=amount==127?b:sat(($signed(aa)+$signed(bb))>>>7);end
    endfunction
    reg [4:0] state;
    reg signed [15:0] x,x1,x2,y1,y2,filtered,tone_sample;
    reg signed [31:0] c[0:4];
    reg signed [63:0] accumulator,product;
    reg signed [31:0] operand;
    reg [2:0] term;
    reg [6:0] filter_mix;
    reg filter_on,dist_on;
    reg signed [31:0] driven;
    reg signed [15:0] distortion;
    reg tone_tick;
    always @*begin
        case(term)0:operand={{16{x[15]}},x};1:operand={{16{x1[15]}},x1};
            2:operand={{16{x2[15]}},x2};3:operand=-$signed({{16{y1[15]}},y1});
            default:operand=-$signed({{16{y2[15]}},y2});endcase
    end
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            state<=0;x<=0;x1<=0;x2<=0;y1<=0;y2<=0;filtered<=0;tone_sample<=0;
            accumulator<=0;product<=0;term<=0;tone_tick<=0;driven<=0;distortion<=0;
            filter_mix<=127;filter_on<=0;dist_on<=0;
            for(i=0;i<5;i=i+1)c[i]<=0;
        end else begin
            tone_tick<=0;
            if(filter_clear)begin x1<=0;x2<=0;y1<=0;y2<=0;end
            case(state)
                0:if(sample_tick)begin
                    driven<=$signed(dry_sample)*$signed({1'b0,cfg[3][3:0]}+6'sd1);
                    x<=dry_sample;filter_on<=cfg[0][3];dist_on<=cfg[0][4];
                    filter_mix<=cfg[6][6:0];for(i=0;i<5;i=i+1)c[i]<=cfg[7+i];state<=1;
                end
                1:begin
                    case(cfg[4][1:0])
                        0:distortion<=driven>16384?sat(16384+((driven-16384)>>>2)):
                            driven< -16384?sat(-16384+((driven+16384)>>>2)):sat(driven);
                        1:distortion<=sat(driven);
                        default:distortion<={x[15:8],8'd0};
                    endcase
                    state<=2;
                end
                2:begin if(dist_on)x<=blend(x,distortion,cfg[5][6:0]);term<=0;accumulator<=0;state<=3;end
                3:begin product<=$signed(operand)*$signed(c[term]);state<=4;end
                4:begin accumulator<=accumulator+product;
                    if(term==4)state<=5;else begin term<=term+1'b1;state<=3;end
                end
                5:begin filtered<=sat(accumulator>>>28);state<=6;end
                6:begin
                    x2<=x1;x1<=x;y2<=y1;y1<=filtered;
                    tone_sample<=filter_on?blend(x,filtered,filter_mix):x;
                    tone_tick<=1;state<=0;
                end
                default:state<=0;
            endcase
        end
    end
    wire signed [15:0] room_sample;
    audio_effects u_room(.clk(clk),.reset_n(reset_n),.sample_tick(tone_tick),
        .dry_sample(tone_sample),.chorus_mix(cfg[0][1]?cfg[1][6:0]:7'd0),
        .reverb_mix(cfg[0][2]?cfg[2][6:0]:7'd0),.sample_out(room_sample));
    assign sample_out=cfg[0][0]?dry_sample:room_sample;
endmodule
