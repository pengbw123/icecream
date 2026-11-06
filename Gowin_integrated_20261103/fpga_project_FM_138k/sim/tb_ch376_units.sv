`timescale 1ns/1ps
module tb_ch376_units;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0,start=0,byte_valid=0,finish=0;
    reg [7:0] byte_data;
    wire done,malformed,found;
    wire [7:0] config_value,ifnum,alt;
    wire [3:0] ep;
    wire [6:0] mps;
    wire [15:0] total;
    usb_midi_config_parser parser(.clk(clk),.reset_n(reset_n),.start(start),.byte_valid(byte_valid),
        .byte_data(byte_data),.finish(finish),.done(done),.malformed(malformed),.found(found),
        .configuration_value(config_value),.interface_number(ifnum),.alternate_setting(alt),
        .endpoint_number(ep),.endpoint_max_packet(mps),.total_length(total));
    byte unsigned descriptor[$];
    task send_descriptor;
        @(negedge clk);start=1;@(negedge clk);start=0;
        foreach(descriptor[j]) begin
            byte_valid=1;byte_data=descriptor[j];@(negedge clk);byte_valid=0;
            if(j%8==7) repeat(5) @(negedge clk);
        end
        finish=1;@(negedge clk);finish=0;
        assert(done) else $fatal(1,"parser did not finish");
    endtask
    task make_descriptor(input byte protocol, input int packet_size);
        descriptor={9,2,0,0,1,5,0,8'h80,50,
            9,4,7,1,1,1,3,0,0,
            9,5,8'h83,2,0,0,0,0,0,
            5,8'h25,1,1,1};
        descriptor[16]=protocol;descriptor[22]=packet_size;descriptor[23]=packet_size>>8;
        descriptor[2]=byte'(descriptor.size());descriptor[3]=0;
    endtask
    reg [31:0] packet;
    wire event_ok;
    wire [31:0] event_data;
    usb_midi_event_decode decode(.packet(packet),.valid(event_ok),.event_data(event_data));
    int velocity_checks=0;
    reg [31:0] data0=32'h12340000,data1=32'h12340001,data2=32'h12340002;
    reg v0=0,v1=0,v2=0,out_ready=0;
    wire r0,r1,r2,out_valid;
    wire [31:0] out_data;
    midi_event_arbiter3 arb(.clk(clk),.reset_n(reset_n),.data0(data0),.data1(data1),.data2(data2),
        .valid0(v0),.valid1(v1),.valid2(v2),.ready0(r0),.ready1(r1),.ready2(r2),
        .event_data(out_data),.event_valid(out_valid),.event_ready(out_ready));
    int seen[3];
    always @(posedge clk) if(reset_n && out_valid && out_ready) begin
        assert(out_data[31:2]==(32'h12340000>>2)) else $fatal(1,"arbiter data corrupt");
        seen[out_data[1:0]]++;
    end
    initial begin
        repeat(5) @(negedge clk);reset_n=1;
        make_descriptor(0,64);send_descriptor();
        assert(found && !malformed && config_value==5 && ifnum==7 && alt==1 && ep==3 && mps==64)
            else $fatal(1,"valid MIDI configuration rejected");
        make_descriptor(2,64);send_descriptor();assert(!found && !malformed) else $fatal(1,"UMP accepted as MIDI1");
        make_descriptor(0,512);send_descriptor();assert(!found) else $fatal(1,"high speed MPS accepted");
        make_descriptor(0,63);send_descriptor();assert(!found) else $fatal(1,"non-event-aligned MPS accepted");
        make_descriptor(0,12);send_descriptor();assert(!found) else $fatal(1,"nonstandard FS bulk MPS accepted");
        make_descriptor(0,64);descriptor[18]=0;send_descriptor();assert(malformed && !found) else $fatal(1,"zero bLength accepted");
        make_descriptor(0,64);descriptor.pop_back();send_descriptor();assert(malformed && !found) else $fatal(1,"truncated descriptor accepted");
        make_descriptor(0,64);descriptor[2]=descriptor[2]+8'd1;send_descriptor();assert(malformed && !found) else $fatal(1,"wrong total accepted");
        // Cross 255-byte and 64-byte boundaries with a legal unknown descriptor.
        make_descriptor(0,64);
        repeat(140) begin descriptor.push_back(2);descriptor.push_back(8'hff);end
        descriptor[2]=byte'(descriptor.size());descriptor[3]=byte'(descriptor.size()>>8);
        send_descriptor();assert(found && !malformed && total==descriptor.size()) else $fatal(1,"wide descriptor count truncated");
        make_descriptor(0,64);
        repeat(2032) begin descriptor.push_back(2);descriptor.push_back(8'hff);end
        descriptor[2]=0;descriptor[3]=16;
        send_descriptor();assert(found && !malformed && total==4096) else $fatal(1,"4096-byte count truncated");
        for(int v=0;v<128;v++) begin
            packet={byte'(v),8'd60,8'h90,8'h09};#1;
            assert(event_ok && event_data[23:8]==16'h903c) else $fatal(1,"decode layout");
            if(v==0) assert(event_data[7:0]==0) else $fatal(1,"zero velocity release changed");
            if(v>=80) assert(event_data[7:0]==127) else $fatal(1,"velocity saturation");
            if(v>0) assert(event_data[7:0]>0) else $fatal(1,"positive velocity became release");
            velocity_checks++;
        end
        packet=32'h28409129;#1;assert(event_ok && event_data==32'h29914028) else $fatal(1,"channel one velocity changed");
        packet=32'hff05c00c;#1;assert(event_ok && event_data==32'h0cc00500) else $fatal(1,"two-byte MIDI padding");
        packet=32'hff3c9009;#1;assert(!event_ok) else $fatal(1,"invalid data high bit accepted");
        packet=32'h403c8009;#1;assert(!event_ok) else $fatal(1,"CIN/status mismatch accepted");
        packet=32'h0000f80f;#1;assert(!event_ok) else $fatal(1,"clock emitted as note");
        // A low-priority UI event must remain stable while a host event arrives.
        @(negedge clk);v2=1;
        @(negedge clk);v2=0;assert(out_valid && out_data==data2);
        v0=1;v1=1;
        repeat(5) begin @(negedge clk);assert(out_valid && out_data==data2 && !r0 && !r1);end
        out_ready=1;
        @(negedge clk);assert(out_data==data0);v0=0;
        @(negedge clk);assert(out_data==data1);v1=0;
        @(negedge clk);assert(!out_valid);
        assert(seen[0]==1 && seen[1]==1 && seen[2]==1) else $fatal(1,"arbiter duplicate/lost event");
        $display("CH376_UNITS_OK descriptor_cases=10 max_descriptor=4096 velocity_cases=%0d arbiter_stall_ok=1",velocity_checks);$finish;
    end
    initial begin #1000000;$fatal(1,"unit test timeout");end
endmodule
