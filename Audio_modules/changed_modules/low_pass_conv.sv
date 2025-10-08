module low_pass_conv #(parameter W=32, W_FRAC=16) (
    input  logic clk,
    input  logic reset,
    input  logic x_valid,
    output logic x_ready,
    input  logic [W-1:0] x_data,
    output logic y_valid,
    input  logic y_ready,
    output logic [W-1:0] y_data
);
    localparam N = 41;

    // Filter coefficients
    logic signed [W-1:0] h [0:N-1] = '{
        32'h00000000, 32'h00000014, 32'h0000003f, 32'h00000050, 32'h00000000,
        32'hffffff0b, 32'hfffffd56, 32'hfffffb08, 32'hfffff8a1, 32'hfffff6ee,
        32'hfffff6f3, 32'hfffff9b5, 32'h00000000, 32'h00000a2d, 32'h000017f4,
        32'h00002860, 32'h000039e3, 32'h00004a8b, 32'h0000584b, 32'h0000615d,
        32'h00006488, 32'h0000615d, 32'h0000584b, 32'h00004a8b, 32'h000039e3,
        32'h00002860, 32'h000017f4, 32'h00000a2d, 32'h00000000, 32'hfffff9b5,
        32'hfffff6f3, 32'hfffff6ee, 32'hfffff8a1, 32'hfffffb08, 32'hfffffd56,
        32'hffffff0b, 32'h00000000, 32'h00000050, 32'h0000003f, 32'h00000014,
        32'h00000000
    };

    // Shift register for input samples
    logic signed [W-1:0] shift_reg [0:N-1];
    integer i;

    // MAC state
    logic [$clog2(N)-1:0] mac_index;
    logic [$clog2(N)+2*W-1:0] acc;
    logic mac_running;

    // Input handshake: accept new sample only when MAC is idle
    assign x_ready = ~mac_running;

    // Latch new input and shift register
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i=0; i<N; i=i+1) shift_reg[i] <= 0;
            mac_running <= 0;
            mac_index <= 0;
            acc <= 0;
        end else if (x_valid & x_ready) begin
            // Shift in new sample
            for (i=N-1; i>0; i=i-1) shift_reg[i] <= shift_reg[i-1];
            shift_reg[0] <= x_data;

            // Start MAC
            mac_running <= 1;
            mac_index <= 0;
            acc <= 0;
        end else if (mac_running) begin
            // Sequential multiply-accumulate
            acc <= acc + shift_reg[mac_index] * h[mac_index];
            if (mac_index == N-1) begin
                mac_running <= 0; // MAC finished
            end
            mac_index <= mac_index + 1;
        end
    end

    // Output logic
    logic y_valid_reg;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            y_valid_reg <= 0;
            y_data <= 0;
        end else if (~mac_running & x_ready==0) begin
            // Only assert y_valid when MAC has finished and downstream is ready
            y_valid_reg <= 1'b1;
            y_data <= acc >>> W_FRAC;
        end else if (y_ready) begin
            y_valid_reg <= 0; // Clear after downstream consumes data
        end
    end

    assign y_valid = y_valid_reg;

endmodule
