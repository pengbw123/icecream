`timescale 1ns/1ps
module tb_calibration_banner;
reg pclk=0;always #5 pclk=~pclk;
reg reset_n=0,enabled=0;reg [10:0] h=0;reg [9:0] v=0;wire panel_on,ink;
calibration_banner dut(.*);
int covers=0,inks=0;
task tick;@(posedge pclk);#1;endtask
initial begin
 repeat(3)tick();reset_n=1;enabled=1;
 for(int yy=168;yy<312;yy++)for(int xx=196;xx<604;xx++)begin
   @(negedge pclk);h=xx;v=yy;tick();if(panel_on)covers++;if(ink)inks++;
 end
 if(covers<56000||inks<400)$fatal(1,"banner failed cover=%0d ink=%0d",covers,inks);
 @(negedge pclk);enabled=0;repeat(4)tick();if(panel_on||ink)$fatal(1,"banner stuck enabled");
 $display("CALIBRATION_BANNER_OK covers=%0d ink=%0d",covers,inks);$finish;
end
endmodule
