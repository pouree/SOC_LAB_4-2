// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)


`default_nettype wire
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
    parameter DELAYS=10,
    parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  wire  [`MPRJ_IO_PADS-1:0] io_in,
    output wire  [`MPRJ_IO_PADS-1:0] io_out,
    output wire[`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);

    wire clk;
    wire rst;
    assign clk = wb_clk_i;
    assign rst = wb_rst_i;

    // wire [`MPRJ_IO_PADS-1:0] io_in;
    // wire [`MPRJ_IO_PADS-1:0] io_out;
    // wire [`MPRJ_IO_PADS-1:0] io_oeb;

    // Address Decode
    wire [1:0] decode;
    assign decode = (wbs_adr_i[31:16]==16'h3800)? 2'd2:    // exmem_fir
                (wbs_adr_i[31:16]==16'h3000)? 2'd1: 2'd0;   // veilog_fir


    wire exmem_fir_request, verilog_fir_request;    // 3800 , 3000
    assign exmem_fir_request = wbs_cyc_i & wbs_stb_i & (decode == 2'd2);
    assign verilog_fir_request = wbs_cyc_i & wbs_stb_i & (decode == 2'd1);

    // write data to on_chip ram only when request_sig assert
    wire [31:0] ram_adr;
    wire [31:0] ram_data;
    wire [3:0] ram_we;
    wire ram_en;
    assign ram_adr = (exmem_fir_request==1'b1)? wbs_adr_i : 32'b0;
    assign ram_data = (exmem_fir_request==1'b1)? wbs_dat_i : 32'b0;
    assign ram_we = (exmem_fir_request==1'b1)?  ({4{wbs_we_i}} & wbs_sel_i) : 4'b0;
    assign ram_en = (exmem_fir_request==1'b1)? (wbs_cyc_i & wbs_stb_i): 1'b0;


    wire                     awready;       // o
    wire                     wready;        // o
    wire                     awvalid;       // i
    wire [(pADDR_WIDTH-1):0] awaddr;        // i
    wire                     wvalid;        // i 
    wire [(pDATA_WIDTH-1):0] wdata;         // i
    wire                     arready;       // o
    wire                     rready;        // i
    wire                     arvalid;       // i
    wire [(pADDR_WIDTH-1):0] araddr;        // i
    wire                     rvalid;        // o 
    wire [(pDATA_WIDTH-1):0] rdata;         // o
    wire                     ss_tvalid;     // i
    wire [(pDATA_WIDTH-1):0] ss_tdata;      // i
    wire                     ss_tlast;      // i
    wire                     ss_tready;     // o
    wire                     sm_tready;     // i
    wire                     sm_tvalid;     // o
    wire [(pDATA_WIDTH-1):0] sm_tdata;      // o
    wire                     sm_tlast;      // o
    wire                     axis_clk;
    wire                     axis_rst_n;

    // bram for tap RAM
    wire           [3:0]     tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;     // i

    // bram for data RAM
    wire            [3:0]    data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;   // i

    wire tap_in_request, data_length_in_request, ctrl_in_request;
    wire x_in_request, y_out_request;
    reg [(pDATA_WIDTH-1):0] data_length, data_length_count;
    
    assign axis_clk = wb_clk_i;
    assign axis_rst_n = !wb_rst_i;
    
    assign tap_in_request = (verilog_fir_request && wbs_adr_i[7:0] >= 8'h40 && wbs_adr_i[7:0] <= 8'h7F)? 1'b1:1'b0;
    assign x_in_request = (verilog_fir_request && wbs_adr_i[7:0] >= 8'h80 && wbs_adr_i[7:0] <= 8'h83)? 1'b1:1'b0;
    assign y_out_request = (verilog_fir_request && wbs_adr_i[7:0] >= 8'h84 && wbs_adr_i[7:0] <= 8'h87)? 1'b1:1'b0;
    assign data_length_in_request = (verilog_fir_request && wbs_adr_i[7:0] >= 8'h10 && wbs_adr_i[7:0] <= 8'h13)? 1'b1:1'b0;
    assign ctrl_in_request = (verilog_fir_request && wbs_adr_i[7:0] == 8'h00 )? 1'b1:1'b0;

    assign awvalid   = ((ctrl_in_request || tap_in_request ||  data_length_in_request) & wbs_we_i)? 1'b1 : 1'b0;
    assign awaddr    = ((ctrl_in_request || tap_in_request ||  data_length_in_request) & wbs_we_i)? wbs_adr_i : 0;

    assign wvalid    = ((ctrl_in_request || tap_in_request ||  data_length_in_request)  & wbs_we_i)? 1'b1 : 1'b0;
    assign wdata     = ((ctrl_in_request || tap_in_request ||  data_length_in_request)  & wbs_we_i) ? wbs_dat_i : 0;

    assign rready    = (!wbs_we_i & tap_in_request ) ? 1'b1 : 1'b0;
    assign arvalid   = (!wbs_we_i & tap_in_request ) ? 1'b1 : 1'b0;
    assign araddr    = (!wbs_we_i & tap_in_request ) ? wbs_adr_i : 0;

    assign ss_tlast  = (data_length_count==(data_length-1)) ? 1'b1 : 1'b0;
    assign ss_tvalid = (wbs_we_i & x_in_request) ? 1'b1 : 1'b0;
    assign ss_tdata  = (wbs_we_i & x_in_request) ? wbs_dat_i : 0;
    assign sm_tready = (verilog_fir_request) ? 1'b1 : 1'b0;

    wire verlog_fir_ack_o;
    reg exmem_fir_ack_o;
    wire [31:0] exmem_fir_o;

    assign verlog_fir_ack_o = (awready && wready) ? 1'b1 :
    	(rvalid) ? 1'b1 :
    	(data_length_in_request && awready) ? 1'b1 : 
        (ctrl_in_request && awready) ? 1'b1 :
        (sm_tvalid) ? 1'b1 :
        (y_out_request) ? 1'b1 : 1'b0;
        
    assign wbs_ack_o =  verlog_fir_ack_o | exmem_fir_ack_o;

    reg [(pDATA_WIDTH-1):0] data_y;

    assign wbs_dat_o = (exmem_fir_ack_o)? exmem_fir_o :
                    (y_out_request)? data_y : 
                    (verlog_fir_ack_o)? sm_tdata : 1'b0 ;

    always @ (posedge wb_clk_i) begin 
        if (wb_rst_i)
            data_y <= 0;
        else if (sm_tvalid)
            data_y <= sm_tdata;

    end

    always@(posedge wb_clk_i)begin
        if(wb_rst_i) begin
            data_length_count <= 0;		
        end
        else if(data_length_in_request) 
            data_length <= wbs_dat_i;
        
        else if(sm_tvalid==1) 
            data_length_count <= data_length_count + 1;
            
        else if (sm_tlast) 
            data_length_count <= 0;
    end

    reg [3:0] delay_cnt;   // delay = 10 (DELAYS) < 2^4
    always @ (posedge clk) begin 
        if (rst) begin
            exmem_fir_ack_o <= 0;
            delay_cnt <= 0;
        end
        else if (exmem_fir_request == 1'b1) begin 
            if (delay_cnt == DELAYS) begin
                exmem_fir_ack_o <= 1'b1;
                delay_cnt <= 0;            
            end
            else begin  
                exmem_fir_ack_o <= 1'b0;
                delay_cnt <= delay_cnt + 1 ;
            end
        end
        else begin 
            delay_cnt <= 0;
            exmem_fir_ack_o <= 1'b0;
        end
    end

wire [1:0] state;
wire ap_start_sig, ss_write_valid;
wire ctrl_tap_ready, ctrl_tap_valid;

fir verilog_fir(
        .awready(awready),          // o
        .wready(wready),            // o
        .awvalid(awvalid),          // i
        .awaddr(awaddr),            // i
        .wvalid(wvalid),            // i
        .wdata(wdata),              // i
        .arready(arready),          // o
        .rready(rready),            // i
        .arvalid(arvalid),          // i
        .araddr(araddr),            // i
        .rvalid(rvalid),            // o
        .rdata(rdata),              // o
        .ss_tvalid(ss_tvalid),      // i
        .ss_tdata(ss_tdata),        // i
        .ss_tlast(ss_tlast),        // i
        .ss_tready(ss_tready),      // o
        .sm_tready(sm_tready),      // i
        .sm_tvalid(sm_tvalid),      // o
        .sm_tdata(sm_tdata),        // o
        .sm_tlast(sm_tlast),        // o

        // ram for tap
        .tap_WE(tap_WE),            // o
        .tap_EN(tap_EN),            // o
        .tap_Di(tap_Di),            // o        
        .tap_Do(tap_Do),            // i
        .tap_A(tap_A),              // o

        // ram for data
        .data_WE(data_WE),          // o
        .data_EN(data_EN),          // o
        .data_Di(data_Di),          // o        
        .data_Do(data_Do),          // i
	    .data_A(data_A),            // o
	
        .axis_clk(axis_clk),
        .axis_rst_n(axis_rst_n),
        .state(state),
        .ap_start_sig(ap_start_sig),        
        .ctrl_tap_valid(ctrl_tap_valid),
        .ctrl_tap_ready(ctrl_tap_ready),
        .ss_write_valid(ss_write_valid)
    );             


bram exmem_bram(
    .CLK(clk),
    .WE0(ram_we),
    .EN0(ram_en),
    .Di0(wbs_dat_i),
    .Do0(exmem_fir_o),
    .A0(wbs_adr_i)
);

// RAM for tap
bram11 tap_RAM (
           .CLK(axis_clk),
           .WE(tap_WE),
           .EN(tap_EN),
           .Di(tap_Di),
           .Do(tap_Do),
           .A(tap_A)
       );

// RAM for data: choose bram11 or bram12
bram11 data_RAM(
           .CLK(axis_clk),
           .WE(data_WE),
           .EN(data_EN),
           .Di(data_Di),           
           .Do(data_Do),
           .A(data_A)
       );      


endmodule


`default_nettype wire
