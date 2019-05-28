
//  Xilinx UltraRAM True Dual Port Mode.  This code implements
//  a parameterizable UltraRAM block with write/read on both ports in
//  No change behavior on both the ports . The behavior of this RAM is
//  when data is written, the output of RAM is unchanged w.r.t each port.
//  Only when write is inactive data corresponding to the address is
//  presented on the output port.
//

module uram_reset #(
  parameter RAM_WIDTH = 18,
  parameter RAM_DEPTH = 1024,
  parameter PIPELINES = 3
) (
  if_ram.sink a,
  if_ram.sink b
);

if_ram #(.RAM_WIDTH(a.RAM_WIDTH), .RAM_DEPTH(a.RAM_DEPTH)) if_ram_a(.i_clk(a.i_clk), .i_rst(a.i_rst));

logic reset_done;
logic [$clog2(RAM_WIDTH)-1:0] addr;

always_ff @ (posedge a.i_clk) begin
  if (a.i_rst) begin
    reset_done <= 0;
    addr <= 0;
  end else begin
    addr <= addr + 1;
    if (&addr)
      reset_done <= 1;
  end
end

always_comb begin
  if_ram_a.a =  reset_done ? a.a : addr;
  if_ram_a.en = a.en;
  if_ram_a.we = reset_done ? a.we : 1'd1;
  if_ram_a.re = a.re;
  if_ram_a.d =  reset_done ? a.d : {RAM_WIDTH{1'd0}};
  a.q = if_ram_a.q;
end

uram #(
  .RAM_WIDTH ( RAM_WIDTH ),
  .RAM_DEPTH ( RAM_DEPTH ),
  .PIPELINES ( PIPELINES )
)
uram_instance (
  .a( if_ram_a ),
  .b( b )
);

endmodule

module uram #(
  parameter RAM_WIDTH = 18,
  parameter RAM_DEPTH = 1024,
  parameter PIPELINES = 3
) (
  if_ram.sink a,
  if_ram.sink b
);

// Check RAM sizes match the interface
initial begin
  assert ($bits(a.d) == RAM_WIDTH) else $fatal(1, "%m %t ERROR: bram RAM_WIDTH (%d) does not match interface a (%d)", $time, RAM_WIDTH, $bits(a.d));
  assert ($bits(a.a) == $clog2(RAM_DEPTH)) else $fatal(1, "%m %t ERROR: bram $clog2(RAM_DEPTH) (%d) does not match interface a (%d)", $time, $clog2(RAM_DEPTH), $bits(a.a));
  assert ($bits(b.d) == RAM_WIDTH) else $fatal(1, "%m %t ERROR: bram RAM_WIDTH (%d) does not match interface b (%d)", $time, RAM_WIDTH, $bits(b.d));
  assert ($bits(b.a) == $clog2(RAM_DEPTH)) else $fatal(1, "%m %t ERROR: bram $clog2(RAM_DEPTH) (%d) does not match interface b (%d)", $time, $clog2(RAM_DEPTH), $bits(b.a));
end

xilinx_ultraram_true_dual_port #(
  .AWIDTH ( $clog2(RAM_DEPTH) ),
  .DWIDTH ( RAM_WIDTH ),
  .NBPIPE ( PIPELINES )
)
uram_instance (
  .addra(a.a),
  .addrb(b.a),
  .dina(a.d),
  .dinb(b.d),
  .clk(a.i_clk),
  .wea(a.we),
  .web(b.we),
  .mem_ena(a.en),
  .mem_enb(b.en),
  .rsta(a.i_rst),
  .rstb(b.i_rst),
  .regcea(a.re),
  .regceb(b.re),
  .douta(a.q),
  .doutb(b.q)
 );

endmodule

