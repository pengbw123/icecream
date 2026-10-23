// Prevent one demo/human owner from releasing a note held by the other.
// This is a ready/valid filter: suppressed events are still acknowledged and
// reported to the practice engine. Untagged MIDI retains normal retriggering.
module midi_note_owners(
    input wire clk,reset_n,
    input wire [31:0] data,input wire valid,input wire ready,
    output wire forward
);
    reg [127:0] human,demo;
    reg mono;
    wire [6:0] note=data[14:8];
    wire on_event=data[23:20]==4'h9&&data[6:0]!=0;
    wire off_event=data[23:20]==4'h8||(data[23:20]==4'h9&&data[6:0]==0);
    wire other=data[31]?human[note]:demo[note];
    assign forward=!((on_event||off_event)&&other);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin human<=0;demo<=0;mono<=0;end
        else if(valid&&ready)begin
            if(on_event||off_event)begin
                if(data[31])demo[note]<=on_event;else human[note]<=on_event;
            end else if(data[23:20]==4'hb&&(data[14:8]==120||data[14:8]==123))begin
                human<=0;demo<=0;
            end else if(data[23:20]==4'hb&&data[14:8]==22)begin
                // The FM allocator clears its voices on a mono/poly change.
                // Clear our matching bookkeeping at the same accepted event.
                mono<=data[6:0]!=0;
                if(mono!=(data[6:0]!=0))begin human<=0;demo<=0;end
            end
        end
    end
endmodule
