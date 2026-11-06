`timescale 1ns/1ps
module tb_calibration_sync;
reg pclk=0;always #5 pclk=~pclk;
reg reset_n=0,notice_async=0,frame_latch=0;wire notice_frame;
calibration_notice_sync dut(.*);
task tick;@(posedge pclk);#1;endtask
initial begin
 repeat(2)tick();reset_n=1;notice_async=1;repeat(4)tick();
 if(notice_frame)$fatal(1,"notice changed outside frame boundary");
 frame_latch=1;tick();frame_latch=0;if(!notice_frame)$fatal(1,"notice failed to appear");
 notice_async=0;repeat(4)tick();if(!notice_frame)$fatal(1,"notice vanished mid-frame");
 frame_latch=1;tick();frame_latch=0;if(notice_frame)$fatal(1,"notice failed to disappear");
 $display("CALIBRATION_SYNC_OK stable per frame and disappears after synchronized expiry");$finish;
end
endmodule
