// sevenseg_display8.sv
// 8-digit 7-seg: [HEX7..HEX0] = [S][R][d][b][thousands][hundreds][tens][ones]
module sevenseg_display8 #(
  parameter bit ACTIVE_LOW = 1,          // 1 = active-low segments (DE2-115)
  parameter bit BLANK_LEADING_ZEROS = 1  // 1 = blank leading zeros in the 4-digit value
)(
  input  logic [15:0] value,             // 0..9999 (your SNR is 0..99; that's fine)
  output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);

  // Digit to segments (a..g). Active-low patterns here; invert later if needed.
  function automatic logic [6:0] seg_digit(input logic [3:0] d);
    case (d)
      4'd0: seg_digit = 7'b100_0000;
      4'd1: seg_digit = 7'b111_1001;
      4'd2: seg_digit = 7'b010_0100;
      4'd3: seg_digit = 7'b011_0000;
      4'd4: seg_digit = 7'b001_1001;
      4'd5: seg_digit = 7'b001_0010;
      4'd6: seg_digit = 7'b000_0010;
      4'd7: seg_digit = 7'b111_1000;
      4'd8: seg_digit = 7'b000_0000;
      4'd9: seg_digit = 7'b001_0000;
      default: seg_digit = 7'b111_1111; // blank
    endcase
  endfunction

  // Limited letters
  localparam logic [6:0] SEG_S    = 7'b001_0010; // 'S' (approx using 7-seg)
  localparam logic [6:0] SEG_R    = 7'b010_1111; // 'r' (lowercase-ish); change if you prefer 'R'
  localparam logic [6:0] SEG_D    = 7'b010_0001; // 'd'
  localparam logic [6:0] SEG_B    = 7'b000_0011; // 'b'
  localparam logic [6:0] SEG_BLNK = 7'b111_1111; // blank

  function automatic logic [6:0] pol(input logic [6:0] raw);
    pol = (ACTIVE_LOW) ? raw : ~raw;
  endfunction

  // Split value into digits
  logic [3:0] thousands, hundreds, tens, ones;
  always_comb begin
    thousands = (value / 1000) % 10;
    hundreds  = (value / 100 ) % 10;
    tens      = (value / 10  ) % 10;
    ones      = (value       ) % 10;
  end

  // Optional blanking of leading zeros on the 4-digit numeric field
  logic [6:0] seg_thou, seg_hund, seg_tens, seg_ones;
  always_comb begin
    seg_thou = seg_digit(thousands);
    seg_hund = seg_digit(hundreds);
    seg_tens = seg_digit(tens);
    seg_ones = seg_digit(ones);

    if (BLANK_LEADING_ZEROS) begin
      if (thousands == 0) begin
        seg_thou = SEG_BLNK;
        if (hundreds == 0) begin
          seg_hund = SEG_BLNK;
          if (tens == 0) begin
            // For values 0..9, keep tens blank and show just ones
            seg_tens = SEG_BLNK;
          end
        end
      end
    end
  end

  // Assign to physical digits (left→right: HEX7..HEX0). Swap if your board order differs.
  assign HEX7 = pol(SEG_S);
  assign HEX6 = pol(SEG_R);
  assign HEX5 = pol(SEG_D);
  assign HEX4 = pol(SEG_B);
  assign HEX3 = pol(seg_thou);
  assign HEX2 = pol(seg_hund);
  assign HEX1 = pol(seg_tens);
  assign HEX0 = pol(seg_ones);

endmodule
