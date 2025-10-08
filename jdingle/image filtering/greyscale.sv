// grayscale.sv
module grayscale (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [23:0] pixel_in,  // {R[23:16], G[15:8], B[7:0]}
    output logic        out_valid,
    output logic [7:0]  gray_out
);

    // Coefficients (scaled by 256)
    localparam int C_R = 77;
    localparam int C_G = 150;
    localparam int C_B = 29;

    // Extract channels
    logic [7:0] R, G, B;
    always_comb begin
        R = pixel_in[23:16];
        G = pixel_in[15:8];
        B = pixel_in[7:0];
    end

    // Accumulator width: choose 18 bits (safe)
    logic [17:0] acc;

    // Compute when in_valid is asserted. Combinational multiply-add.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= '0;
            gray_out <= '0;
            out_valid <= 1'b0;
        end else begin
            if (in_valid) begin
                // Multiply-add (synthesizable - inferred multipliers)
                acc <= C_R * R + C_G * G + C_B * B; // up to ~65k
                gray_out <= (C_R * R + C_G * G + C_B * B) >> 8; // integer shift
                out_valid <= 1'b1;
            end else begin
                out_valid <= 1'b0;
            end
        end
    end

endmodule
