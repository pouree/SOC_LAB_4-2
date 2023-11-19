//`timescale 1ns/1ns

module fir
       #(  parameter pADDR_WIDTH = 12,
           parameter pDATA_WIDTH = 32,
           parameter Tape_Num    = 11
        )
       (
           output  wire                     awready,
           output  wire                     wready,
           input   wire                     awvalid,
           input   wire [(pADDR_WIDTH-1):0] awaddr,
           input   wire                     wvalid,
           input   wire [(pDATA_WIDTH-1):0] wdata,
           output  wire                     arready,
           input   wire                     rready,
           input   wire                     arvalid,
           input   wire [(pADDR_WIDTH-1):0] araddr,
           output  wire                     rvalid,
           output  wire [(pDATA_WIDTH-1):0] rdata,
           input   wire                     ss_tvalid,
           input   wire [(pDATA_WIDTH-1):0] ss_tdata,
           input   wire                     ss_tlast,
           output  wire                     ss_tready,
           input   wire                     sm_tready,
           output  wire                     sm_tvalid,
           output  wire [(pDATA_WIDTH-1):0] sm_tdata,
           output  wire                     sm_tlast,

           // bram for tap RAM
           output  wire           [3:0]     tap_WE,
           output  wire                     tap_EN,
           output  wire [(pDATA_WIDTH-1):0] tap_Di,
           output  wire [(pADDR_WIDTH-1):0] tap_A,
           input   wire [(pDATA_WIDTH-1):0] tap_Do,

           // bram for data RAM
           output  wire            [3:0]    data_WE,
           output  wire                     data_EN,
           output  wire [(pDATA_WIDTH-1):0] data_Di,
           output  wire [(pADDR_WIDTH-1):0] data_A,
           input   wire [(pDATA_WIDTH-1):0] data_Do,

           input   wire                     axis_clk,
           input   wire                     axis_rst_n,
           output  reg      [1:0]           state,
           output  wire                     ss_write_valid,
           output  reg                      ap_start_sig,
           output  wire                     ctrl_tap_valid,
           output  wire                     ctrl_tap_ready        

       );
// write your code here!

// state declare
parameter ap_idle = 0;
parameter ap_start = 1;
parameter ap_done = 2;

//reg [1:0] state;

// AXIS_Stream write declare
reg     ss_tready_reg;
reg     ss_finish_reg;
wire    ss_finish;
reg     data_EN_sw_reg;
reg     data_EN_sr_reg;
reg     data_EN_r_d;
wire    stream_prepared;
//reg     ap_start_sig;

reg [pADDR_WIDTH-1:0] data_WA_reg;
reg [3:0]             data_WE_reg;
wire[pADDR_WIDTH-1:0] data_WA;

assign data_WE = data_WE_reg ;
assign ss_tready = ss_tready_reg;

assign data_WA = data_WA_reg;
assign data_Di = (state == ap_start) ? ss_tdata : 0;

//wire                   ss_write_valid;
wire [3:0]             ss_count;
reg [3:0]              ss_count_reg;
assign ss_count = ss_count_reg;

reg stream_prepared_reg;
assign stream_prepared = stream_prepared_reg;

reg     ss_read_valid_reg;
wire    ss_read_valid;
assign  ss_read_valid = ss_read_valid_reg;

assign  ss_finish = ss_finish_reg;

reg [pADDR_WIDTH-1:0] data_RA_reg;
wire [pADDR_WIDTH-1:0] data_RA;
assign data_RA = ctrl_data_addr;
assign data_EN = data_EN_sw_reg | data_EN_r_d;

always@(posedge axis_clk)
begin
    data_EN_r_d <= data_EN_sr_reg;
end

assign data_A =(data_EN_sw_reg) ? data_WA :
       (data_EN_sr_reg) ? data_RA : 0;

reg sm_tvalid_reg;
assign sm_tvalid = sm_tvalid_reg;

reg  [pDATA_WIDTH-1:0]  sm_tdata_reg;
assign  sm_tdata = sm_tdata_reg;
reg     sm_tlast_reg;
assign  sm_tlast = sm_tlast_reg;
assign ss_write_valid = ~ ss_read_valid;

