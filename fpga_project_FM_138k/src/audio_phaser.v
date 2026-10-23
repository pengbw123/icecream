// Four first-order allpasses with a musical midrange sweep and dry/wet notches.
module audio_phaser (
    input wire clk, reset_n, sample_tick,
    input wire signed [15:0] in_sample,
    input wire enable,
    input wire [6:0] freq, depth, mix,
    output reg signed [15:0] out_sample
);
    function signed [15:0] sat16;
        input signed [47:0] v;
        begin
            if(v>32767) sat16=32767;
            else if(v< -32768) sat16=-32768;
            else sat16=v[15:0];
        end
    endfunction
    function signed [27:0] sat28;
        input signed [47:0] v;
        begin
            if(v>48'sd134217727) sat28=28'sd134217727;
            else if(v< -48'sd134217728) sat28=-28'sd134217728;
            else sat28=v[27:0];
        end
    endfunction
    reg [31:0] inc_tab[0:99];
    reg signed [15:0] mix_tab[0:99];
    reg signed [15:0] coeff_tab[0:255];
    initial begin
        $readmemh("src/generated/fx_phaser_inc.mem",inc_tab);
        $readmemh("src/generated/fx_level_gain.mem",mix_tab);
        $readmemh("src/generated/fx_phaser_coeff.mem",coeff_tab);
    end
    wire [6:0] freq_i=(freq>99)?7'd99:freq;
    wire [6:0] depth_i=(depth>99)?7'd99:depth;
    wire [6:0] mix_i=(mix>99)?7'd99:mix;
    reg [31:0] lfo_phase;
    wire [15:0] triangle=lfo_phase[31] ? ~lfo_phase[30:15]:lfo_phase[30:15];
    wire signed [16:0] centered=$signed({1'b0,triangle})-17'sd32768;
    wire signed [15:0] span=depth_i*16'd328;
    reg signed [16:0] centered_q;
    reg signed [15:0] span_q;
    reg signed [32:0] position_product;
    wire signed [32:0] position=33'sd32768+(position_product>>>15);
    reg [15:0] position_q;
    wire [7:0] lut_index=position_q[15:8];
    wire [7:0] lut_next=(lut_index==255)?8'd255:lut_index+1'b1;
    wire signed [16:0] coeff_delta=
        $signed({coeff_tab[lut_next][15],coeff_tab[lut_next]})-
        $signed({coeff_tab[lut_index][15],coeff_tab[lut_index]});
    reg signed [15:0] coeff_base_q;
    reg signed [16:0] coeff_delta_q;
    reg [7:0] coeff_frac_q;
    reg signed [25:0] interpolated_delta;
    wire signed [31:0] coeff_target=
        ($signed(coeff_base_q)<<<8)+interpolated_delta;
    // Q8 coefficient smoothing removes parameter zippering without deadband.
    reg signed [31:0] coefficient_q8;
    reg signed [15:0] a_q15,mix_q;
    reg enabled_q;
    reg [3:0] st;
    reg [1:0] stage;
    reg signed [15:0] in_q;
    // Q8 states plus four guard bits prevent integer allpass limit cycles
    // and intermediate clipping at normal signal levels.
    reg signed [27:0] cur,x1[0:3],y1[0:3];
    reg signed [47:0] prod1,prod2,mix_prod;
    wire signed [27:0] input_q8=$signed(in_q)*28'sd256;
    wire signed [27:0] y_new=sat28((prod1>>>15)+$signed(x1[stage])-(prod2>>>15));
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            lfo_phase<=0;st<=0;stage<=0;in_q<=0;cur<=0;
            a_q15<=0;mix_q<=0;enabled_q<=0;coefficient_q8<=-32'sd7630000;
            centered_q<=0;span_q<=0;position_product<=0;position_q<=0;
            coeff_base_q<=0;coeff_delta_q<=0;coeff_frac_q<=0;interpolated_delta<=0;
            prod1<=0;prod2<=0;mix_prod<=0;out_sample<=0;
            x1[0]<=0;x1[1]<=0;x1[2]<=0;x1[3]<=0;
            y1[0]<=0;y1[1]<=0;y1[2]<=0;y1[3]<=0;
        end else case(st)
            0: if(sample_tick) begin
                in_q<=in_sample;cur<=$signed(in_sample)*28'sd256;
                lfo_phase<=lfo_phase+inc_tab[freq_i];
                centered_q<=centered;span_q<=span;
                mix_q<=$signed({1'b0,mix_tab[mix_i][15:1]});
                enabled_q<=enable;stage<=0;st<=7;
            end
            // Pipeline modulation, ROM lookup and interpolation. Chaining
            // all three multiplications/lookups into one clock missed 50 MHz.
            7: begin position_product<=centered_q*span_q;st<=8;end
            8: begin position_q<=position[15:0];st<=9;end
            9: begin
                coeff_base_q<=coeff_tab[lut_index];coeff_delta_q<=coeff_delta;
                coeff_frac_q<=position_q[7:0];st<=10;
            end
           10: begin interpolated_delta<=coeff_delta_q*$signed({1'b0,coeff_frac_q});st<=11;end
           11: begin
                coefficient_q8<=coefficient_q8+((coeff_target-coefficient_q8)>>>6);
                st<=1;
            end
            1: begin a_q15<=coefficient_q8>>>8;st<=2;end
            2: begin prod1<=$signed(a_q15)*$signed(cur);st<=3;end
            3: begin prod2<=$signed(a_q15)*$signed(y1[stage]);st<=4;end
            4: begin
                x1[stage]<=cur;y1[stage]<=y_new;cur<=y_new;
                if(stage==3) st<=5;
                else begin stage<=stage+1'b1;st<=2;end
            end
            5: begin
                // MIX=99 is 50% dry + 50% allpass: maximum notch depth.
                mix_prod<=($signed({cur[27],cur})-$signed({input_q8[27],input_q8}))*mix_q;
                st<=6;
            end
            default: begin
                out_sample<=enabled_q ? sat16(($signed(input_q8)+(mix_prod>>>15))>>>8):in_q;
                st<=0;
            end
        endcase
    end
endmodule
