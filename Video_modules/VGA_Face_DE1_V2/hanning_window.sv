// hanning_window.sv — window AFTER FIFO/LPF, sample-by-sample
module hanning_window #(
    parameter int W     = 16,            // sample width
    parameter int N     = 1024,          // samples per frame
    // If your coeffs are generated as Q1.15, set FRAC=15.
    // If your coeffs are plain integers (no fractional), set FRAC=0.
    parameter int FRAC  = 15,
    // Name of the coefficient file (hex, one value per line, W bits wide)
    parameter string COEFF_FILE = "hanning_coeff.mem",
    // Choose whether to output full 2W-bit product (1) or W-bit shifted/truncated (0)
    parameter bit   OUT_WIDE = 1,
	 parameter int MAX_SAMPLE_INDEX = 10
)(
    input  logic                   clk,
    input  logic                   reset,

    // Simple ready/valid streaming interface (no backpressure here)
    output logic                   sample_in_ready,   // always ready (1)
    input  logic                   sample_in_valid,   // advance when 1
    input  logic signed [W-1:0]    sample_in,         // *** signed ***

    // Output
    output logic signed [(2*W-1):0] windowed_sample,  // 2W if OUT_WIDE=1 else sign-extended W
    output logic                    windowed_valid,
    output logic                    frame_done
);
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    localparam int IDXW = (N <= 2) ? 1 : $clog2(N);
    logic [IDXW-1:0] sample_index;

    // -------------------------------------------------------------------------
    // Coefficient ROM (signed)
    // IMPORTANT: add COEFF_FILE to your Quartus project files so it packs into bitstream.
    // -------------------------------------------------------------------------
    logic signed [W-1:0] hanning_coeff [0:N-1];

    initial begin
        // Synthesis on Intel works if the file is in the project.
        // If you see zeros in hardware, your file wasn’t included.
        $readmemh("hanning_coeff.mem", hanning_coeff);
    end

    // Always ready (no backpressure here)
    assign sample_in_ready = 1'b1;

    // Multiply (registered)
    logic signed [W-1:0]    coeff_s;
    logic signed [2*W-1:0]  product;      // exact product
    logic signed [W-1:0]    product_q;    // shifted/truncated to W if needed

    // Optional fixed-point alignment (right shift by FRAC)
    // product[2*W-1:0] has binary point at (FRAC) if coeffs are Qx.FRAC.
    // Take W MSBs starting at bit (W+FRAC-1).
    always_comb begin
        coeff_s    = hanning_coeff[sample_index];
        product_q  = product[W+FRAC-1 -: W];  // safe when 0 <= FRAC <= W
    end

    // Pipeline: register output and valid with one-cycle latency
    always_ff @(posedge clk) begin
        if (reset) begin
            sample_index    <= '0;
            windowed_sample <= '0;
            windowed_valid  <= 1'b0;
            frame_done      <= 1'b0;
        end
        else begin
            windowed_valid <= 1'b0;
            frame_done     <= 1'b0;

            if (sample_in_valid && sample_in_ready) begin
                // Do multiply this cycle, register results next cycle
                product <= sample_in * coeff_s;

                // Register output
                if (OUT_WIDE) begin
                    windowed_sample <= product;                 // feed a 32-bit FFT, etc.
                end else begin
                    // Return W-bit aligned sample (sign-extend)
                    windowed_sample <= {{(2*W-W){product_q[W-1]}}, product_q};
                end

                windowed_valid <= 1'b1;

                // Advance index with **non-blocking** wrap
                if (sample_index == N-1) begin
                    sample_index <= '0;
                    frame_done   <= 1'b1;
                end else begin
                    sample_index <= sample_index + 1'b1;
                end
            end
        end
    end
endmodule
