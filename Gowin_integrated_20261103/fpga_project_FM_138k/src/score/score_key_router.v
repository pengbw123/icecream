// Translate only real CH376 key events. A held key owns the pitch and a
// physical-key tag captured at press time until its matching release.
// On disconnect, queued note-offs release exactly the tagged USB voices.
module score_key_router(
    input wire clk,reset_n,
    input wire enabled,input wire [6:0] first_key,
    input wire [24:0] target_valid,input wire [174:0] target_notes,
    input wire disconnect,
    input wire [31:0] in_data,input wire in_valid,output wire in_ready,
    output reg [31:0] out_data,output reg out_valid,input wire out_ready,
    output wire busy
);
    reg [24:0] held;
    reg [6:0] held_pitch[0:24];
    reg [6:0] bound_first;
    reg was_enabled,flushing;
    reg [5:0] flush_index;
    wire slot_free=!out_valid || out_ready;
    assign in_ready=slot_free && !flushing && !disconnect;
    assign busy=flushing || (|held);
    wire [6:0] base=enabled ? first_key : bound_first;
    wire [6:0] raw_note=in_data[14:8];
    wire in_range=!in_data[15] && {1'b0,raw_note}>={1'b0,base} &&
                  {1'b0,raw_note}<({1'b0,base}+8'd25);
    wire [4:0] key_index=raw_note-base;
    wire note_on=in_data[23:20]==4'h9 && in_data[6:0]!=0;
    wire note_off=in_data[23:20]==4'h8 || (in_data[23:20]==4'h9 && in_data[6:0]==0);
    wire all_off=in_data[23:20]==4'hb && (raw_note==7'd120 || raw_note==7'd123);
    integer i;
    reg [4:0] tag;
    reg [6:0] pitch;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            held<=0;bound_first<=0;was_enabled<=0;flushing<=0;flush_index<=0;
            out_valid<=0;out_data<=0;
            for(i=0;i<25;i=i+1)held_pitch[i]<=0;
        end else begin
            was_enabled<=enabled;
            if(enabled&&!was_enabled)bound_first<=first_key;
            if(out_valid&&out_ready)out_valid<=0;
            if(disconnect)begin flushing<=1;flush_index<=0;end
            else if(flushing&&slot_free)begin
                if(flush_index>=25)begin flushing<=0;flush_index<=0;end
                else begin
                    if(held[flush_index])begin
                        tag=flush_index[4:0];
                        out_data<={{2'b00,1'b1,1'b0,tag[3:0]},7'h40,tag[4],{1'b0,held_pitch[flush_index]},8'd0};
                        out_valid<=1;held[flush_index]<=0;
                    end
                    flush_index<=flush_index+1'b1;
                end
            end else if(in_valid&&in_ready)begin
                out_data<=in_data;out_valid<=1;
                if(all_off)held<=0;
                else if(in_range&&note_on&&(enabled||held[key_index]))begin
                    if(held[key_index])out_valid<=0; // repeated Note On without release
                    else begin
                        pitch=target_valid[key_index] ? target_notes[key_index*7 +: 7] : raw_note;
                        tag=key_index;
                        out_data[31:24]<={2'b00,1'b1,1'b0,tag[3:0]};
                        out_data[16]<=tag[4];
                        out_data[15:8]<={1'b0,pitch};
                        held[key_index]<=1;held_pitch[key_index]<=pitch;
                    end
                end else if(in_range&&note_off&&held[key_index])begin
                    tag=key_index;
                    out_data[31:24]<={2'b00,1'b1,1'b0,tag[3:0]};
                    out_data[16]<=tag[4];
                    out_data[15:8]<={1'b0,held_pitch[key_index]};
                    held[key_index]<=0;
                end else if(enabled&&in_range&&note_off)begin
                    // Ignore an orphan off: it has no mapped voice to release.
                    out_valid<=0;
                end
            end
        end
    end
endmodule
