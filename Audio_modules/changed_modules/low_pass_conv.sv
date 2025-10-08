module low_pass_conv #(parameter W=32, W_FRAC=16, N=41, PIPE=4) (
    input  logic clk,
    input  logic reset,
    input  logic x_valid,
    output logic x_ready,
    input  logic [W-1:0] x_data,
    output logic y_valid,
    input  logic y_ready,
    output logic [W-1:0] y_data
);
    // Filter coefficients
    logic signed [W-1:0] h [0:N-1];
    initial begin
        h[0]=32'h00000000; h[1]=32'h00000014; // ... fill the rest
        // Same as before
    end

    // Shift register
    logic signed [W-1:0] shift_reg [0:N-1];
    integer i;

    always_ff @(posedge clk) begin
        if (reset) begin
            for (i=0;i<N;i=i+1) shift_reg[i]<=0;
        end else if (x_valid & x_ready) begin
            for (i=N-1;i>=1;i=i-1) shift_reg[i]<=shift_reg[i-1];
            shift_reg[0]<=x_data;
        end
    end

    // Pipelined MAC
    logic [$clog2(N/PIPE+1)+W+W_FRAC-1:0] acc;
    logic mac_running;
    logic [$clog2(N)-1:0] mac_index;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            acc<=0; mac_index<=0; mac_running<=0;
        end else if (x_valid & x_ready) begin
            mac_running <= 1;
            mac_index <= 0;
            acc <= 0;
        end else if (mac_running) begin
            integer j;
            for (j=0;j<PIPE;j=j+1) begin
                if (mac_index+j < N)
                    acc <= acc + shift_reg[mac_index+j]*h[mac_index+j];
            end
            mac_index <= mac_index + PIPE;
            if (mac_index + PIPE >= N)
                mac_running <= 0;
        end
    end

    assign x_ready = ~mac_running; // accept new sample only when MAC idle

    // Output
    logic y_valid_reg;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            y_valid_reg<=0;
            y_data<=0;
        end else if (~mac_running) begin
            y_valid_reg <= 1;
            y_data <= acc >>> W_FRAC;
        end else if (y_ready) begin
            y_valid_reg <= 0;
        end
    end
    assign y_valid = y_valid_reg;
endmodule
