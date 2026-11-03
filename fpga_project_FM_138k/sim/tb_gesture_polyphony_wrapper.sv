// Run the existing, unchanged 32-voice demonstration regression with the
// production gesture adapter present. Gesture control is off for this test.
module tb_gesture_polyphony_wrapper;
    tb_polyphony_audio test();
    defparam test.dut.GESTURE_ENABLED=1;
    initial begin
        force test.dut.gesture_control=1'b0;
        force test.dut.gesture_valid=1'b0;
        force test.dut.gesture_action=4'd0;
    end
endmodule