module xilinx_ultraram_true_dual_port #(
  parameter AWIDTH = 12,  // Address Width
  parameter DWIDTH = 72,  // Data Width
  parameter NBPIPE = 3    // Number of pipeline Registers
 ) (
  input clk,                    // Clock
  // Port A
  input rsta,                   // Reset
  input wea,                    // Write Enable
  input regcea,                 // Output Register Enable
  input mem_ena,                // Memory Enable
  input [DWIDTH-1:0] dina,      // Data Input
  input [AWIDTH-1:0] addra,     // Address Input
  output reg [DWIDTH-1:0] douta,// Data Output

  // Port B
  input rstb,                   // Reset
  input web,                    // Write Enable
  input regceb,                 // Output Register Enable
  input mem_enb,                // Memory Enable
  input [DWIDTH-1:0] dinb,      // Data Input
  input [AWIDTH-1:0] addrb,     // Address Input
  output reg [DWIDTH-1:0] doutb // Data Output
 );

(* ram_style = "ultra" *)
reg [DWIDTH-1:0] mem[(1<<AWIDTH)-1:0];        // Memory Declaration

reg [DWIDTH-1:0] memrega;
reg [DWIDTH-1:0] mem_pipe_rega[NBPIPE-1:0];    // Pipelines for memory
reg mem_en_pipe_rega[NBPIPE:0];                // Pipelines for memory enable

reg [DWIDTH-1:0] memregb;
reg [DWIDTH-1:0] mem_pipe_regb[NBPIPE-1:0];    // Pipelines for memory
reg mem_en_pipe_regb[NBPIPE:0];                // Pipelines for memory enable

integer          i;

// RAM : Read has one latency, Write has one latency as well.
always @ (posedge clk)
begin
 if(mem_ena)
  begin
   if(wea)
    mem[addra] <= dina;
   else
    memrega <= mem[addra];
  end
end
// The enable of the RAM goes through a pipeline to produce a
// series of pipelined enable signals required to control the data
// pipeline.
always @ (posedge clk)
begin
mem_en_pipe_rega[0] <= mem_ena;
 for (i=0; i<NBPIPE; i=i+1)
  mem_en_pipe_rega[i+1] <= mem_en_pipe_rega[i];
end

// RAM output data goes through a pipeline.
always @ (posedge clk)
begin
 if (mem_en_pipe_rega[0])
  mem_pipe_rega[0] <= memrega;
end

always @ (posedge clk)
begin
 for (i = 0; i < NBPIPE-1; i = i+1)
  if (mem_en_pipe_rega[i+1])
    mem_pipe_rega[i+1] <= mem_pipe_rega[i];
end

// Final output register gives user the option to add a reset and
// an additional enable signal just for the data ouptut
always @ (posedge clk)
begin
 if (rsta)
  douta <= 0;
 else if (mem_en_pipe_rega[NBPIPE] && regcea)
  douta <= mem_pipe_rega[NBPIPE-1];
end

// RAM : Read has one latency, Write has one latency as well.
always @ (posedge clk)
begin
 if(mem_enb)
  begin
   if(web)
    mem[addrb] <= dinb;
   else
    memregb <= mem[addrb];
  end
end
// The enable of the RAM goes through a pipeline to produce a
// series of pipelined enable signals required to control the data
// pipeline.
always @ (posedge clk)
begin
mem_en_pipe_regb[0] <= mem_enb;
 for (i=0; i<NBPIPE; i=i+1)
  mem_en_pipe_regb[i+1] <= mem_en_pipe_regb[i];
end

// RAM output data goes through a pipeline.
always @ (posedge clk)
begin
 if (mem_en_pipe_regb[0])
  mem_pipe_regb[0] <= memregb;
end

always @ (posedge clk)
begin
 for (i = 0; i < NBPIPE-1; i = i+1)
  if (mem_en_pipe_regb[i+1])
    mem_pipe_regb[i+1] <= mem_pipe_regb[i];
end

// Final output register gives user the option to add a reset and
// an additional enable signal just for the data ouptut
always @ (posedge clk)
begin
 if (rsta)
  doutb <= 0;
 else if (mem_en_pipe_regb[NBPIPE] && regceb)
  doutb <= mem_pipe_regb[NBPIPE-1];
end
endmodule

