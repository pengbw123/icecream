// V2: 96 causal player/harmony features -> 32 clipped ReLU -> 17 logits.
// Four independent heads: articulation(3), degree(6), gate(4), dynamics(4).
module ai_bass_inference #(
    parameter WEIGHTS="src/generated/ai_bass/ai_bass_weights.mem",
    parameter BIASES="src/generated/ai_bass/ai_bass_biases.mem"
)(
    input wire clk,reset_n,feature_write,input wire [6:0] feature_index,
    input wire [7:0] feature_value,input wire start,
    output reg busy,done,output wire [2:0] action,
    output reg [1:0] articulation,gate_class,dynamic_class,output reg [2:0] degree,
    output reg [15:0] cycles,
    input wire [4:0] score_index,output wire signed [31:0] score
);
    reg signed [7:0] weights[0:3615] /* synthesis syn_ramstyle="block_ram" */;
    reg signed [31:0] biases[0:48];
    reg [7:0] features[0:95],hidden[0:31];
    reg signed [31:0] scores[0:16];
    initial begin $readmemh(WEIGHTS,weights);$readmemh(BIASES,biases);end
    assign score=score_index<17 ? scores[score_index]:32'sd0;
    assign action=articulation==2 ? degree+3'd2:articulation==1 ? 3'd1:3'd0;
    localparam IDLE=0,INIT=1,LOAD=2,MAC=3,FINISH=4;
    reg [2:0] state;reg layer;reg [5:0] neuron;reg [6:0] term;
    reg [11:0] address;
    reg signed [31:0] accumulator,best;
    reg signed [7:0] weight;reg [7:0] operand;
    wire signed [16:0] product=$signed({1'b0,operand})*$signed(weight);
    always @(posedge clk)begin
        if(!reset_n)begin
            state<=IDLE;busy<=0;done<=0;cycles<=0;articulation<=0;degree<=0;gate_class<=0;dynamic_class<=0;
            layer<=0;neuron<=0;term<=0;address<=0;accumulator<=0;best<=0;weight<=0;operand<=0;
        end else begin
            done<=0;
            if(feature_write&&!busy&&feature_index<96)features[feature_index]<=feature_value;
            if(busy)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin busy<=1;cycles<=0;layer<=0;neuron<=0;address<=0;state<=INIT;end
                INIT:begin accumulator<=biases[layer ? 32+neuron:neuron];term<=0;state<=LOAD;end
                LOAD:begin weight<=weights[address];operand<=layer ? hidden[term]:features[term];state<=MAC;end
                MAC:begin
                    accumulator<=accumulator+product;address<=address+1'b1;
                    if(term==(layer ? 31:95))state<=FINISH;else begin term<=term+1'b1;state<=LOAD;end
                end
                FINISH:begin
                    if(!layer)begin
                        hidden[neuron]<=accumulator<0 ? 0:accumulator>=4064 ? 127:accumulator[11:5];
                        if(neuron==31)begin layer<=1;neuron<=0;end else neuron<=neuron+1'b1;
                        state<=INIT;
                    end else begin
                        scores[neuron]<=accumulator;
                        if(neuron==0||neuron==3||neuron==9||neuron==13||accumulator>best)begin
                            best<=accumulator;
                            if(neuron<3)articulation<=neuron[1:0];
                            else if(neuron<9)degree<=neuron-3;
                            else if(neuron<13)gate_class<=neuron-9;
                            else dynamic_class<=neuron-13;
                        end
                        if(neuron==16)begin busy<=0;done<=1;state<=IDLE;end
                        else begin neuron<=neuron+1'b1;state<=INIT;end
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
