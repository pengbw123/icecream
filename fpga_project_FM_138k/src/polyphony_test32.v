// Held valid/ready MIDI source; emit matching NoteOffs even if stopped early.
module polyphony_test32(input wire clk,reset_n,press,allowed,
 output wire active,output wire valid,output wire [31:0] data,input wire ready);
 reg [2:0] state;reg [5:0] count,sent;reg stop_requested;
 localparam IDLE=0,START=1,HOLD=2,STOP=3,CLEAN=4;
 assign active=state!=IDLE;
 assign valid=state==START||state==STOP||state==CLEAN;
 wire [7:0] note=8'd96+{2'd0,count};
 assign data=state==CLEAN?32'h88b07b00:{8'h88,(state==START?8'h90:8'h80),note,(state==START?8'd32:8'd0)};
 always @(posedge clk)begin
  if(!reset_n)begin state<=IDLE;count<=0;sent<=0;stop_requested<=0;end
  else begin
   if(press&&state==START)stop_requested<=1;
   case(state)
    IDLE:if(press&&allowed)begin state<=START;count<=0;sent<=0;stop_requested<=0;end
    START:if(ready)begin
     sent<=sent+1'b1;
     if(stop_requested||press)begin state<=STOP;count<=0;end
     else if(count==31)begin state<=HOLD;count<=0;end
     else count<=count+1'b1;
    end
    HOLD:if(press)begin state<=STOP;count<=0;end
    STOP:if(ready)begin
     if(count+1'b1==sent)begin state<=CLEAN;count<=0;end
     else count<=count+1'b1;
    end
    CLEAN:if(ready)state<=IDLE;
   endcase
  end
 end
endmodule
