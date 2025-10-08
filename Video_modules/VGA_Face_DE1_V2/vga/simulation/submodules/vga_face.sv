module vga_p2 (
    input  logic        clk,
    input  logic        reset,
    output logic [29:0] data,
    output logic        startofpacket,
    output logic        endofpacket,
    output logic        valid,
    input  logic        ready
);

    localparam NumPixels = 640*480;

    // Image ROM
    (* ram_init_file = "p2.mif" *) logic [5:0] p2_face [0:NumPixels-1];
    logic [18:0] pixel_index = 0, pixel_index_next;
    logic [5:0] pixel_q;

    assign valid = ~reset;
    assign startofpacket = (pixel_index == 0);
    assign endofpacket   = (pixel_index == NumPixels-1);

    always_ff @(posedge clk) begin
        if (reset)
            pixel_index <= 0;
        else if (valid && ready)
            pixel_index <= pixel_index_next;
    end

    always_comb begin
        if (reset)
            pixel_index_next = 0;
        else if (valid && ready)
            pixel_index_next = (pixel_index == NumPixels-1) ? 0 : pixel_index + 1;
        else
            pixel_index_next = pixel_index;
    end

    always_ff @(posedge clk) begin
        if (valid && ready)
            pixel_q <= p2_face[pixel_index];
    end

    // 2-bit per channel -> 10-bit VGA
    wire [9:0] red_10   = { {4{pixel_q[5:4]}}, 2'b00 };
    wire [9:0] green_10 = { {4{pixel_q[3:2]}}, 2'b00 };
    wire [9:0] blue_10  = { {4{pixel_q[1:0]}}, 2'b00 };

    assign data = {red_10, green_10, blue_10};

endmodule
