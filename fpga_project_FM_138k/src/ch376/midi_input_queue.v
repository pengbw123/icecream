// Two register slots isolate upstream ready from the ARP/voice-control path.
// Full + pop intentionally accepts new input on the following clock; no
// combinational out_ready -> in_ready path, no BRAM and no event drops.
module midi_input_queue(
    input wire clk,reset_n,
    input wire [31:0] in_data,input wire in_valid,output wire in_ready,
    output wire [31:0] out_data,output wire out_valid,input wire out_ready
);
    reg [31:0] slot0,slot1;
    reg read_pointer,write_pointer;
    reg [1:0] count;
    assign in_ready=count!=2;
    assign out_valid=count!=0;
    assign out_data=read_pointer?slot1:slot0;
    wire push=in_valid&&in_ready,pop=out_valid&&out_ready;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin slot0<=0;slot1<=0;read_pointer<=0;write_pointer<=0;count<=0;end
        else begin
            if(push)begin
                if(write_pointer)slot1<=in_data;else slot0<=in_data;
                write_pointer<=!write_pointer;
            end
            if(pop)read_pointer<=!read_pointer;
            case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
        end
    end
endmodule
