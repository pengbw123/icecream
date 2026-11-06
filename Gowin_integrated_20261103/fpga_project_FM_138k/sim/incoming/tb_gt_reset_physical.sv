`timescale 1ns/1ps
// Check the unaccelerated 50 MHz touch-reset sequence at its external pins.
module tb_gt_reset_physical;
    reg clk=0;always #10 clk=~clk;
    reg reset_n=0;
    wire tp_int_o,tp_int_t,tp_rst,ready;
    gt9147_reset dut(.*);
    int cycles=0;
    task automatic tick;@(posedge clk);#1;endtask
    initial begin
        repeat(4)tick();
        if(tp_rst!==0||tp_int_t!==0||tp_int_o!==0||ready!==0)$fatal(1,"bad touch reset state");
        @(negedge clk);reset_n=1;
        while(!ready && cycles<8850100)begin
            tick();cycles++;
            case(cycles)
                999000:if(tp_rst!==0||tp_int_t!==0||tp_int_o!==0)$fatal(1,"20ms reset-low phase");
                1025000:if(tp_rst!==0||tp_int_t!==0||tp_int_o!==1)$fatal(1,"address-selection phase");
                1100000:if(tp_rst!==1||tp_int_t!==0||tp_int_o!==1)$fatal(1,"reset release phase");
                1500000:if(tp_rst!==1||tp_int_t!==0||tp_int_o!==0)$fatal(1,"50ms synchronization phase");
                4000000:if(tp_rst!==1||tp_int_t!==1||ready!==0)$fatal(1,"100ms boot-wait phase");
                8845000:if(ready!==0)$fatal(1,"ready asserted before 177ms");
            endcase
        end
        if(!ready||cycles!=8850000||tp_rst!==1||tp_int_t!==1)$fatal(1,"touch reset completion cycle=%0d",cycles);
        @(negedge clk);reset_n=0;#1;
        if(tp_rst!==0||tp_int_t!==0||tp_int_o!==0||ready!==0)$fatal(1,"reasserted reset did not clear touch state");
        $display("GT_RESET_50MHZ_OK exact_177ms pin_sequence and reset_reassertion");$finish;
    end
endmodule
