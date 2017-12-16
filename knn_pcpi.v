`define LOG	1 

module KNN_PCPI(
input           	    clk, resetn,
	input      	        pcpi_valid,
	input     	 [31:0] pcpi_insn,
	input     	 [31:0] pcpi_rs1,
	input    	 [31:0] pcpi_rs2,
	output reg          pcpi_wr,
	output reg   [31:0] pcpi_rd,
	output reg          pcpi_wait,
	output reg          pcpi_ready,
	//memory interface
	input        [31:0] mem_rdata,
	input               mem_ready,
	output reg          mem_valid,
	output reg          mem_write,
	output reg   [31:0] mem_addr,
	output reg   [31:0] mem_wdata
);

	// state parameter
	parameter IDLE = 3'b000;
	// L2DIST start
	parameter GETTEST = 3'b001;
	parameter GETTRAIN = 3'b010;
	parameter COMPUTE = 3'b011;
	// L2DIST end
	parameter TOPK = 3'b100;
	parameter GETLABEL = 3'b101;
	parameter VOTE = 3'b110;
	
	parameter DONE = 3'b111;

	// knn paraneter 
	parameter K = 32'd5;
	parameter IMAGE_OFFSET = 32'h0001_0000;
	parameter NUM_CLASS = 32'd10;
    parameter NUM_TEST_IMAGE = 32'd50;
    parameter NUM_TRAIN_IMAGE = 32'd950;
	parameter DATA_LENGTH = 32'd3073;

	parameter DIST_OFFSET = 32'h0002_0000;
	parameter MAX_INT = 32'd2147483647;


	wire pcpi_insn_valid = pcpi_valid && pcpi_insn[6:0] == 7'b0101011 && pcpi_insn[31:25] == 7'b0000001;

	reg [2:0] state;
	reg [2:0] state_next;

	// L2 distance 
	wire [31:0] test = pcpi_rs1;
	wire [31:0] train = pcpi_rs2;
	
	reg [31:0] pixel_pos;
	reg [31:0] pixel_pos_next;
	reg [31:0] train_pixel;
	reg [31:0] test_pixel; 

	reg [31:0] dist;
	reg	[31:0] dist_next;

	reg [31:0] dists[NUM_TRAIN_IMAGE-1:0];

	// topk 
	reg [31:0] topk_dist[K-1:0];
	reg [31:0] topk_image[K-1:0];
	reg [31:0] topk_dist_next[K-1:0];
	reg [31:0] topk_image_next[K-1:0];

	integer a, i, j, insert_idx;
	
	
	// getlabel
	reg [31:0] get_label_counter;
	reg [31:0] get_label_counter_next;
	reg [31:0] topk_label[K-1:0];
	reg [31:0] topk_label_next[K-1:0];

	integer label; 

	// vote
	reg [31:0] max_count;
	reg [31:0] max_label;
	reg [31:0] num_labels[NUM_CLASS-1:0];
	integer k;

	always@(posedge clk or negedge resetn)begin
		if(!resetn)begin
			state <= IDLE;
		end else begin
			state <= state_next;
		end
	end	

	always@(posedge clk or negedge resetn)begin
		if(!resetn || state == IDLE)begin
			pixel_pos <= 32'd1;
			dist <= 32'd0;
		end else begin
			if(state == COMPUTE || state == GETTEST) begin
				pixel_pos <= pixel_pos_next;
				dist <= dist_next;
			end
		end
	end

	always@(posedge clk or negedge resetn)begin
		if(!resetn || state == VOTE)begin
			for(a=0; a<K; a=a+1)begin
				topk_dist[a] <= MAX_INT;
				topk_image[a] <= 0;
			end
		end 
	end

	always@(posedge clk or negedge resetn)begin
		if(!resetn || state == IDLE)begin
			get_label_counter <= 32'd0;
			for(label=0; label<K; label=label+1)begin	
					topk_label[label] = 0;
				end
		end else begin
			if(state == GETLABEL) begin
				get_label_counter <= get_label_counter_next;
				for(label=0; label<K; label=label+1)begin	
					topk_label[label] = topk_label_next[label];
				end
			end
		end
	end
	
	always@(posedge clk or negedge resetn)begin
		if(!resetn || state == IDLE)begin
			for(i=0; i<NUM_CLASS ;i=i+1)begin
				num_labels[i] = 32'd0;
			end
		end
	end

	always@(*)begin
		state_next = state;
		pixel_pos_next = pixel_pos;
		dist_next = dist;
		
		get_label_counter_next = get_label_counter;
		for(k=0; k<K; k=k+1)begin	
			topk_label_next[k] = topk_label[k];
		end
	
		pcpi_wr = 1'b0;
		pcpi_wait = 1'b1;
		pcpi_ready = 1'b0;
		pcpi_rd = 32'd0;

		mem_write = 1'b0;
		mem_valid = 1'b0;
		mem_addr = 32'd0;
		mem_wdata = 32'd0;

		case(state)
			IDLE: begin
				if(pcpi_insn_valid)begin
					if(pcpi_rs2 != 32'd0)begin
						state_next = GETTEST;
					end else begin
						state_next = TOPK;
					end
				end else begin
					state_next = IDLE;
					pcpi_wait = 1'b0;
				end
			end
			GETTEST: begin
				// pass test image pixel addr
				state_next = GETTRAIN;			

				mem_write = 1'b0;
				mem_valid = 1'b1;
				mem_addr = IMAGE_OFFSET + (test * DATA_LENGTH + pixel_pos) * 32'd4;
			end
			GETTRAIN: begin
				// pass train image pixel addr
				//gg read test image pixel from memory
				state_next = COMPUTE;
				mem_write = 1'b0;
				mem_valid = 1'b1;
				mem_addr = IMAGE_OFFSET + (train * DATA_LENGTH + pixel_pos) * 32'd4;
				test_pixel = mem_rdata;
			end
			COMPUTE: begin
				// 1. 	read train image pixel from memory then compute distance of 2 pixels
				// 2.   put final dist into dists
				mem_valid = 1'b1;
				train_pixel = mem_rdata;
				dist_next = dist + (test_pixel - train_pixel)*(test_pixel - train_pixel);
				
				if(pixel_pos == 32'd3072) begin
					state_next = IDLE;
					
					dists[train-50] = dist + (test_pixel - train_pixel)*(test_pixel - train_pixel);

					pixel_pos_next = 32'd1;
					// return L2 distance
					pcpi_wr = 1'b1;
					pcpi_wait = 1'b0;
					pcpi_ready = 1'b1;
					pcpi_rd = dist_next;
				end else begin
					state_next = GETTEST;

					pixel_pos_next = pixel_pos + 32'd1;
				end
			end
			TOPK: begin
				state_next = GETLABEL;
				// find the top k
				// get the index to insert, so that distances after this index are all larger
				for(i=0; i<NUM_TRAIN_IMAGE; i=i+1)begin
					insert_idx = K;
					for(j=0; j<K; j=j+1)begin
						if(dists[i] < topk_dist[j])begin
							if(insert_idx == K)begin
								insert_idx = j;
							end
						end
					end
					if(insert_idx != K)begin
						// shift
						for(j=K-1; j > insert_idx; j=j-1)begin
							topk_dist[j] = topk_dist[j-1];
							topk_image[j] = topk_image[j-1];
						end
						topk_dist[insert_idx] = dists[i];
						topk_image[insert_idx] = i;
					end
				end
			end
			GETLABEL: begin
				// get K label
				get_label_counter_next = get_label_counter + 32'd1;
				
				// read label from memory, and get the data at next cycle
				mem_valid = 1'b1;
				mem_write = 1'b0;
				if(get_label_counter >= 32'd0 && get_label_counter <=32'd4)begin
					mem_addr = IMAGE_OFFSET + (topk_image[get_label_counter]+NUM_TEST_IMAGE) * DATA_LENGTH * 32'd4;
				end
				// give the label to topk_label	
				if(get_label_counter != 32'd0)begin
					topk_label_next[get_label_counter-32'd1] = mem_rdata;
				end 

				if(get_label_counter == 32'd5)begin
					state_next = VOTE;
				end else begin
					state_next = GETLABEL;
				end
			end
			VOTE: begin
				state_next = DONE;				

				max_count = 32'd0;
				max_label = 32'd0;
				for(k=32'd0; k<K; k=k+1)begin
					num_labels[topk_label[k]] = num_labels[topk_label[k]] + 32'd1;
					if(num_labels[topk_label[k]] > max_count)begin
						max_count = num_labels[topk_label[k]];
						max_label = topk_label[k];
					end else if(num_labels[topk_label[k]] == max_count && topk_label[k] < max_label)begin
						max_count = num_labels[topk_label[k]];
						max_label = topk_label[k];
					end
				end
			end	
			DONE: begin
				state_next = IDLE;	

				pcpi_wr = 1'b1;
				pcpi_wait = 1'b0;
				pcpi_ready = 1'b1;
				pcpi_rd = max_label;	
			end	
		endcase
	end

	`ifdef LOG
	integer iter;
	always@(*)begin
		if(pcpi_insn_valid && state == VOTE)begin
/*			for(iter=0; iter<K; iter=iter+1)begin
				$display("topk_image[%d] = %d", iter, topk_image[iter]);
			end
*/			for(iter=0; iter<K; iter=iter+1)begin
				$display("topk_dist [%d] = %d", iter, topk_dist[iter]);
			end
			for(iter=0; iter<K; iter=iter+1)begin
				$display("topk_label[%d] = %d", iter, topk_label[iter]);
			end
			$display("=================");
		//	$display("state: %d, cpi_rs1: %d, pcpi_rs2: %d, mem_rdata: %d", state, pcpi_rs1, pcpi_rs2, mem_rdata);
  		end
	end
	`endif
endmodule
