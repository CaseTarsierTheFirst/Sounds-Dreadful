module vga_face (
    input  logic        clk,             
    input  logic        reset,           
    input  logic [1:0]  face_select,     // 0: wolf 1: Troll 2: P2

    // Avalon-ST Interface:
    output logic [29:0] data,            // Data output to VGA (10 bits per RGB)
    output logic        startofpacket,   
    output logic        endofpacket,     
    output logic        valid,           
    input  logic        ready            
);

    typedef enum logic [1:0] {Wolf=2'd0, P2=2'd1, Troll=2'd2} face_t;

    localparam VGA_WIDTH  = 640;
    localparam VGA_HEIGHT = 480;
    localparam SRC_WIDTH  = 160;
    localparam SRC_HEIGHT = 120;
    localparam NumPixels  = VGA_WIDTH * VGA_HEIGHT;
    localparam NumColourBits = 12; // 4 bits per R, G, B

    // Image ROMs (160x120, 4 bits per channel)
    (* ram_init_file = "wolf.mif" *)   logic [NumColourBits-1:0] wolf_face   [0: SRC_WIDTH*SRC_HEIGHT-1];
    (* ram_init_file = "troll.mif" *) logic [NumColourBits-1:0] troll_face [0: SRC_WIDTH*SRC_HEIGHT-1];
    (* ram_init_file = "p2.mif" *)    logic [NumColourBits-1:0] p2_face    [0: SRC_WIDTH*SRC_HEIGHT-1];

    `ifdef VERILATOR
    initial begin
        $readmemh("wolf.hex", wolf_face);
        $readmemh("troll.hex", troll_face);
        $readmemh("p2.hex", p2_face);
    end
    `endif

    logic [18:0] pixel_index = 0, pixel_index_next;
    logic [NumColourBits-1:0] wolf_face_q, troll_face_q, p2_face_q;
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
            troll_face_q <= troll_face[src_pixel_index];
            p2_face_q    <= p2_face[src_pixel_index];
        end
    end

    logic [NumColourBits-1:0] current_pixel;
    face_t face_sel;

    always_comb face_sel = face_t'(face_select);

    always_comb begin
        case(face_sel)
            Wolf:   current_pixel = wolf_face_q;
            Troll:  current_pixel = troll_face_q;
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

    wire [9:0] red_10   = { r4, r4, 2'b00 };   // 4 bits → 8 bits then pad 2 zeros
    wire [9:0] green_10 = { g4, g4, 2'b00 };
    wire [9:0] blue_10  = { b4, b4, 2'b00 };

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
