`timescale 1ns/1ps
module tb_ov5640_capture;
    reg pclk=0;always #13 pclk=~pclk;
    reg reset_n=0,href=0,vsync=0;reg [7:0] data=0;
    wire pixel_write,frame_start,frame_good,frame_bad,frame_toggle,bad_toggle;
    wire [14:0] pixel_address;wire [7:0] pixel_data;
    wire debug_request;wire debug_ack=debug_request;wire [71:0] debug_packet;
    wire [7:0] capture_status;
    ov5640_capture #(.WIDTH(8),.HEIGHT(6),.WARMUP_FRAMES(2)) dut(.*);
    integer good=0,bad=0,n=0;reg verify=0;
    always @(posedge pclk)begin
        if(frame_good)good=good+1;if(frame_bad)bad=bad+1;
        if(pixel_write)begin
            if(pixel_address>=12)$fatal(1,"DVP address overflow");
            if(verify)begin
                if(pixel_address!==n||pixel_data!==8'({3'(n/4),3'(n%4),2'b10}))
                    $fatal(1,"DVP byte order/decimation/position at %d got%h",n,pixel_data);
                n=n+1;
            end
        end
    end
    task boundary;
        begin @(negedge pclk);href=0;vsync=1;repeat(4)@(negedge pclk);vsync=0;repeat(4)@(negedge pclk);end
    endtask
    task image(input integer rows,columns,odd);
        integer y,x;reg [15:0] v;
        begin
            n=0;
            for(y=0;y<rows;y=y+1)begin
                @(negedge pclk);href=1;
                for(x=0;x<columns;x=x+1)begin
                    v={3'(y/2),2'b00,3'(x/2),3'b000,2'b10,3'b000};
                    data=v[15:8];@(negedge pclk);
                    if(!(odd&&y==0&&x==columns-1))begin data=v[7:0];@(negedge pclk);end
                end
                href=0;repeat(6)@(negedge pclk);
            end
            boundary;
        end
    endtask
    initial begin
        repeat(5)@(negedge pclk);reset_n=1;
        // Reset released mid-frame: ignore until an actual VSYNC boundary.
        href=1;repeat(20)@(negedge pclk);if(pixel_write||frame_good)$fatal(1,"Unsynchronized frame accepted");
        boundary;verify=1;image(6,8,0);image(6,8,0);if(good!=0)$fatal(1,"Warmup skipped");
        image(6,8,0);if(good!=1||n!=12)$fatal(1,"Valid frame lost");
        verify=0;image(6,7,0);image(5,8,0);image(7,8,0);image(6,9,0);image(6,8,1);
        if(bad!=5||good!=1)$fatal(1,"Malformed frame accepted bad%d good%d",bad,good);
        verify=1;image(6,8,0);image(6,8,0);image(6,8,0);
        if(good!=2)$fatal(1,"Warmup did not recover after errors");
        if(debug_packet!=={8'd0,16'd16,16'd16,16'd6,16'd12})$fatal(1,"DVP geometry telemetry mismatch %h",debug_packet);
        @(negedge pclk);href=1;repeat(3)@(negedge pclk);reset_n=0;
        repeat(3)@(negedge pclk);if(pixel_write||frame_good||dut.seen_sync)$fatal(1,"Mid-pixel reset failed");
        $display("PASS DVP capture: RGB565 byte order, all decimated coordinates, warmup, unsynchronized input, short/long rows and frames, odd bytes and mid-pixel reset");$finish;
    end
    initial begin #1000000;$fatal(1,"Capture timeout");end
endmodule