reg ctrl_tap_ready_reg;
reg ctrl_rst_n;
reg tap_EN_r_d;
reg tap_EN_sr_reg;
//wire ctrl_tap_ready;
//wire ctrl_tap_valid;
wire ffen;
wire sel;

wire [pADDR_WIDTH-1:0]       tap_RA_sr;
wire [pADDR_WIDTH-1:0]       tap_RA_lr;

wire [pADDR_WIDTH-1:0]      ctrl_tap_addr;
wire [pADDR_WIDTH-1:0]      ctrl_data_addr;

assign tap_RA_lr = (araddr-12'h40);
assign tap_RA_sr = ctrl_tap_addr;

// state
always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        state <= ap_idle;
        ctrl_rst_n <= 0;
    end
    else
    begin
        case(state)
            ap_idle:
            begin
                if(ap_start_sig && stream_prepared)
                begin
                    state <= ap_start;
                    ctrl_rst_n <= 1;
                end                    
                sm_tlast_reg <= 0;
            end

            ap_start:
            begin
                if(ss_tlast && sm_tlast)
                    state <= ap_done;

                if(ss_tlast  && !ctrl_tap_valid)
                    sm_tlast_reg <= 1;
                else
                    sm_tlast_reg <= 0;
            end
            
            ap_done:
            begin
            	state <= ap_idle;
            	sm_tlast_reg <= 0;       	   
                ctrl_rst_n <= 0;         
            end
            
            default: 
           	    state <= ap_idle;
            
        endcase
    end
end

// AXIS_Stream write

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        ss_tready_reg <= 0;
        ss_count_reg <= 0;
        ss_read_valid_reg <= 0;

        data_WA_reg <= 0;
        stream_prepared_reg <= 0;
    
    end
    else
    begin
        if (ss_tvalid && !ss_tready)
        begin
            case(state)
                ap_idle:
                begin
                    ss_read_valid_reg <= 0;

                    if((ss_count <= Tape_Num - 1) && !stream_prepared)
                    begin
                        data_WE_reg <= 4'b1111;
                        data_EN_sw_reg <= 1;

                        data_WA_reg <= (ss_count == 0) ? 0:data_WA_reg + 4;
                        ss_count_reg <= ss_count_reg + 1;

                    end
                    else
                    begin
                        stream_prepared_reg <= 1;
                        ss_count_reg <= 4'd10;

                        data_EN_sw_reg <= 0;
                        data_WE_reg <= 0;
                    end
                end

                ap_start:
                begin
                    if(ss_write_valid)
                    begin                        
                        data_WE_reg <= 4'b1111;
                        data_EN_sw_reg <= 1;
                        data_WA_reg <= (ss_count == 4'd10) ? 0 :data_WA_reg + 4;
                        ss_count_reg <=(ss_count == 4'd10) ? 0 :ss_count_reg + 1;
                        ss_read_valid_reg <= 1;
                        ss_tready_reg <= 1;

                    end
                    else if (sm_tvalid)
                        ss_read_valid_reg <= 0;
                    else
                    begin
                        data_WE_reg <= 0;
                        ss_tready_reg <= 0;

                    end
                end
            endcase
        end
        else
        begin
            data_WE_reg <= 4'b0;
            data_EN_sw_reg <= 1'b0;
            ss_tready_reg <= 1'b0;
            
            case (state)
            	ap_start:
            	begin
            		if(sm_tvalid)
            		    ss_read_valid_reg <= 1'b0;
            	end
          
          	    ap_done: 
          	    begin
                    stream_prepared_reg <= 0;
                    ss_count_reg <= 0;                   
                end
	        endcase
        end
    end
end

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        sm_tvalid_reg <= 0;
        ctrl_tap_ready_reg <= 0;
        data_EN_sr_reg <= 0;
        tap_EN_sr_reg <= 0;
    end
    else
    begin
        if (sm_tready && !sm_tvalid)
        begin
            case(state)

                ap_start:
                begin
                    if(ss_read_valid && ctrl_tap_valid)
                    begin                        
                        data_EN_sr_reg <= 1;
                        tap_EN_sr_reg <= 1;
			            sm_tvalid_reg <= 0;
			 
                        ctrl_tap_ready_reg <= 1;
                    end
                    else if (ss_read_valid && ctrl_tap_ready && !ctrl_tap_valid)
                    begin
                        sm_tvalid_reg <= 1;
                        ctrl_tap_ready_reg <= 0 ;

                    end
                end
                
                ap_idle: 
                begin
                    sm_tvalid_reg <= 0;
                end
                    
            endcase
        end
        else
        begin
            if (ss_read_valid && ctrl_tap_ready && !ctrl_tap_valid ) begin
                        sm_tvalid_reg <= 1'b1;
                        ctrl_tap_ready_reg <= 1'b0 ;
                end
            	else sm_tvalid_reg <= 1'b0;
        end
    end
end

//caculate fir declare
wire  [pDATA_WIDTH-1:0]       o_ram_data;
wire  [pDATA_WIDTH-1:0]       o_coef_data;
reg   [pDATA_WIDTH-1:0]       old_ram_data_reg;
reg   [pDATA_WIDTH-1:0]       old_coef_data_reg;
wire  [pDATA_WIDTH-1:0]       old_ram_data;
wire  [pDATA_WIDTH-1:0]       old_coef_data;
wire  [pDATA_WIDTH-1:0]       new_ram_data;
wire  [pDATA_WIDTH-1:0]       new_coef_data;
wire  [3:0]                   ctrl_count;


assign old_ram_data = old_ram_data_reg;
assign old_coef_data = old_coef_data_reg;

assign new_coef_data = tap_Do;
assign new_ram_data = data_Do;

assign ctrl_tap_ready = ctrl_tap_ready_reg;
assign o_ram_data = sel ?  old_ram_data : new_ram_data;
assign o_coef_data = sel ?  old_coef_data : new_coef_data;

//caculate fir

always@(posedge axis_clk)
begin

    if(!axis_rst_n)
        sm_tdata_reg <= 0;
    else if(sm_tvalid)
        sm_tdata_reg <= 0;
    else if(ffen)
        sm_tdata_reg <= sm_tdata_reg +(o_ram_data*o_coef_data);
end

always@(posedge axis_clk)
begin
    if(ffen)
    begin
        old_ram_data_reg <= new_ram_data;
        old_coef_data_reg <= new_coef_data;
    end
end

// ctrl_tapRAM
wire en;
reg o_valid_reg, ffen_r;
reg [pADDR_WIDTH-1:0] o_data_addr_reg;
reg [pADDR_WIDTH-1:0] o_tap_addr_reg;


assign ctrl_tap_valid = o_valid_reg;
assign ctrl_data_addr = o_data_addr_reg;
assign ctrl_tap_addr = o_tap_addr_reg;
assign ffen = ffen_r;
assign sel = ~ffen ;
assign en = ctrl_tap_ready & ctrl_tap_valid;

reg[3:0] count_reg;
assign ctrl_count = count_reg;

reg [pADDR_WIDTH-1:0]tap_last_addr_reg;

always@(posedge axis_clk)   // axis_clk
begin
    if (!ctrl_rst_n)  //!axis_rst_n
    begin
        o_data_addr_reg <= 0;
        o_tap_addr_reg <= 12'd40;
        ffen_r  <= 0;
        o_valid_reg <= 0;
        count_reg <= 0;
    end
    else if(en)
    begin
        o_valid_reg <= (ctrl_count == 4'd10) ? 0 : 1;

        o_data_addr_reg <= (ctrl_count == 4'd10)? 0:o_data_addr_reg + 4;

        o_tap_addr_reg <= (ctrl_count == 4'd10) ? tap_last_addr_reg :
                     (ctrl_tap_addr == 12'd40) ? 0 : ctrl_tap_addr + 4;

        tap_last_addr_reg <= (ctrl_count == 0 && ctrl_tap_addr == 0) ? 12'd40 :
                        (ctrl_count == 0) ? ctrl_tap_addr - 4 : tap_last_addr_reg;

        count_reg <= (ctrl_count == 4'd10) ? 0 :ctrl_count + 1;

        ffen_r  <= 1;
    end
    else
    begin
        o_valid_reg <= 1;
        ffen_r  <= 0;
    end
end

// Lite write declare
reg wready_reg;
reg awready_reg;

reg [pADDR_WIDTH-1:0]       tap_WA_reg;
reg [pDATA_WIDTH-1:0]       tap_Di_reg;
wire [pADDR_WIDTH-1:0]      tap_WA;
reg [pDATA_WIDTH-1:0]       data_length;

assign awready = awready_reg;
assign wready = wready_reg;
assign tap_WE = (awaddr>=12'h40 && awaddr<=12'h7f)?{4{awvalid & wvalid}}:0;

assign tap_WA = (awaddr-12'h40);
assign tap_Di = wdata;

// Lite write
always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        awready_reg <= 0;
        wready_reg <= 0;
        ap_start_sig <= 0;
    end
    else
    begin
        if (!awready && awvalid)
        begin
            awready_reg <= 1'b1;
            
            if(awaddr>=12'h40 && awaddr<=12'h7f)
            begin
                awready_reg <= 1;                
            end
            else if (awaddr==0 && wdata==1)
                awready_reg <= 1'b1;
        end
        else
        begin
            awready_reg <= 0;
        end

        if (!wready && wvalid)
        begin
            
            if(awaddr>=12'h40 && awaddr<=12'h7f)
            begin
                 
                wready_reg <= 1'b1;
            end
            else if (awaddr==12'h10)
                data_length <= wdata;
            else if(awaddr==0 && wdata==1)
                ap_start_sig <= 1'b1;

        end
        else
        begin
            wready_reg <= 0;

            if(stream_prepared)
                ap_start_sig <= 0;
        end

    end
end

// Lite read declare
reg arready_reg;
reg rvalid_reg;

reg [pDATA_WIDTH-1:0]       rdata_reg;
wire [pADDR_WIDTH-1:0]      tap_RA;

assign arready = arready_reg;
assign rvalid = rvalid_reg;
assign rdata = rdata_reg ;

assign tap_RA = (tap_EN_sr_reg) ? tap_RA_sr : tap_RA_lr;
assign tap_EN = {awvalid & wvalid} | tap_EN_r_d ;

always @( posedge axis_clk )
begin
    tap_EN_r_d <= {arvalid & arready} | tap_EN_sr_reg;
end

assign tap_A = ({awready & wvalid}) ? tap_WA :
       ({arvalid & arready} | tap_EN_sr_reg) ? tap_RA : 0;


// Lite read

always@(*)
begin
    case(state)

        ap_start:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h00;
            else if(awaddr==12'h10 && rvalid)
                rdata_reg = data_length;
            else
                rdata_reg = tap_Do;
        end

        ap_done:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h06;
            else
                rdata_reg = tap_Do;
        end

        ap_idle:
        begin
            if(araddr==0 && rvalid)
                rdata_reg =32'h04;
            else if(araddr==0 && rvalid && ap_start_sig)
                rdata_reg =32'h01;
            else
                rdata_reg = tap_Do;
        end

        default:
            rdata_reg = 0;
    endcase
end

always @( posedge axis_clk )
begin
    if ( !axis_rst_n )
    begin
        arready_reg <= 1'b0;
        rvalid_reg <= 1'b0;
    end
    else
    begin
        if(!arready && arvalid && !rvalid)
        begin
            if(araddr>=12'h40 && araddr<=12'h7f)
            begin
                arready_reg <= 1'b1;                
            end
            else if(araddr==12'h0)
            begin
                arready_reg <= 1'b1;
            end
            else if (awaddr==12'h10)
                arready_reg <= 1'b1;
            else
                arready_reg <= 1'b0;

        end
        else if(arready && arvalid && !rvalid)
        begin
            arready_reg <= 1'b0;
            rvalid_reg <= 1'b1;
        end
        else
        begin
            arready_reg <= 1'b0;
            rvalid_reg <= 1'b0;
        end
    end
end
endmodule



