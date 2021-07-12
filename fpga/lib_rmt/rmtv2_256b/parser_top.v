`timescale 1ns / 1ps


module parser_top #(
	parameter C_S_AXIS_DATA_WIDTH = 256,
	parameter C_S_AXIS_TUSER_WIDTH = 128,
	parameter PKT_HDR_LEN = (6+4+2)*8*8+256, // check with the doc
	parameter PARSER_MOD_ID = 3'b0,
	parameter C_NUM_SEGS = 4,
	parameter C_VLANID_WIDTH = 12
)
(
	input									axis_clk,
	input									aresetn,

	// input slvae axi stream
	input [C_S_AXIS_DATA_WIDTH-1:0]			s_axis_tdata,
	input [C_S_AXIS_TUSER_WIDTH-1:0]		s_axis_tuser,
	input [C_S_AXIS_DATA_WIDTH/8-1:0]		s_axis_tkeep,
	input									s_axis_tvalid,
	input									s_axis_tlast,

	// output
	output reg								parser_valid,
	output reg [PKT_HDR_LEN-1:0]			pkt_hdr_vec,

	// back-pressure signals
	output									s_axis_tready,
	input									stg_ready_in,

	// output to different pkt fifo queues (i.e., data cache)
	output [C_S_AXIS_DATA_WIDTH-1:0]		m_axis_tdata_0,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser_0,
	output [C_S_AXIS_DATA_WIDTH/8-1:0]		m_axis_tkeep_0,
	output									m_axis_tlast_0,
	output									m_axis_tvalid_0,
	input									m_axis_tready_0,

	output [C_S_AXIS_DATA_WIDTH-1:0]		m_axis_tdata_1,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser_1,
	output [C_S_AXIS_DATA_WIDTH/8-1:0]		m_axis_tkeep_1,
	output									m_axis_tlast_1,
	output									m_axis_tvalid_1,
	input									m_axis_tready_1,

	output [C_S_AXIS_DATA_WIDTH-1:0]		m_axis_tdata_2,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser_2,
	output [C_S_AXIS_DATA_WIDTH/8-1:0]		m_axis_tkeep_2,
	output									m_axis_tlast_2,
	output									m_axis_tvalid_2,
	input									m_axis_tready_2,

	output [C_S_AXIS_DATA_WIDTH-1:0]		m_axis_tdata_3,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		m_axis_tuser_3,
	output [C_S_AXIS_DATA_WIDTH/8-1:0]		m_axis_tkeep_3,
	output									m_axis_tlast_3,
	output									m_axis_tvalid_3,
	input									m_axis_tready_3,

	// ctrl path
	input [C_S_AXIS_DATA_WIDTH-1:0]			ctrl_s_axis_tdata,
	input [C_S_AXIS_TUSER_WIDTH-1:0]		ctrl_s_axis_tuser,
	input [C_S_AXIS_DATA_WIDTH/8-1:0]		ctrl_s_axis_tkeep,
	input									ctrl_s_axis_tvalid,
	input									ctrl_s_axis_tlast,

	output [C_S_AXIS_DATA_WIDTH-1:0]		ctrl_m_axis_tdata,
	output [C_S_AXIS_TUSER_WIDTH-1:0]		ctrl_m_axis_tuser,
	output [C_S_AXIS_DATA_WIDTH/8-1:0]		ctrl_m_axis_tkeep,
	output									ctrl_m_axis_tvalid,
	output									ctrl_m_axis_tlast
);

wire [C_NUM_SEGS*C_S_AXIS_DATA_WIDTH-1:0]	tdata_segs_in, tdata_segs_fifo_out;
wire [C_S_AXIS_TUSER_WIDTH-1:0]				tuser_1st_in, tuser_1st_fifo_out;
wire										segs_fifo_full, segs_fifo_empty;
wire										vlan_fifo_full, vlan_fifo_empty;
wire										segs_valid_in, vlan_valid_in;

wire [C_VLANID_WIDTH-1:0]					vlan_in, vlan_fifo_out;
wire										segs_fifo_rd, vlan_fifo_rd;

assign s_axis_tready = ~segs_fifo_full & ~vlan_fifo_full;


wire [3:0] m_axis_tready_queue;

assign m_axis_tready_queue[0] = m_axis_tready_0;
assign m_axis_tready_queue[1] = m_axis_tready_1;
assign m_axis_tready_queue[2] = m_axis_tready_2;
assign m_axis_tready_queue[3] = m_axis_tready_3;


localparam	IDLE=0,
			FLUSH_REST_PKTS=1;
reg [1:0] state, state_next;
reg [1:0] cur_queue, cur_queue_next;
wire [1:0] cur_queue_plus1;

assign cur_queue_plus1 = (cur_queue==3)?0:cur_queue+1;

// ==================================================
assign m_axis_tdata_0 = s_axis_tdata;
assign m_axis_tuser_0 = s_axis_tuser;
assign m_axis_tkeep_0 = s_axis_tkeep;
assign m_axis_tlast_0 = s_axis_tlast;
assign m_axis_tvalid_0 = (cur_queue==0?1:0) & s_axis_tvalid;

assign m_axis_tdata_1 = s_axis_tdata;
assign m_axis_tuser_1 = s_axis_tuser;
assign m_axis_tkeep_1 = s_axis_tkeep;
assign m_axis_tlast_1 = s_axis_tlast;
assign m_axis_tvalid_1 = (cur_queue==1?1:0) & s_axis_tvalid;

assign m_axis_tdata_2 = s_axis_tdata;
assign m_axis_tuser_2 = s_axis_tuser;
assign m_axis_tkeep_2 = s_axis_tkeep;
assign m_axis_tlast_2 = s_axis_tlast;
assign m_axis_tvalid_2 = (cur_queue==2?1:0) & s_axis_tvalid;

assign m_axis_tdata_3 = s_axis_tdata;
assign m_axis_tuser_3 = s_axis_tuser;
assign m_axis_tkeep_3 = s_axis_tkeep;
assign m_axis_tlast_3 = s_axis_tlast;
assign m_axis_tvalid_3 = (cur_queue==3?1:0) & s_axis_tvalid;
// ==================================================


always @(*) begin
	state_next = state;
	cur_queue_next = cur_queue;

	case (state)
		IDLE: begin
			if (s_axis_tvalid) begin
				if (m_axis_tready_queue[cur_queue]) begin

					if (!s_axis_tlast) begin
						state_next = FLUSH_REST_PKTS;
					end
					else begin
						cur_queue_next = cur_queue_plus1;
					end
				end
			end
		end
		FLUSH_REST_PKTS: begin
			if (s_axis_tvalid) begin
				if (m_axis_tready_queue[cur_queue]) begin

					if (s_axis_tlast) begin
						cur_queue_next = cur_queue_plus1;
						state_next = IDLE;
					end
				end
			end
		end
	endcase
end

always @(posedge axis_clk) begin
	if (~aresetn) begin
		state <= IDLE;
		cur_queue <= 0;
	end
	else begin
		state <= state_next;
		cur_queue <= cur_queue_next;
	end
end

// ==================================================

localparam P_IDLE=0;

reg [1:0] p_state, p_state_next;
reg [1:0] p_cur_queue, p_cur_queue_next;
wire [1:0] p_cur_queue_plus1;

assign p_cur_queue_plus1 = (p_cur_queue==3)?0:p_cur_queue+1;

wire [3:0] p_cur_queue_val;
assign p_cur_queue_val[0] = (p_cur_queue==0)?1:0;
assign p_cur_queue_val[1] = (p_cur_queue==1)?1:0;
assign p_cur_queue_val[2] = (p_cur_queue==2)?1:0;
assign p_cur_queue_val[3] = (p_cur_queue==3)?1:0;

wire parser_valid_w;
wire [PKT_HDR_LEN-1:0] pkt_hdr_vec_w;
reg [PKT_HDR_LEN-1:0] pkt_hdr_vec_next;
reg parser_valid_next;

always @(*) begin
	p_state_next = p_state;
	p_cur_queue_next = p_cur_queue;
	
	pkt_hdr_vec_next = pkt_hdr_vec;
	parser_valid_next = 0;
	case (p_state)
		P_IDLE: begin
			if (parser_valid_w) begin
				pkt_hdr_vec_next = {pkt_hdr_vec_w[PKT_HDR_LEN-1:145], p_cur_queue_val, pkt_hdr_vec_w[0+:141]};
				parser_valid_next = 1;

				p_cur_queue_next = p_cur_queue_plus1;
			end
		end
	endcase
end

always @(posedge axis_clk) begin
	if (~aresetn) begin
		p_state <= P_IDLE;
		p_cur_queue <= 0;
		pkt_hdr_vec <= 0;
		parser_valid <= 0;
	end
	else begin
		p_state <= p_state_next;
		p_cur_queue <= p_cur_queue_next;
		pkt_hdr_vec <= pkt_hdr_vec_next;
		parser_valid <= parser_valid_next;
	end
end

// ==================================================

fallthrough_small_fifo #(
	.WIDTH(C_NUM_SEGS*C_S_AXIS_DATA_WIDTH+C_S_AXIS_TUSER_WIDTH),
	.MAX_DEPTH_BITS(5)
)
segs_fifo (
	.din					({tdata_segs_in, tuser_1st_in}),
	.wr_en					(segs_valid_in),
	//
	.rd_en					(segs_fifo_rd),
	.dout					({tdata_segs_fifo_out, tuser_1st_fifo_out}),
	//
	.full					(),
	.prog_full				(),
	.nearly_full			(segs_fifo_full),
	.empty					(segs_fifo_empty),
	.reset					(~aresetn),
	.clk					(axis_clk)
);

fallthrough_small_fifo #(
	.WIDTH(C_VLANID_WIDTH),
	.MAX_DEPTH_BITS(5)
)
vlan_fifo (
	.din					(vlan_in),
	.wr_en					(vlan_valid_in),
	//
	.rd_en					(vlan_fifo_rd),
	.dout					(vlan_fifo_out),
	//
	.full					(),
	.prog_full				(),
	.nearly_full			(vlan_fifo_full),
	.empty					(vlan_fifo_empty),
	.reset					(~aresetn),
	.clk					(axis_clk)
);

parser_wait_segs #(
)
get_segs
(
	.axis_clk				(axis_clk),
	.aresetn				(aresetn),

	.s_axis_tdata			(s_axis_tdata),
	.s_axis_tuser			(s_axis_tuser),
	.s_axis_tkeep			(s_axis_tkeep),
	.s_axis_tvalid			(s_axis_tvalid),
	.s_axis_tlast			(s_axis_tlast),

	.segs_fifo_ready		(!segs_fifo_full),
	// output
	.tdata_segs				(tdata_segs_in),
	.tuser_1st				(tuser_1st_in),
	.vlan					(vlan_in),
	.segs_valid				(segs_valid_in),
	.vlan_valid				(vlan_valid_in)
);

parser_do_parsing #(
)
do_parsing
(
	.axis_clk				(axis_clk),
	.aresetn				(aresetn),

	.tdata_segs				(tdata_segs_fifo_out),
	.tuser_1st				(tuser_1st_fifo_out),
	.vlan_id				(vlan_fifo_out),
	.segs_fifo_empty		(segs_fifo_empty),
	.vlan_fifo_empty		(vlan_fifo_empty),
	.stg_ready_in			(stg_ready_in),

	.segs_fifo_rd			(segs_fifo_rd),
	.vlan_fifo_rd			(vlan_fifo_rd),
	
	.parser_valid			(parser_valid_w),
	.pkt_hdr_vec			(pkt_hdr_vec_w),

	.ctrl_s_axis_tdata		(ctrl_s_axis_tdata),
	.ctrl_s_axis_tuser		(ctrl_s_axis_tuser),
	.ctrl_s_axis_tkeep		(ctrl_s_axis_tkeep),
	.ctrl_s_axis_tvalid		(ctrl_s_axis_tvalid),
	.ctrl_s_axis_tlast		(ctrl_s_axis_tlast),

	.ctrl_m_axis_tdata		(ctrl_m_axis_tdata),
	.ctrl_m_axis_tuser		(ctrl_m_axis_tuser),
	.ctrl_m_axis_tkeep		(ctrl_m_axis_tkeep),
	.ctrl_m_axis_tvalid		(ctrl_m_axis_tvalid),
	.ctrl_m_axis_tlast		(ctrl_m_axis_tlast)
);


endmodule
