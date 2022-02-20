// Copyright 2022 Douglas P. Fields, Jr.

// Based upon Analog Devices AN-1270
// ADV7513-Based Video Generators
// Listing 3, Generated Video Sync Generator Connected with Pattern Generator Top Module

// This implements HDMI output to the ADV7513 chip,
// which is assumed to have been initialized properly via I2C.
// It consists of two pieces:
// 1. A clock generator, which generates several signals:
//   Horizontal & Vertical Synce
//   Data Enable (during the displayed part of the video signal)
//   H/V count (where we are in a single frame, including sync & porch areas)
//   X/Y position (where we are in a displayable part)
//   This does not handle interlaced video (which I hope never to output).
// 2. A pattern generator, or in other words, the serial video signal.
//   This takes an input and generates a few different sample outputs.

// This does NOT implement ADV7513 interrupt handling.

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif


module top_sync_vg_pattern (
  input  logic        clk,
  input  logic        reset,
  
  // ADV7513 outputs
  output logic        adv7513_hs,  // HS output to ADV7513
  output logic        adv7513_vs,  // VS output to ADV7513
  output logic        adv7513_clk, // ADV7513: CLK out (not sure what it is for, it's just inverted clk
  output logic [23:0] adv7513_d,   // data (original AN-1270 had 36 bits)
  output logic        adv7513_de,  // ADV7513: Data Enable (during visible part of video signal)
  
  input  logic [7:0]  pattern      // Input to the pattern generator
);


// Desired mode
// Note that an appropriate pixel clock must be fed in here as "clk"
`define MODE_1080p
//`define MODE_720p


`ifdef MODE_1080p 
// FORMAT 16

// VESA Standard, DMT ID: 52h - CEA-861 1080p 1920x1080@60Hz
// Pixel Clock = 148.500 MHz
// Hor Freq = 67.500 kHz
// Ver Freq = 60.000 Hz
// H & V Sync Polarity = positive

/* Per AN-1270, you need to know:
- Total horizontal line length
- Horizontal front and back porch
- Horizontal sync pulse
- Total number of vertical lines
- Vertical front and back porch
- Vertical sync pulse
- HV offset
- Pixel clock frequency
*/

parameter V_TOTAL  = 12'd1125; // Ver Total Time (number of rows, including non-displayed)
parameter V_FP     = 12'd4;    // V Front Porch
parameter V_BP     = 12'd36;   // V Back Porch
parameter V_SYNC   = 12'd5;    // Ver Sync Time
// 1125 - 4 - 35 - 5 = 1080

parameter H_TOTAL    = 12'd2200; // Hor Total Time (number of columns, including non-displayed)
parameter H_FP       = 12'd88;   // H Front Porch (counts)
parameter H_BP       = 12'd148;  // H Back Porch (counts)
parameter H_SYNC     = 12'd44;   // Hor Sync Time
// 2200 - 88 - 148 - 44 = 1920

parameter HV_OFFSET = 12'd0;   // HV offset relates to the timing of the vsync within a column

parameter PATTERN_RAMP_STEP = 20'h0222;
`endif


`ifdef MODE_720p 
// FORMAT 4
// Pixel clock required: 74.250 MHz per VESA DMT

parameter V_TOTAL = 12'd750;
parameter V_FP    = 12'd5;
parameter V_BP    = 12'd20;
parameter V_SYNC  = 12'd5;
parameter H_TOTAL = 12'd1650;
parameter H_FP    = 12'd110;
parameter H_BP    = 12'd220;
parameter H_SYNC  = 12'd40;
parameter HV_OFFSET = 12'd0;
parameter PATTERN_RAMP_STEP = 20'h0333; // 20'hFFFFF / 1280 act_pixels per line = 20'h0333

`endif

///////////////////////////////////////////////////////////////////////////////

logic [11:0] x_out; // Displayable position output from sync generator (valid when de)
logic [11:0] y_out;

logic [7:0]  r_out; // Color output from pattern generator
logic [7:0]  g_out;
logic [7:0]  b_out;

logic de; // data enable out from the sync generator
logic vs; // vertical sync signal out from the sync generator
logic hs; // horizontal sync out from the sync generator

logic de_out; // data enable out from the PATTERN generator
logic vs_out; // vertical sync signal out from the PATTERN generator
logic hs_out; // horizontal sync out from the PATTERN generator


sync_vg #(.X_BITS(12), .Y_BITS(12)) sync_vg (
  .clk(clk),
  .reset(reset),
  .clk_out(), // inverted output clock - unconnected
  
  // Inputs to the sync generator
  .v_total(V_TOTAL),
  .v_fp(V_FP),
  .v_bp(V_BP),
  .v_sync(V_SYNC),
  .h_total(H_TOTAL),
  .h_fp(H_FP),
  .h_bp(H_BP),
  .h_sync(H_SYNC),
  .hv_offset(HV_OFFSET),
  
  // Our sync and count/pixel locations
  .vs_out(vs),
  .hs_out(hs),
  .de_out(de),
  .v_count_out(), // We don't use the counts
  .h_count_out(),
  .x_out(x_out),  // But we do use the pixel locations
  .y_out(y_out)
);

pattern_vg #(
  .B(8), // Bits per channel
  .X_BITS(12),
  .Y_BITS(12),
  .FRACTIONAL_BITS(12) // Number of fractional bits for ramp pattern
) pattern_vg (
  .clk(clk),
  .reset(reset),
  
  // Sync generator inputs
  .x    (x_out),
  .y    (y_out),
  .vn_in(vs),
  .hn_in(hs),
  .dn_in(de),
  
  // Info on the size
  .max_x(H_TOTAL - (H_FP + H_BP + H_SYNC)), // 1920
  .max_y(V_TOTAL - (V_FP + V_BP + V_SYNC)), // 1080
  
  // What pattern to generate
  .pattern(pattern),
  .ramp_step(PATTERN_RAMP_STEP),

  // Outputs (although the v/h/de are just passed through currently)
  .vn_out (vs_out),
  .hn_out (hs_out),
  .den_out(de_out),
  .r_out  (r_out),
  .g_out  (g_out),
  .b_out  (b_out)
);

// Not sure why the AN-1270 wants a negative clock output
assign adv7513_clk = ~clk;

// Register our outputs
always_ff @(posedge clk) begin
  adv7513_d[23:16] <= r_out;
  adv7513_d[15:8]  <= g_out;
  adv7513_d[ 7:0]  <= b_out;
  adv7513_hs       <= hs_out;
  adv7513_vs       <= vs_out;
  adv7513_de       <= de_out;
end

endmodule


`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// Restore the default_nettype to prevent side effects
// See: https://front-end-verification.blogspot.com/2010/10/implicit-net-declartions-in-verilog-and.html
// and: https://sutherland-hdl.com/papers/2006-SNUG-Boston_standard_gotchas_presentation.pdf
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif
