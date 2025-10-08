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
            wolf_face_q   <= wolf_face[src_pixel_index];
            colour_face_q <= colour_face[src_pixel_index];
            p2_face_q     <= p2_face[src_pixel_index];
        end
    end

    logic [NumColourBits-1:0] current_pixel;
    face_t face_sel;

    always_comb face_sel = face_t'(face_select);

    always_comb begin
        case(face_sel)
            Wolf:    current_pixel = wolf_face_q;
            Colour:  current_pixel = colour_face_q;
            P2:      current_pixel = p2_face_q;
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

    logic [3:0] filter_select;
    initial filter_select = 4'b1111;    // 1111 = Gaussian blur

    logic[3:0] r_filt, g_filt, b_filt;  // Filtered color channels

    //##### Shift-register line buffers for pipelined Gaussian blur (5 lines)
    logic [11:0] linebuf0 [0:SRC_WIDTH-1];
    logic [11:0] linebuf1 [0:SRC_WIDTH-1];
    logic [11:0] linebuf2 [0:SRC_WIDTH-1];
    logic [11:0] linebuf3 [0:SRC_WIDTH-1];
    logic [11:0] linebuf4 [0:SRC_WIDTH-1];

    logic [7:0] shift_ptr; //##### Horizontal shift pointer for line buffers

    integer i;
    always_ff @(posedge clk) begin
        if (reset) begin
            shift_ptr <= 0;
            for (i=0; i<SRC_WIDTH; i=i+1) begin
                linebuf0[i] <= 12'd0; //##### zero-initialize buffers
                linebuf1[i] <= 12'd0;
                linebuf2[i] <= 12'd0;
                linebuf3[i] <= 12'd0;
                linebuf4[i] <= 12'd0;
            end
        end else if (read_enable) begin
            //##### Shift pixel down the line buffers at shift_ptr position
            linebuf0[shift_ptr] <= linebuf1[shift_ptr];
            linebuf1[shift_ptr] <= linebuf2[shift_ptr];
            linebuf2[shift_ptr] <= linebuf3[shift_ptr];
            linebuf3[shift_ptr] <= linebuf4[shift_ptr];
            linebuf4[shift_ptr] <= current_pixel;

            shift_ptr <= (shift_ptr == SRC_WIDTH-1) ? 0 : shift_ptr + 1;
        end
    end

    //##### Pipelined Gaussian blur for 5x5 window
    int kernel [0:4][0:4] = '{
        '{1, 4, 7, 4, 1},
        '{4,16,26,16,4},
        '{7,26,41,26,7},
        '{4,16,26,16,4},
        '{1, 4, 7, 4,1}
    };
    int weight_sum = 273;
    int r_sum, g_sum, b_sum;
    int xx, yy;
    int pos_x;
    logic [11:0] pix;
    logic [3:0] r, g, b;

    always_ff @(posedge clk) begin
        case(filter_select)
            4'b1111: begin //##### Gaussian blur
                r_sum = 0;
                g_sum = 0;
                b_sum = 0;

                for (yy=0; yy<5; yy=yy+1) begin
                    for (xx=0; xx<5; xx=xx+1) begin
                        pos_x = shift_ptr + xx - 2;
                        if (pos_x < 0) pos_x = 0;
                        else if (pos_x >= SRC_WIDTH) pos_x = SRC_WIDTH-1;

                        case(yy)
                            0: pix = linebuf0[pos_x];
                            1: pix = linebuf1[pos_x];
                            2: pix = linebuf2[pos_x];
                            3: pix = linebuf3[pos_x];
                            4: pix = linebuf4[pos_x];
                        endcase

                        r = pix[11:8];
                        g = pix[7:4];
                        b = pix[3:0];

                        //##### Shift-add approximations
                        case(kernel[yy][xx])
                            1:   begin r_sum += r; g_sum += g; b_sum += b; end
                            4:   begin r_sum += r<<2; g_sum += g<<2; b_sum += b<<2; end
                            7:   begin r_sum += (r<<2)+r; g_sum += (g<<2)+g; b_sum += (b<<2)+b; end
                            16:  begin r_sum += r<<4; g_sum += g<<4; b_sum += b<<4; end
                            26:  begin r_sum += (r<<4)+(r<<3)+(r<<1); g_sum += (g<<4)+(g<<3)+(g<<1); b_sum += (b<<4)+(b<<3)+(b<<1); end
                            41:  begin r_sum += (r<<5)+(r<<3)+r; g_sum += (g<<5)+(g<<3)+g; b_sum += (b<<5)+(b<<3)+b; end
                        endcase
                    end
                end

                r_filt <= (r_sum + weight_sum/2)/weight_sum;
                g_filt <= (g_sum + weight_sum/2)/weight_sum;
                b_filt <= (b_sum + weight_sum/2)/weight_sum;
            end
            default: begin
                r_filt <= r4;
                g_filt <= g4;
                b_filt <= b4;
            end
        endcase
    end

    // Convert to 10-bit VGA
    wire [9:0] red_10   = {r_filt, r_filt, r_filt[3:2]};
    wire [9:0] green_10 = {g_filt, g_filt, g_filt[3:2]};
    wire [9:0] blue_10  = {b_filt, b_filt, b_filt[3:2]};
    assign data = {red_10, green_10, blue_10};

    // Pixel counter
    always_comb begin
        if (reset) pixel_index_next = 0;
        else if (valid && ready) pixel_index_next = (pixel_index==NumPixels-1)?0:pixel_index+1;
        else pixel_index_next = pixel_index;
    end
    always_ff @(posedge clk) begin
        if (reset) pixel_index <= 0;
        else pixel_index <= pixel_index_next;
    end

endmodule
