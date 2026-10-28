// 256 unsigned 7-bit pixels -> 24 clipped ReLU -> 3 signed logits.
// Single time-multiplexed 8x8 MAC. All ports are in ONE clock domain.
// Load all 256 features while !busy, then pulse start on a later cycle.
module gesture_mlp #(
    parameter WEIGHTS="src/generated/gesture/weights.mem",
    parameter BIASES="src/generated/gesture/biases.mem"
)(
    input wire clk,reset_n,feature_write,
    input wire [7:0] feature_index,
    input wire [6:0] feature_value,
    input wire start,
    output reg busy,done,
    output reg [1:0] class_id,
    output reg signed [31:0] score0,score1,score2,
    output reg [15:0] cycles
);
    reg signed [7:0] weights[0:6215] /* synthesis syn_ramstyle="block_ram" */;
    reg signed [31:0] biases[0:26];
    reg [6:0] features[0:255],hidden[0:23];
    initial begin $readmemh(WEIGHTS,weights);$readmemh(BIASES,biases);end
    localparam IDLE=0,INIT=1,LOAD=2,MAC=3,FINISH=4;
    reg [2:0] state;
    reg layer;
    reg [4:0] neuron;
    reg [7:0] term;
    reg [12:0] address;
    reg signed [31:0] accumulator,best;
    reg signed [7:0] weight;
    reg [6:0] operand;
    wire signed [15:0] product=$signed({1'b0,operand})*$signed(weight);
    always @(posedge clk) begin
        if(!reset_n) begin
            busy<=0;done<=0;cycles<=0;state<=IDLE;layer<=0;neuron<=0;
            term<=0;address<=0;accumulator<=0;best<=0;weight<=0;operand<=0;
            class_id<=0;score0<=0;score1<=0;score2<=0;
        end else begin
            done<=0;
            if(feature_write&&!busy) features[feature_index]<=feature_value;
            if(busy) cycles<=cycles+1'b1;
            case(state)
                IDLE: if(start) begin
                    busy<=1;cycles<=0;layer<=0;neuron<=0;address<=0;state<=INIT;
                end
                INIT: begin
                    accumulator<=biases[layer?24+neuron:neuron];term<=0;state<=LOAD;
                end
                LOAD: begin
                    weight<=weights[address];operand<=layer?hidden[term]:features[term];state<=MAC;
                end
                MAC: begin
                    accumulator<=accumulator+product;address<=address+1'b1;
                    if(term==(layer?23:255)) state<=FINISH;
                    else begin term<=term+1'b1;state<=LOAD;end
                end
                FINISH: begin
                    if(!layer) begin
                        hidden[neuron]<=accumulator<0?0:accumulator>=8128?127:accumulator[12:6];
                        if(neuron==23) begin layer<=1;neuron<=0;end
                        else neuron<=neuron+1'b1;
                        state<=INIT;
                    end else begin
                        if(neuron==0) begin score0<=accumulator;best<=accumulator;class_id<=0;end
                        if(neuron==1) score1<=accumulator;
                        if(neuron==2) score2<=accumulator;
                        if(neuron!=0&&accumulator>best) begin best<=accumulator;class_id<=neuron[1:0];end
                        if(neuron==2) begin busy<=0;done<=1;state<=IDLE;end
                        else begin neuron<=neuron+1'b1;state<=INIT;end
                    end
                end
                default: begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule
