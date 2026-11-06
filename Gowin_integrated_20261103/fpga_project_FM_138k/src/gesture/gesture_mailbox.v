// One 256x7 feature bank, held unchanged from publish until inference finishes.
// Two-flop toggle handshake; payload and energy are stable BEFORE the request
// is observed. Dual-clock memory is the CDC payload, never a combinational bus.
// All reset users must share reset_n; each clock synchronously releases it.
module gesture_mailbox(
    input wire source_clk,clk,reset_n,
    input wire source_write,input wire [7:0] source_index,
    input wire [6:0] source_value,input wire source_publish,
    input wire [14:0] source_energy,output wire source_busy,
    output reg feature_write,output reg [7:0] feature_index,
    output reg [6:0] feature_value,output reg start,
    output reg [14:0] feature_energy,
    input wire inference_done
);
    reg [6:0] memory[0:255] /* synthesis syn_ramstyle="distributed_ram" */;
    reg request,ack;
    reg [14:0] held_energy;
    reg [1:0] ack_sync,request_sync;
    reg [2:0] source_reset,main_reset;
    always @(posedge source_clk or negedge reset_n)
        if(!reset_n)source_reset<=0;else source_reset<={source_reset[1:0],1'b1};
    always @(posedge clk or negedge reset_n)
        if(!reset_n)main_reset<=0;else main_reset<={main_reset[1:0],1'b1};
    assign source_busy=!source_reset[2]||(request!=ack_sync[1]);
    always @(posedge source_clk)begin
        if(source_reset[2]&&source_write&&!source_busy)memory[source_index]<=source_value;
    end
    always @(posedge source_clk or negedge reset_n)begin
        if(!reset_n)begin request<=0;ack_sync<=0;held_energy<=0;end
        else if(!source_reset[2])begin request<=0;ack_sync<=0;held_energy<=0;end
        else begin
            ack_sync<={ack_sync[0],ack};
            if(source_publish&&!source_busy)begin request<=!request;held_energy<=source_energy;end
        end
    end
    localparam IDLE=0,READ=1,SEND=2,START=3,WAIT=4;
    reg [2:0] state;
    reg [7:0] index;
    reg [6:0] q;
    always @(posedge clk) q<=memory[index];
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            ack<=0;request_sync<=0;state<=IDLE;index<=0;
            feature_write<=0;feature_index<=0;feature_value<=0;start<=0;feature_energy<=0;
        end else if(!main_reset[2])begin
            ack<=0;request_sync<=0;state<=IDLE;index<=0;
            feature_write<=0;feature_index<=0;feature_value<=0;start<=0;feature_energy<=0;
        end else begin
            request_sync<={request_sync[0],request};feature_write<=0;start<=0;
            case(state)
                IDLE: if(request_sync[1]!=ack)begin
                    index<=0;feature_energy<=held_energy;state<=READ;
                end
                READ: state<=SEND;
                SEND: begin
                    feature_write<=1;feature_index<=index;feature_value<=q;
                    if(index==255)state<=START;
                    else begin index<=index+1'b1;state<=READ;end
                end
                START: begin start<=1;state<=WAIT;end
                WAIT: if(inference_done)begin ack<=request_sync[1];state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
