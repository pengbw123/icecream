// One held output slot plus round-robin arbitration. Never change a stalled
// event when a second input becomes valid; each accepted source advances once.
module midi_event_arbiter3 (
    input wire clk,reset_n,
    input wire [31:0] data0,data1,data2,
    input wire valid0,valid1,valid2,
    output wire ready0,ready1,ready2,
    output reg [31:0] event_data,
    output reg event_valid,
    input wire event_ready
);
    reg [1:0] cursor,selected;
    wire available=!event_valid || event_ready;
    always @* begin
        selected=3;
        case (cursor)
            0: if(valid0)selected=0;else if(valid1)selected=1;else if(valid2)selected=2;
            1: if(valid1)selected=1;else if(valid2)selected=2;else if(valid0)selected=0;
            default: if(valid2)selected=2;else if(valid0)selected=0;else if(valid1)selected=1;
        endcase
    end
    assign ready0=available && selected==0;
    assign ready1=available && selected==1;
    assign ready2=available && selected==2;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin cursor<=0;event_valid<=0;event_data<=0;end
        else if(available) begin
            event_valid<=selected!=3;
            case(selected)
                0:begin event_data<=data0;cursor<=1;end
                1:begin event_data<=data1;cursor<=2;end
                2:begin event_data<=data2;cursor<=0;end
                default:;
            endcase
        end
    end
endmodule
