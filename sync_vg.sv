// Copyright 2022 Douglas P. Fields, Jr.

// HDMI Sync Generator for ADV7513 HDMI Transmitter
//
// Generates H/V sync, data enable (true when displayable data).
// Also lets you know where you are in terms of counts (the full
// frequency range of a frame including sync, porch, etc.) and
// X/Y pixel position (only valid when DE).

// Based upon Analog Devices AN-1270: ADV7513-Based Video Generators
// Listing 1

// Differences from AN-1270
// 1. Translated to SystemVerilog
// 2. Remove interlaced support
// 3. Simplify and clarify the code compared to AN-1270
// 4. Add detailed comments describing what's going on

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// This doesn't work in Questa for some reason. vlog-2892 errors.
`default_nettype none // Disable implicit creation of undeclared nets
`endif

module sync_vg #(
  parameter X_BITS=12,
            Y_BITS=12
) (
  input  logic              clk,
  input  logic              reset,
  
  // The current video setting's timing information
  // See VESA Display Monitor Timing section 3 for details
  input  logic [Y_BITS-1:0] v_total, // Total vertical row counts
  input  logic [Y_BITS-1:0] v_fp,    // Vertical front porch (bottom)
  input  logic [Y_BITS-1:0] v_bp,    // Vertical pack porch (top)
  input  logic [Y_BITS-1:0] v_sync,  // Vertical sync time (top)
  input  logic [X_BITS-1:0] h_total, // Total horizontal column counts
  input  logic [X_BITS-1:0] h_fp,    // Horizontal front porch (right side)
  input  logic [X_BITS-1:0] h_bp,    // Horizontal back porch (left side)
  input  logic [X_BITS-1:0] h_sync,  // Horizontal sync time (left)
  input  logic [X_BITS-1:0] hv_offset, // NOT SURE - see below
  
  // Outputs
  output logic              vs_out, // Vertical Sync signal output
  output logic              hs_out, // Horizontal Sync signal output
  output logic              de_out, // Data Enable output (when the pixel would be visible)
  output logic [Y_BITS-1:0] v_count_out, // Full count out (including sync/porches)
  output logic [X_BITS-1:0] h_count_out,
  output logic [X_BITS-1:0] x_out, // Pixel # out (only valid when de_out is true)
  output logic [Y_BITS-1:0] y_out,
  output logic              clk_out // Inverted clock output (combinatoral)
);

// Where are we in our scan down/across the screen?
// These counts include the porches and the sync zones.
logic [X_BITS-1:0] h_count;
logic [Y_BITS-1:0] v_count;

// Not sure why the AN-1270 sends an inverted clock out
assign clk_out = ~clk;


// Horizontal counter:
// ALways counts up for the total horizontal count
always_ff @(posedge clk)
  if (reset)
    h_count <= 0;
  else if (h_count == h_total - 1)
    h_count <= 0;
  else
    h_count <= h_count + { {X_BITS-1{1'b0}}, 1'b1 };
    
// Vertical counter
// Counts up every time we are at the end of a horizontal line;
// resets to zero when we are also at the last vertical row.
always_ff @(posedge clk)
  if (reset)
    v_count <= 0;
  else if (h_count == h_total - 1) begin
    if (v_count == v_total - 1)
      v_count <= 0;
    else
      v_count <= v_count + { {Y_BITS-1{1'b0}}, 1'b1 };
  end

// Generate sync signals.
// Vertical sync: We're in the top-so-many counts/rows
// Horizontal sync: We're in the left so-many counts/columns
// Display Enable: when we are in the user visible area of the
// scree, after the sync and porch, and before the other porch
//
// Also output where we are in terms of counts and (displayable) pixels.
always_ff @(posedge clk)
  if (reset)
    { vs_out, hs_out, de_out } <= 3'b0;
    
  else begin
    // Are we in the displayable area? If so, then DE (data enable)
    de_out <= (v_count >= v_sync + v_bp) && (v_count <= v_total - v_fp - 1) &&
              (h_count >= h_sync + h_bp) && (h_count <= h_total - h_fp - 1);

    // The beginning h_sync counts are the horizontal sync pulse
    // of every line of output
    hs_out <= h_count < h_sync;

    // v_sync starts at the beginning (plus hv_offset columns)
    // and continues for v_sync rows (plus hv_offset columns)
    if (v_count == 0 && h_count == hv_offset)
      vs_out <= 1'b1;
    else if (v_count == v_sync && h_count == hv_offset)
      vs_out <= 1'b0;
      
    // H_COUNT_OUT and V_COUNT_OUT - the raw location
    // including porches, sync areas, etc.
    h_count_out <= h_count;
    v_count_out <= v_count;
      
    // X and Y coords – for a backend pattern generator
    x_out <= h_count - (h_sync + h_bp);
    y_out <= v_count - (v_sync + v_bp);
  end

endmodule

`ifdef IS_QUARTUS // Defined in Assignments -> Settings -> ... -> Verilog HDL Input
// Restore the default_nettype to prevent side effects
// See: https://front-end-verification.blogspot.com/2010/10/implicit-net-declartions-in-verilog-and.html
// and: https://sutherland-hdl.com/papers/2006-SNUG-Boston_standard_gotchas_presentation.pdf
`default_nettype wire // turn implicit nets on again to avoid side-effects
`endif

