module debounced_press #(
    parameter integer STABLE_CYCLES = 500000
)(
    input wire clk, reset_n, button_n,
    output reg pressed
);
    reg [1:0] sync_n;
    reg stable_n;
    integer stable_count;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sync_n <= 2'b11; stable_n <= 1; stable_count <= 0; pressed <= 0;
        end else begin
            sync_n <= {sync_n[0],button_n};
            pressed <= 0;
            if (sync_n[1] == stable_n) stable_count <= 0;
            else if (stable_count == STABLE_CYCLES-1) begin
                stable_n <= sync_n[1]; stable_count <= 0;
                if (!sync_n[1]) pressed <= 1;
            end else stable_count <= stable_count+1;
        end
    end
endmodule
