// 128 causal melody/seed/control features -> 48 clipped ReLU -> 36 logits.
// Heads: REST/HOLD/ATTACK, chromatic interval -12..12, gate, dynamics.
module ai_melody_inference #(
    parameter WEIGHTS="src/generated/ai_composer/weights.mem",
    parameter BIASES="src/generated/ai_composer/biases.mem"
)(
    input wire clk,reset_n,feature_write,input wire [6:0] feature_index,
    input wire [7:0] feature_value,input wire start,
    output reg busy,done,output reg [1:0] articulation,gate_class,dynamic_class,
    output reg [4:0] interval_class,interval_alt,output reg [15:0] cycles,
    input wire [5:0] score_index,output wire signed [31:0] score
);
    reg signed [7:0] weights[0:7871] /* synthesis syn_ramstyle="block_ram" */;
    reg signed [31:0] biases[0:83];
    reg [7:0] features[0:127],hidden[0:47];
    reg signed [31:0] scores[0:35];
    initial begin $readmemh(WEIGHTS,weights);$readmemh(BIASES,biases);end
    assign score=score_index<36 ? scores[score_index] : 32'sd0;
    localparam IDLE=0,INIT=1,LOAD=2,MAC=3,FINISH=4;
    reg [2:0] state;reg layer;reg [5:0] neuron;reg [6:0] term;
    reg [12:0] address;reg signed [31:0] accumulator,best,second_best;
    reg signed [7:0] weight;reg [7:0] operand;
    wire signed [16:0] product=$signed({1'b0,operand})*$signed(weight);
    always @(posedge clk)begin
        if(!reset_n)begin
            state<=IDLE;busy<=0;done<=0;cycles<=0;articulation<=0;gate_class<=0;dynamic_class<=0;
            interval_class<=12;interval_alt<=13;layer<=0;neuron<=0;term<=0;address<=0;
            accumulator<=0;best<=0;second_best<=0;weight<=0;operand<=0;
        end else begin
            done<=0;
            if(feature_write&&!busy)features[feature_index]<=feature_value;
            if(busy)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin busy<=1;cycles<=0;layer<=0;neuron<=0;address<=0;state<=INIT;end
                INIT:begin accumulator<=biases[layer ? 48+neuron : neuron];term<=0;state<=LOAD;end
                LOAD:begin weight<=weights[address];operand<=layer ? hidden[term] : features[term];state<=MAC;end
                MAC:begin
                    accumulator<=accumulator+product;address<=address+1'b1;
                    if(term==(layer ? 47 : 127))state<=FINISH;
                    else begin term<=term+1'b1;state<=LOAD;end
                end
                FINISH:begin
                    if(!layer)begin
                        hidden[neuron]<=accumulator<0 ? 0 : accumulator>=4064 ? 127 : accumulator[11:5];
                        if(neuron==47)begin layer<=1;neuron<=0;end else neuron<=neuron+1'b1;
                        state<=INIT;
                    end else begin
                        scores[neuron]<=accumulator;
                        if(neuron==3)begin interval_class<=0;best<=accumulator;second_best<=-32'sd2147483647;interval_alt<=1;end
                        else if(neuron>3&&neuron<28)begin
                            if(accumulator>best)begin second_best<=best;interval_alt<=interval_class;best<=accumulator;interval_class<=neuron-3;end
                            else if(neuron==4||accumulator>second_best)begin second_best<=accumulator;interval_alt<=neuron-3;end
                        end else if(neuron==0||neuron==28||neuron==32||accumulator>best)begin
                            best<=accumulator;
                            if(neuron<3)articulation<=neuron[1:0];
                            else if(neuron<32)gate_class<=neuron-28;
                            else dynamic_class<=neuron-32;
                        end
                        if(neuron==35)begin busy<=0;done<=1;state<=IDLE;end
                        else begin neuron<=neuron+1'b1;state<=INIT;end
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
