// Passive, qualified LIVE NoteOn -> first audible I2S left word completed.
// This measures only the FPGA-visible digital path, never key-to-ear latency.
module audio_note_latency #(
 parameter integer CLOCK_HZ=50000000, QUIET_FRAMES=32,
 parameter integer TIMEOUT_CLOCKS=CLOCK_HZ/4, THRESHOLD=32
)(
 input wire clk,reset_n,enable,event_valid,event_ready,
 input wire [31:0] event_data,input wire [7:0] active_voices,
 input wire frame_load,left_word_done,input wire signed [15:0] sample_value,
 input wire snapshot,clear_stats,input wire [4:0] read_index,
 output reg [31:0] read_data,output wire marker
);
 assign marker=pending;
 reg [31:0] age,last_latency,max_latency,completed,timeouts,skipped;
 reg pending,word_pending,seen;
 reg [15:0] quiet;
 wire [15:0] magnitude=sample_value[15]?(~sample_value+16'd1):sample_value;
 wire note_on=event_data[31:28]==0&&event_data[23:20]==9&&event_data[6:0]!=0;
 wire fresh_event=event_valid&&!seen;
 reg [31:0] held[0:5];integer i;
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin
   age<=0;last_latency<=0;max_latency<=0;completed<=0;timeouts<=0;skipped<=0;
   pending<=0;word_pending<=0;seen<=0;quiet<=0;
  end else begin
   // A stalled producer is counted once; consecutive accepted packets may
   // legally keep VALID high and are separate events.
   if(!event_valid||event_ready)seen<=0;else seen<=1;
   if(frame_load)begin
    if(magnitude<=THRESHOLD&&active_voices==0)begin if(quiet<QUIET_FRAMES)quiet<=quiet+1'b1;end
    else quiet<=0;
   end
   if(clear_stats)begin
    age<=0;last_latency<=0;max_latency<=0;completed<=0;timeouts<=0;skipped<=0;
    pending<=0;word_pending<=0;quiet<=0;
   end else begin
    if(fresh_event&&note_on)begin
     if(enable&&!pending&&quiet>=QUIET_FRAMES&&active_voices==0&&magnitude<=THRESHOLD)begin
      age<=0;pending<=1;word_pending<=0;quiet<=0;
     end else if(skipped!=32'hffffffff)skipped<=skipped+1'b1;
    end
    if(pending)begin
     age<=age+1'b1;
     if(fresh_event&&note_on)begin pending<=0;word_pending<=0;end
     else if(!enable||age>=TIMEOUT_CLOCKS-1)begin
      pending<=0;word_pending<=0;if(timeouts!=32'hffffffff)timeouts<=timeouts+1'b1;
     end else if(left_word_done&&word_pending)begin
      pending<=0;word_pending<=0;last_latency<=age+1'b1;
      if(age+1'b1>max_latency)max_latency<=age+1'b1;
      if(completed!=32'hffffffff)completed<=completed+1'b1;
     end else if(frame_load&&magnitude>THRESHOLD)word_pending<=1;
    end
   end
  end
 end
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)for(i=0;i<6;i=i+1)held[i]<=0;
  else if(snapshot)begin
   held[0]<=last_latency;held[1]<=max_latency;held[2]<=completed;
   held[3]<=timeouts;held[4]<=skipped;
   held[5]<={28'd0,enable,quiet>=QUIET_FRAMES,word_pending,pending};
  end
 end
 always @*read_data=(read_index>=18&&read_index<=23)?held[read_index-18]:32'd0;
endmodule
