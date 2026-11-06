// Passive 50 MHz telemetry. No signal from this module controls the audio path.
// MMIO uses explicit snapshots so a firmware page never combines live epochs.
module audio_performance_monitor #(
    parameter integer CLOCK_HZ=50000000,
    parameter integer SAMPLE_CYCLES=1024,
    parameter integer VOICE_CAPACITY=16,
    parameter integer MIDI_TRACE_ENABLED=0
)(
    input wire clk,reset_n,
    input wire sample_tick,engine_busy,sample_pending,render_start,render_done,
    input wire voice_steal,midi_accept,midi_stall,bridge_drop,
    input wire usb_accept,input wire [31:0] usb_data,midi_data,
    input wire [7:0] active_voices,
    input wire signed [15:0] audio_sample,
    input wire snapshot,clear_stats,
    input wire [4:0] read_index,
    output reg [31:0] read_data
);
    function [15:0] inc16;
        input [15:0] n;
        begin inc16=(&n)?n:n+1'b1;end
    endfunction
    function [31:0] inc32;
        input [31:0] n;
        begin inc32=(&n)?n:n+1'b1;end
    endfunction
    // Timing trackers survive CLEAR. An in-flight render still has its true
    // duration after clearing counters; no partial render is fabricated.
    reg pending_valid,render_active;
    reg [15:0] pending_age,render_age,response_age;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            pending_valid<=0;render_active<=0;pending_age<=0;render_age<=0;response_age<=0;
        end else begin
            if(pending_valid)pending_age<=inc16(pending_age);
            if(sample_tick&&!sample_pending)begin pending_valid<=1;pending_age<=0;end
            if(render_start)begin
                pending_valid<=0;render_active<=1;render_age<=0;
                response_age<=pending_valid?inc16(pending_age):0;
            end
            if(render_active)begin render_age<=inc16(render_age);response_age<=inc16(response_age);end
            if(render_done)render_active<=0;
        end
    end
    reg [15:0] last_render,max_render,last_response,max_response;
    reg [15:0] busy_window,last_busy,max_busy,period_age,last_period;
    reg period_valid;
    reg [31:0] completed,deadlines,lost_ticks,steals,drops,midi_events,stall_clocks,ticks;
    reg [7:0] peak_voices;
    reg [15:0] peak_sample;
    wire [15:0] sample_magnitude=audio_sample[15]?(~audio_sample+16'd1):audio_sample;
    wire [15:0] busy_complete=engine_busy?inc16(busy_window):busy_window;
    wire [15:0] render_elapsed=inc16(render_age);
    wire [15:0] response_elapsed=inc16(response_age);
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin
            last_render<=0;max_render<=0;last_response<=0;max_response<=0;
            busy_window<=0;last_busy<=0;max_busy<=0;period_age<=0;last_period<=0;period_valid<=0;
            completed<=0;deadlines<=0;lost_ticks<=0;steals<=0;drops<=0;midi_events<=0;stall_clocks<=0;ticks<=0;
            peak_voices<=0;peak_sample<=0;
        end else if(clear_stats)begin
            last_render<=0;max_render<=0;last_response<=0;max_response<=0;
            busy_window<=0;last_busy<=0;max_busy<=0;period_age<=0;last_period<=0;period_valid<=0;
            completed<=0;deadlines<=0;lost_ticks<=0;steals<=0;drops<=0;midi_events<=0;stall_clocks<=0;ticks<=0;
            peak_voices<=active_voices;peak_sample<=0;
        end else begin
            period_age<=inc16(period_age);
            if(engine_busy)busy_window<=inc16(busy_window);
            if(active_voices>peak_voices)peak_voices<=active_voices;
            if(midi_accept)midi_events<=inc32(midi_events);
            if(midi_stall)stall_clocks<=inc32(stall_clocks);
            if(voice_steal)steals<=inc32(steals);
            if(bridge_drop)drops<=inc32(drops);
            if(sample_tick)begin
                ticks<=inc32(ticks);period_age<=0;period_valid<=1;busy_window<=0;
                if(period_valid)begin
                    last_period<=inc16(period_age);last_busy<=busy_complete;
                    if(busy_complete>max_busy)max_busy<=busy_complete;
                end
                // Completion on this same edge is too late for the I2S latch,
                // which consumes the preceding value of sample_out.
                if(render_active||sample_pending)deadlines<=inc32(deadlines);
                // Existing synth has one pending request bit. A tick while
                // it is set is coalesced, including a simultaneous consume.
                if(sample_pending)lost_ticks<=inc32(lost_ticks);
                if(sample_magnitude>peak_sample)peak_sample<=sample_magnitude;
            end
            if(render_done&&render_active)begin
                completed<=inc32(completed);last_render<=render_elapsed;last_response<=response_elapsed;
                if(render_elapsed>max_render)max_render<=render_elapsed;
                if(response_elapsed>max_response)max_response<=response_elapsed;
            end
        end
    end
    reg [31:0] usb_events,usb_last,usb_previous,audio_last,audio_previous;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin usb_events<=0;usb_last<=0;usb_previous<=0;audio_last<=0;audio_previous<=0;end
        else if(clear_stats)begin usb_events<=0;usb_last<=0;usb_previous<=0;audio_last<=0;audio_previous<=0;end
        else if(MIDI_TRACE_ENABLED)begin
            if(usb_accept)begin usb_events<=inc32(usb_events);usb_previous<=usb_last;usb_last<=usb_data;end
            if(midi_accept)begin audio_previous<=audio_last;audio_last<=midi_data;end
        end
    end
    reg [31:0] held[0:31];
    integer i;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)for(i=0;i<32;i=i+1)held[i]<=0;
        else if(snapshot)begin
            held[0]<=32'h50455231; // PER1, layout version 1
            held[1]<=CLOCK_HZ;held[2]<=SAMPLE_CYCLES;held[3]<={16'd0,last_period};
            held[4]<=completed;held[5]<={max_render,last_render};held[6]<={max_response,last_response};
            held[7]<={max_busy,last_busy};held[8]<=deadlines;held[9]<=lost_ticks;
            held[10]<=steals;held[11]<=drops;held[12]<=midi_events;
            held[13]<={16'(VOICE_CAPACITY),peak_voices,active_voices};
            held[14]<=stall_clocks;held[15]<={16'd0,peak_sample};held[16]<=ticks;
            held[17]<={29'd0,engine_busy,sample_pending,render_active};
            held[24]<=usb_events;held[25]<=usb_last;held[26]<=usb_previous;
            held[27]<=audio_last;held[28]<=audio_previous;
        end
    end
    always @* read_data=held[read_index];
endmodule
