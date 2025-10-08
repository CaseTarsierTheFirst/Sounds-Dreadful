module vga_face (
    input  logic        clk,             
    input  logic        reset,           
    input  logic [1:0]  face_select,     // 0: wolf 1: colour 2: P2

    // Avalon-ST Interface:
    output logic [29:0] data,            // Data output to VGA (10 bits per RGB)
    output logic        startofpacket,   
    output logic        endofpacket,     
    output logic        valid,           
    input  logic        ready            
);

    typedef enum logic [1:0] {Wolf=2'd0, P2=2'd1, Colour=2'd2} face_t;

    localparam VGA_WIDTH  = 640;
    localparam VGA_HEIGHT = 480;
    localparam SRC_WIDTH  = 160;
    localparam SRC_HEIGHT = 120;
    localparam NumPixels  = VGA_WIDTH * VGA_HEIGHT;
    localparam NumColourBits = 12; // 4 bits per R, G, B

    // Image ROMs (160x120, 4 bits per channel)
    (* ram_init_file = "wolf.mif" *)   logic [NumColourBits-1:0] wolf_face   [0: SRC_WIDTH*SRC_HEIGHT-1];
    (* ram_init_file = "colour.mif" *) logic [NumColourBits-1:0] colour_face [0: SRC_WIDTH*SRC_HEIGHT-1];
    (* ram_init_file = "p2.mif" *)    logic [NumColourBits-1:0] p2_face    [0: SRC_WIDTH*SRC_HEIGHT-1];

    `ifdef VERILATOR
    initial begin
        $readmemh("wolf.hex", wolf_face);
        $readmemh("colour.hex", colour_face);
        $readmemh("p2.hex", p2_face);
    end
    `endif

    logic [18:0] pixel_index = 0, pixel_index_next;
    logic [NumColourBits-1:0] wolf_face_q, colour_face_q, p2_face_q;
    logic read_enable;

    assign read_enable = reset | (valid & ready);

    // Compute source pixel for 160x120 → 640x480 upscaling (4x)
    logic [17:0] src_pixel_index;
    logic [9:0] x, y;
    logic [9:0] src_x, src_y;

    always_comb begin
        x = pixel_index % VGA_WIDTH;
        y = pixel_index / VGA_WIDTH;

        src_x = x >> 2; // divide by 4
        src_y = y >> 2; // divide by 4

        src_pixel_index = src_y*SRC_WIDTH + src_x;
    end

    always_ff @(posedge clk) begin
        if (read_enable) begin
            wolf_face_q  <= wolf_face[src_pixel_index];
            colour_face_q <= colour_face[src_pixel_index];
            p2_face_q    <= p2_face[src_pixel_index];
        end
    end

    logic [NumColourBits-1:0] current_pixel;
    face_t face_sel;

    always_comb face_sel = face_t'(face_select);

    always_comb begin
        case(face_sel)
            Wolf:   current_pixel = wolf_face_q;
            Colour:  current_pixel = colour_face_q;
            P2:     current_pixel = p2_face_q;
            default: current_pixel = 12'b0;
        endcase
    end

    assign valid = ~reset;
    assign startofpacket = (pixel_index == 0);
    assign endofpacket   = (pixel_index == NumPixels-1);

    // Expand 4-bit channels to 10-bit VGA channels (replicate upper 4 bits then pad 2 zeros)
    wire [3:0] r4 = current_pixel[11:8];
    wire [3:0] g4 = current_pixel[7:4];
    wire [3:0] b4 = current_pixel[3:0];

    // Filter selection: TODO: Modify to be an input parameter
    logic[1:0] filter_select;
    initial filter_select = 4'b0011;    // 0000 - No filter, 0001 - Invert, 0010 - Lighten, 0100 - Darken, 1000 - Greyscale, 1111 - Gaussian blur

    logic[3:0] r_filt, g_filt, b_filt;  // Filter colour channels

    // Apply selected filters
    always_comb begin
        case (filter_select)
            4'b0001: begin //Colour inversion
                r_filt = ~r4;
                g_filt = ~g4;
                b_filt = ~b4;
            end

            4'b0010: begin // Lighten (~38%)
					r_filt = r4 + ((15 - r4) >> 2) + ((15 - r4) >> 3);
					g_filt = g4 + ((15 - g4) >> 2) + ((15 - g4) >> 3);
					b_filt = b4 + ((15 - b4) >> 2) + ((15 - b4) >> 3);

					if (r_filt > 15) r_filt = 15;
					if (g_filt > 15) g_filt = 15;
					if (b_filt > 15) b_filt = 15;
			  end

            4'b0100: begin // Darken image (~30%)
					 r_filt = r4 - ((r4 >> 2) + (r4 >> 3)); // ~62.5% brightness
					 g_filt = g4 - ((g4 >> 2) + (g4 >> 3));
					 b_filt = b4 - ((b4 >> 2) + (b4 >> 3));
				end
				4'b0011: begin //Sigma Filter (Red Tint)
					r_filt = r4 + ((15 - r4) >> 2) + ((15 - r4) >> 3);
					g_filt = g4;
					b_filt = b4;

					if (r_filt > 15) r_filt = 15;
			  end

            4'b1000: begin // Greyscale
                logic [5:0] avg;
                avg = (r4 + g4 + b4) / 3;
                r_filt = avg[3:0];
                g_filt = avg[3:0];
                b_filt = avg[3:0];
            end
            // 4'b1111: begin // 5x5 Gaussian blur
            // int sum_r = 0, sum_g = 0, sum_b = 0;
            //     int weight_sum = 0;
            //     int kx, ky;
            //     int kernel[0:4][0:4] = '{
            //         '{1, 4, 7, 4, 1},
            //         '{4,16,26,16,4},
            //         '{7,26,41,26,7},
            //         '{4,16,26,16,4},
            //         '{1, 4, 7, 4, 1}
            //     };

            //     for (ky = -2; ky <= 2; ky++) begin
            //         for (kx = -2; kx <= 2; kx++) begin
            //             int xx = src_x + kx;
            //             int yy = src_y + ky;
            //             if (xx >= 0 && xx < SRC_WIDTH && yy >= 0 && yy < SRC_HEIGHT) begin
            //                 logic [NumColourBits-1:0] pix = wolf_face[yy*SRC_WIDTH + xx];
            //                 logic [3:0] r = pix[11:8];
            //                 logic [3:0] g = pix[7:4];
            //                 logic [3:0] b = pix[3:0];
            //                 sum_r += r * kernel[ky+2][kx+2];
            //                 sum_g += g * kernel[ky+2][kx+2];
            //                 sum_b += b * kernel[ky+2][kx+2];
            //                 weight_sum += kernel[ky+2][kx+2];
            //             end
            //         end
            //     end
            //     // Normalize and clamp to 4 bits
            //     r_filt = (sum_r / weight_sum) > 15 ? 15 : (sum_r / weight_sum);
            //     g_filt = (sum_g / weight_sum) > 15 ? 15 : (sum_g / weight_sum);
            //     b_filt = (sum_b / weight_sum) > 15 ? 15 : (sum_b / weight_sum);
            // end
            default: begin
            // Default: no change
                r_filt = r4;
                g_filt = g4;
                b_filt = b4;
            end
        endcase
    end

    // Convert to 10-bit for VGA output
   wire [9:0] red_10   = {r_filt, r_filt, r_filt[3:2]};
	wire [9:0] green_10 = {g_filt, g_filt, g_filt[3:2]};
	wire [9:0] blue_10  = {b_filt, b_filt, b_filt[3:2]};


    assign data = {red_10, green_10, blue_10};

    // Pixel counter logic
    always_comb begin
        if (reset) begin
            pixel_index_next = 0;
        end else if (valid && ready) begin
            if (pixel_index == NumPixels - 1)
                pixel_index_next = 0;
            else
                pixel_index_next = pixel_index + 1;
        end else begin
            pixel_index_next = pixel_index;
        end
    end

    always_ff @(posedge clk) begin
        if (reset)
            pixel_index <= 0;
        else
            pixel_index <= pixel_index_next;
    end

endmodule