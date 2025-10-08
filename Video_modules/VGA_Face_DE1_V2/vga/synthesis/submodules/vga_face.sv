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
    logic[3:0] filter_select;
    initial filter_select = 4'b1111;    // 0000 - No filter, 0001 - Invert, 0010 - Lighten, 0100 - Darken, 1000 - Greyscale, 1111 - Gaussian blur

    logic[3:0] r_filt, g_filt, b_filt;  // Filter colour channels


    // Line buffers for Gaussian Blur
    logic [11:0] linebuf0 [0:SRC_WIDTH-1];
    logic [11:0] linebuf1 [0:SRC_WIDTH-1];
    logic [11:0] linebuf2 [0:SRC_WIDTH-1];
    logic [11:0] linebuf3 [0:SRC_WIDTH-1];
    logic [11:0] linebuf4 [0:SRC_WIDTH-1];

    // Line buffer write pointer
    logic [9:0] src_x_reg; // Registered src_x to sync line buffer write
    always_ff @(posedge clk) begin
        if (reset)
            src_x_reg <= 0;
        else if (read_enable)
            src_x_reg <= src_x;
    end

    
    //Line buffer update on read_enable ####
    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < SRC_WIDTH; i++) begin
                linebuf0[i] <= 12'd0;
                linebuf1[i] <= 12'd0;
                linebuf2[i] <= 12'd0;
                linebuf3[i] <= 12'd0;
                linebuf4[i] <= 12'd0;
            end
        end else if (read_enable) begin
            // Shift lines upward, new pixel goes into linebuf4 at src_x position
            // This simulates a FIFO of 5 lines for 5x5 window
            // Shift line buffers up
            for (i = 0; i < SRC_WIDTH; i++) begin
                linebuf0[i] <= linebuf1[i];
                linebuf1[i] <= linebuf2[i];
                linebuf2[i] <= linebuf3[i];
                linebuf3[i] <= linebuf4[i];
            end
            // Insert new pixel to linebuf4 at src_x position
            linebuf4[src_x_reg] <= current_pixel;
        end
    end

    // Gaussian blur task
    task automatic gaussian_blur_5x5(
        input logic [11:0] linebuf0_in [0:SRC_WIDTH-1],
        input logic [11:0] linebuf1_in [0:SRC_WIDTH-1],
        input logic [11:0] linebuf2_in [0:SRC_WIDTH-1],
        input logic [11:0] linebuf3_in [0:SRC_WIDTH-1],
        input logic [11:0] linebuf4_in [0:SRC_WIDTH-1],
        input logic [9:0] x_pos,
        output logic [3:0] r_out,
        output logic [3:0] g_out,
        output logic [3:0] b_out
    );
        // Gaussian kernel
        int kernel [0:4][0:4] = '{'{1, 4, 7, 4, 1},
                                  '{4,16,26,16,4},
                                  '{7,26,41,26,7},
                                  '{4,16,26,16,4},
                                  '{1, 4, 7, 4, 1}};

        int r_sum, g_sum, b_sum;
        int xx, yy;
        int weight_sum = 273;
        logic [11:0] pix;
        logic [3:0] r;
        logic [3:0] g;
        logic [3:0] b;
        int tmp_r;
        int tmp_g;
        int tmp_b;

        r_sum = 0;
        g_sum = 0;
        b_sum = 0;


        for (yy = 0; yy < 5; yy++) begin
            for (xx = 0; xx < 5; xx++) begin
                int pos_x = x_pos + xx - 2; // center at x_pos
                int pos_y = yy; // line buffer index (0-4)

                // Boundary check (clamp edges)
                if (pos_x < 0) pos_x = 0;
                else if (pos_x >= SRC_WIDTH) pos_x = SRC_WIDTH - 1;

                // Select pixel from corresponding line buffer
                
                case (pos_y)
                    0: pix = linebuf0_in[pos_x];
                    1: pix = linebuf1_in[pos_x];
                    2: pix = linebuf2_in[pos_x];
                    3: pix = linebuf3_in[pos_x];
                    4: pix = linebuf4_in[pos_x];
                    default: pix = 12'd0;
                endcase

                // Extract channels
                r = pix[11:8];
                g = pix[7:4];
                b = pix[3:0];

                r_sum += kernel[yy][xx] * r;
                g_sum += kernel[yy][xx] * g;
                b_sum += kernel[yy][xx] * b;
            end
        end

        // // Divide by weight_sum (273)
        // r_out = (r_sum + (weight_sum/2)) / weight_sum; // rounding
        // g_out = (g_sum + (weight_sum/2)) / weight_sum;
        // b_out = (b_sum + (weight_sum/2)) / weight_sum;

        // // Clamp outputs (should fit in 4 bits)
        // if (r_out > 15) r_out = 15;
        // if (g_out > 15) g_out = 15;
        // if (b_out > 15) b_out = 15;
                // Divide by weight_sum (273) -- compute into wide ints, then clamp, then assign


        tmp_r = (r_sum + (weight_sum/2)) / weight_sum; //##### FIX: compute in int
        tmp_g = (g_sum + (weight_sum/2)) / weight_sum;
        tmp_b = (b_sum + (weight_sum/2)) / weight_sum;

        // Clamp in wide integers
        if (tmp_r < 0) tmp_r = 0;
        if (tmp_g < 0) tmp_g = 0;
        if (tmp_b < 0) tmp_b = 0;

        if (tmp_r > 15) tmp_r = 15; //##### FIX: clamp before assigning to 4 bits
        if (tmp_g > 15) tmp_g = 15;
        if (tmp_b > 15) tmp_b = 15;

        // Assign the final (clamped) values to the 4-bit outputs
        r_out = tmp_r[3:0]; //##### FIX: assign clipped value
        g_out = tmp_g[3:0];
        b_out = tmp_b[3:0];

    endtask

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
            4'b1111: begin // 5x5 Gaussian blur
                gaussian_blur_5x5(linebuf0, linebuf1, linebuf2, linebuf3, linebuf4, src_x_reg, r_filt, g_filt, b_filt);
            end
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