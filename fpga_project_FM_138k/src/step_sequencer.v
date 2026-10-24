// Eight volatile 16-step patterns. NOTE=bit31, TIE=bit30, otherwise REST.
// Notes use velocity[14:8], pitch[6:0]. Internal MIDI bit31 is the demo owner.
module step_sequencer #(
    parameter integer CLOCKS_PER_US=50
)(
    input wire clk,reset_n,suspend,
    input wire control_write,input wire [31:0] control_data,
    input wire [127:0] timing_data,
    input wire address_write,input wire [6:0] address_data,input wire [6:0] read_address,
    input wire step_write,input wire [31:0] step_data,input wire clear_pattern,
    output reg [6:0] edit_address,output reg [31:0] edit_data,
    input wire [31:0] human_event,input wire human_valid,
    output reg [31:0] midi_data,output reg midi_valid,input wire midi_ready,
    output wire [31:0] status
);
    localparam IDLE=0,READ0=1,READ1=2,LOAD=3;
    reg [31:0] steps[0:127];
    reg [31:0] current_word,next_word;
    reg [2:0] pattern,requested_pattern;
    reg [4:0] length,requested_length;
    reg [3:0] position;
    wire [3:0] next_position={1'b0,position}+1'b1>=length?4'd0:position+1'b1;
    always @(posedge clk)begin
        edit_data<=steps[read_address];
        current_word<=steps[{pattern,position}];
        next_word<=steps[{pattern,next_position}];
    end
    reg running,recording,active,first_step,restart_seen,reset_pending;
    reg initializing,clearing,error;
    reg [6:0] write_index;
    reg [3:0] clear_index;
    reg [2:0] clear_bank;
    reg [2:0] state;
    reg [6:0] active_note;
    reg [5:0] us_div;
    reg [31:0] step_left,gate_left;
    reg [31:0] step_length,gate_length;
    reg gate_enabled,odd;
    reg [127:0] timing;
    wire us_tick=us_div==CLOCKS_PER_US-1;
    wire busy=initializing||clearing;
    wire record_hit=human_valid&&!human_event[31]&&human_event[23:20]==4'h9&&human_event[6:0]!=0;
    wire [31:0] step_time=odd?timing[63:32]:timing[31:0];
    wire [31:0] gate_time=odd?timing[127:96]:timing[95:64];
    wire next_tie=!next_word[31]&&next_word[30];
    wire current_note=current_word[31]&&current_word[14:8]!=0;
    wire current_tie=!current_word[31]&&current_word[30];
    // [0]run,[1]record,[2]busy/cleanup,[3]active,[4]error,
    // [11:8]playhead,[18:12]edit address,[23:19]length,[26:24]pattern.
    assign status={5'd0,pattern,length,edit_address,position,3'd0,error,active,
        (busy||reset_pending||midi_valid),recording,running};
    function [31:0] factory_step;
        input [6:0] a;
        reg [6:0] n;
        begin
            case(a[3:0])
                0:n=60;1:n=62;2:n=64;3:n=65;4:n=67;5:n=69;6:n=71;7:n=72;
                8:n=72;9:n=71;10:n=69;11:n=67;12:n=65;13:n=64;14:n=62;default:n=60;
            endcase
            factory_step=a[6:4]==0?(32'h80006000|n):0;
        end
    endfunction
    task send_off;
        begin midi_data<=32'h80800000|({25'd0,active_note}<<8);midi_valid<=1;end
    endtask
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            initializing<=1;write_index<=0;clearing<=0;clear_index<=0;clear_bank<=0;error<=0;
            edit_address<=0;pattern<=0;requested_pattern<=0;length<=16;requested_length<=16;
            position<=0;running<=0;recording<=0;active<=0;first_step<=1;restart_seen<=0;reset_pending<=0;
            state<=IDLE;active_note<=0;us_div<=0;step_left<=0;gate_left<=0;step_length<=1;gate_length<=1;
            gate_enabled<=0;odd<=0;timing<={32'd87500,32'd87500,32'd125000,32'd125000};
            midi_data<=0;midi_valid<=0;
        end else begin
            if(us_tick)us_div<=0;else us_div<=us_div+1'b1;
            if(us_tick&&running&&!midi_valid&&!reset_pending)begin
                if(step_left!=0)step_left<=step_left-1'b1;
                if(gate_left!=0)gate_left<=gate_left-1'b1;
            end
            // One write port. Manual writes are rejected during recording;
            // firmware disarms it for explicit REST/TIE/step edits.
            if(initializing)begin
                steps[write_index]<=factory_step(write_index);
                if(write_index==127)initializing<=0;else write_index<=write_index+1'b1;
            end else if(clearing)begin
                steps[{clear_bank,clear_index}]<=0;
                if(clear_index==15)clearing<=0;else clear_index<=clear_index+1'b1;
            end else if(step_write)begin
                if(recording)error<=1;
                else begin
                    steps[edit_address]<=step_data&32'hc0007f7f;error<=0;
                end
            end else if(clear_pattern)begin
                if(recording)error<=1;
                else begin clearing<=1;clear_index<=0;clear_bank<=edit_address[6:4];error<=0;end
            end else if(recording&&record_hit&&!suspend)begin
                steps[edit_address]<=32'h80000000|{17'd0,human_event[6:0],1'b0,human_event[14:8]};
                edit_address[3:0]<={1'b0,edit_address[3:0]}+1'b1>=requested_length?4'd0:edit_address[3:0]+1'b1;
            end
            if(address_write)edit_address<=address_data;
            if(midi_valid&&midi_ready)begin
                midi_valid<=0;
                if(midi_data[23:20]==4'h9)begin
                    active<=1;active_note<=midi_data[14:8];step_left<=step_length;gate_left<=gate_length;
                end else if(midi_data[23:20]==4'h8)active<=0;
            end
            if(!midi_valid)begin
                if(reset_pending)begin
                    if(active)send_off();
                    else begin reset_pending<=0;state<=IDLE;position<=0;first_step<=1;odd<=0;step_left<=0;end
                end else if(!running||suspend||busy)begin
                    state<=IDLE;
                    if(active)send_off();
                end else case(state)
                    IDLE:begin
                        if(active&&gate_enabled&&gate_left==0)send_off();
                        else if(first_step||step_left==0)begin
                            if(first_step||pattern!=requested_pattern)position<=0;
                            else position<={1'b0,position}+1'b1>=requested_length?4'd0:position+1'b1;
                            pattern<=requested_pattern;length<=requested_length;
                            step_length<=step_time<2?2:step_time;
                            gate_length<=gate_time==0?1:gate_time>=step_time?(step_time<2?1:step_time-1):gate_time;
                            state<=READ0;
                        end
                    end
                    READ0:state<=READ1;
                    READ1:state<=LOAD;
                    LOAD:begin
                        if(active&&!current_tie)send_off();
                        else begin
                            if(current_note)begin
                                midi_data<=32'h80900000|{17'd0,current_word[6:0],8'd0}|{25'd0,current_word[14:8]};
                                midi_valid<=1;
                            end else begin
                                step_left<=step_length;
                                gate_left<=current_tie?step_length:gate_length;
                            end
                            gate_enabled<=!next_tie;
                            first_step<=0;odd<=!odd;state<=IDLE;
                        end
                    end
                    default:state<=IDLE;
                endcase
            end
            // Control takes precedence over a just-completed sequencer step.
            if(control_write&&!busy)begin
                requested_pattern<=control_data[5:3];requested_length<={1'b0,control_data[9:6]}+1'b1;
                timing<=timing_data;
                running<=control_data[0]&&!control_data[1]&&!suspend;
                recording<=control_data[1]&&!suspend;
                if(!control_data[0]||control_data[1]||(!running&&control_data[0])||restart_seen!=control_data[2])
                    reset_pending<=1;
                restart_seen<=control_data[2];
            end
            if(suspend)begin running<=0;recording<=0;reset_pending<=1;end
            if(human_valid&&human_event[23:20]==4'hb&&
                (human_event[14:8]==120||human_event[14:8]==123))begin
                running<=0;recording<=0;reset_pending<=1;
            end
        end
    end
endmodule
