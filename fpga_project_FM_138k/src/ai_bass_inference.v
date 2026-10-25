// Trained INT8 inference, 48 causal MIDI features -> 32 ReLU -> 8 actions.
// Single serialized MAC, synchronous weight ROM, deterministic bounded work.
// Feature writes while busy are rejected; caller owns snapshot scheduling.
module ai_bass_inference #(
    parameter WEIGHTS="src/generated/ai_bass/ai_bass_weights.mem",
    parameter BIASES="src/generated/ai_bass/ai_bass_biases.mem"
)(
    input wire clk,reset_n,
    input wire feature_write,input wire [5:0] feature_index,
    input wire [7:0] feature_value,input wire start,
    output reg busy,done,output reg [2:0] action,
    output reg [15:0] cycles,
    input wire [2:0] score_index,output wire signed [31:0] score
);
    reg signed [7:0] weights[0:1791] /* synthesis syn_ramstyle = "block_ram" */;
    reg signed [31:0] biases[0:39];
    reg [7:0] features[0:47],hidden[0:31];
    reg signed [31:0] scores[0:7];
    initial begin $readmemh(WEIGHTS,weights);$readmemh(BIASES,biases);end
    assign score=scores[score_index];
    localparam IDLE=0,INIT=1,LOAD=2,MAC=3,FINISH=4;
    reg [2:0] state;
    reg layer;
    reg [5:0] neuron,term;
    reg [10:0] address;
    reg signed [31:0] accumulator,best;
    reg signed [7:0] weight;
    reg [7:0] operand;
    wire signed [16:0] product=$signed({1'b0,operand})*$signed(weight);
    always @(posedge clk)begin
        if(!reset_n)begin
            state<=IDLE;busy<=0;done<=0;action<=0;cycles<=0;
            layer<=0;neuron<=0;term<=0;address<=0;accumulator<=0;best<=0;
        end else begin
            done<=0;
            if(feature_write&&!busy&&feature_index<48)features[feature_index]<=feature_value;
            if(busy)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin busy<=1;cycles<=0;layer<=0;neuron<=0;address<=0;state<=INIT;end
                INIT:begin accumulator<=biases[layer?32+neuron:neuron];term<=0;state<=LOAD;end
                LOAD:begin
                    weight<=weights[address];operand<=layer?hidden[term]:features[term];
                    state<=MAC;
                end
                MAC:begin
                    accumulator<=accumulator+product;address<=address+1'b1;
                    if(term==(layer?31:47))state<=FINISH;
                    else begin term<=term+1'b1;state<=LOAD;end
                end
                FINISH:begin
                    if(!layer)begin
                        hidden[neuron]<=accumulator<0?0:accumulator>=4064?127:accumulator[11:5];
                        if(neuron==31)begin layer<=1;neuron<=0;end
                        else neuron<=neuron+1'b1;
                        state<=INIT;
                    end else begin
                        scores[neuron]<=accumulator;
                        if(neuron==0||accumulator>best)begin best<=accumulator;action<=neuron[2:0];end
                        if(neuron==7)begin busy<=0;done<=1;state<=IDLE;end
                        else begin neuron<=neuron+1'b1;state<=INIT;end
                    end
                end
            endcase
        end
    end
endmodule
