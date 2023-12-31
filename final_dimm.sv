module dimm;

	// DECLARATIONS

	int					fd_in;
	int					fd_out;
	string				in_fname;
	string				out_fname;
	string				mode;
	longint unsigned	current_cyc = 0;
	longint unsigned	wait_time;
	longint unsigned	in_cpu_cyc;
	logic [2:0]			in_core;
	int					in_opn;
	logic [33:0]		in_addr;
	int					isExec;
	longint unsigned	exec_cyc;
	logic [3:0][1:0]	isAccess;
	int			inCounter = 0;
	int			waitCounter = 0;
	
	// TIMING CONSTRAINTS (EXPRESSED IN CPU CLOCK CYCLES)
		
	longint unsigned	tRC		= 230;
	// localparam	tRC		= 115; CHECK
	longint unsigned	tRAS	= 152;
	longint unsigned	tRP		= 78;
	longint unsigned	tWCD	= 76;
	longint unsigned	tCAS	= 80;
	longint unsigned	tRCD	= 78;
	longint unsigned	tRTP	= 36;
	longint unsigned	tWR		= 60;
	longint unsigned	tBURST	= 16;
	
	// INPUT DATA STRUCTURE

	typedef struct packed {
		longint unsigned cpu_cyc;
		logic [2:0]		core;
		logic [1:0]		byte_select;
		logic [1:0]		opn;
		logic			channel;
		logic [2:0]		bank_group;
		logic [1:0]		bank;
		logic [15:0]	row;
		logic [5:0]		high_column;
		logic [4:0]		low_column;
		logic [9:0]		column;
		logic [33:0]	addr;
    } dIn_t;
	
	dIn_t q_in[$];					// INPUT QUEUE TO STORE PARSED ENTRIES
	dIn_t scheduler[$:16];			// SCHEDULER QUEUE OF SIZE 16
	dIn_t temp_in;					// VARIABLE TO INSERT ELEMENT IN INPUT QUEUE
	dIn_t temp_wait;				// VARIABLE TO INSERT ELEMENT IN SCHEDULER QUEUE
	dIn_t temp_out;					// VARIABLE TO EXTRACT ELEMENT FROM SCHEDULER QUEUE
	
	// COMMANDS TO BE ISSUED BY DIMM
	
	typedef enum {
		ACT0,
		ACT1,
		RD0,
		RD1,
		WR0,
		WR1,
		PRE,
		STALL
	} cmd_t;
	
	cmd_t current_cmd;				// CURRENTLY ISSUED COMMAND
	cmd_t next_cmd;					// COMMAND TO BE ISSUED NEXT
	
	// READ AND PARSE TRACE FILE

    initial begin
	current_cyc = 0;
        if ($value$plusargs("mode=%s", mode)) begin
            if (mode == "DEBUG")
                $display("DEBUG mode selected.");
            else
                $display("DEBUG mode not selected.");
        end

        $value$plusargs("ifname=%s", in_fname);
		$value$plusargs("ofname=%s", out_fname);

        if(in_fname) begin
            fd_in = $fopen(in_fname, "r");
        end
        else begin
            in_fname = "trace.txt";
            $display("No input file name specified, selecting file %s.", $sformatf("%s", in_fname));
			$fwrite	(fd_out,"No input file name specified, selecting file %s.\n", $sformatf("%s", in_fname));
            fd_in = $fopen(in_fname, "r");   	
        end
		
		if (out_fname) begin
			fd_out = $fopen(out_fname, "w");
		end
		else begin
			out_fname = "dram.txt";
			$display("No output file name specified, selecting file %s.", out_fname);
			$fwrite	(fd_out,"No output file name specified, selecting file %s.\n", out_fname);
			fd_out = $fopen(out_fname, "w");
		end


        if (fd_in) begin
            $display("File opened.");
        end
        else begin
            $display("File not opened.");
             if (mode == "DEBUG") begin
                $display("%s ,%d", in_fname, fd_in);
				$fwrite	(fd_out,"%s ,%d\n", in_fname, fd_in);
			end
		end

	// ADDING ELEMENT TO QUEUE

		do begin
			
			while ($fscanf(fd_in, "%0d %d %d %h\n", in_cpu_cyc, in_core, in_opn, in_addr) == 4) begin
				inCounter++;
				if (in_core >= 13 || in_opn >= 3 || in_addr[6] != 0) begin
					if (mode == "DEBUG") begin
						$display("DEBUG mode: Boundary condition failure. Core > 13 | Operation > 3 | Channel > 0. Scrapping the entry.");
						$fwrite(fd_out,"DEBUG mode: Boundary condition failure. Core > 13 | Operation > 3 | Channel > 0. Scrapping the entry.\n");
					end
				end
				else begin
					temp_in.cpu_cyc		=	in_cpu_cyc;
					temp_in.core		=	in_core;
					temp_in.byte_select	=	in_addr[1:0];
					temp_in.opn			=	in_opn;
					temp_in.channel		=	in_addr[6];
					temp_in.bank_group	=	in_addr[9:7];
					temp_in.bank		=	in_addr[11:10];
					temp_in.row			=	in_addr[33:18];
					temp_in.high_column	=	in_addr[17:12];
					temp_in.low_column	=	in_addr[5:2];
					temp_in.column		=	{in_addr[17:12],in_addr[5:2]};
					temp_in.addr		=	in_addr;
					$fwrite(fd_out,"temp_in at q_in %p\n", temp_in);
					if (mode == "DEBUG") begin
						$display("DEBUG mode: At time %0d temp_in has been assigned input values. temp_in = %p", current_cyc, temp_in);
						$fwrite	(fd_out,"DEBUG mode: At time %0d temp_in has been assigned input values. temp_in = %p\n", current_cyc, temp_in);
					end
					
					q_in.push_back(temp_in);

	
					if (mode == "DEBUG") begin
						$display("DEBUG mode: Displaying parsed entries: Clock: %0d Core: %d Operation: %d Bank Group : %h Bank: %h Row : %h Column: %h", temp_in.cpu_cyc, temp_in.core, temp_in.opn, temp_in.bank_group, temp_in.bank, temp_in.row, temp_in.column);
						$fwrite	(fd_out,"DEBUG mode: Displaying parsed entries: Clock: %0d Core: %d Operation: %d Bank Group : %h Bank: %h Row : %h Column: %h\n", temp_in.cpu_cyc, temp_in.core, temp_in.opn, temp_in.bank_group, temp_in.bank, temp_in.row, temp_in.column);
					end
				end
			end
       	
		end
		while(!$feof(fd_in));
		$fclose(fd_in);
		$display("All lines have been parsed.");
		$fwrite(fd_out,"All lines have been parsed.\n");
    end
	
	task inScheduler;
		temp_wait = q_in.pop_front();
		$fwrite(fd_out,"temp_wait at scheduler q %p\n", temp_wait);
		if (waitCounter <= inCounter) begin
			waitCounter++;
			wait_time = temp_wait.cpu_cyc;
			if (wait_time >= current_cyc) begin
				wait(current_cyc == wait_time);
				scheduler.push_back(temp_wait);
				//void'(q_in.pop_front());
				if (mode == "DEBUG") begin
					$display("DEBUG mode: At time %0d element entered into scheduler queue. Element temp_wait = %p", current_cyc, temp_wait, current_cyc);
					$fwrite	(fd_out,"DEBUG mode: At time %0d element entered into scheduler queue. Element temp_wait = %p\n", current_cyc, temp_wait, current_cyc);
				end
			end
			else begin
				if (mode == "DEBUG") begin
					$display("DEBUG mode: At time %0d Boundary condition failure. cpu_cyc < current_cyc. Scrapping entry.", current_cyc);
					$fwrite(fd_out,"DEBUG mode: At time %0d Boundary condition failure. cpu_cyc < current_cyc. Scrapping entry.\n", current_cyc);
				end
			end
		end
		else if (waitCounter > inCounter) begin
			void'(q_in.pop_front());
		end
	endtask
	
	always #1 current_cyc = current_cyc + 1;
	
	// INSERT REQUEST IN SCHEDULER QUEUE WHILE STALLING REQUESTS TILL QUEUE HAS SPACE
		
	always@(current_cyc) begin
	 	if (q_in.size() > 0 && scheduler.size() < 16) begin
		temp_wait = q_in.pop_front();
		$fwrite(fd_out,"temp_wait at scheduler q %p\n", temp_wait);
		if (waitCounter <= inCounter) begin
			wait_time = temp_wait.cpu_cyc;
			if (wait_time >= current_cyc) begin
				wait(current_cyc == wait_time);
				scheduler.push_back(temp_wait);
				waitCounter++;

				if (mode == "DEBUG") begin
					$display("DEBUG mode: At time %0d element entered into scheduler queue. Element temp_wait = %p", current_cyc, temp_wait, current_cyc);
					$fwrite	(fd_out,"DEBUG mode: At time %0d element entered into scheduler queue. Element temp_wait = %p\n", current_cyc, temp_wait, current_cyc);
				end
			end
			else begin
				if (mode == "DEBUG") begin
					$display("DEBUG mode: At time %0d Boundary condition failure. cpu_cyc < current_cyc. Scrapping entry.", current_cyc);
					$fwrite(fd_out,"DEBUG mode: At time %0d Boundary condition failure. cpu_cyc < current_cyc. Scrapping entry.\n", current_cyc);
				end
			end
		end
		else if (waitCounter > inCounter) begin
			void'(q_in.pop_front());
		end	 		
//inScheduler;
		end
		else if(scheduler.size() == 16)
			if (mode == "DEBUG")
			$fwrite(fd_out,"DEBUG mode: Scheduler full at time %0d.\n", current_cyc);
	end
	
	// EXTRACT REQUEST FROM SCHEDULER QUEUE AND PRINT OUTPUT AFTER EVERY 2 CLOCK CYCLES
	
	// ADD 1 TO EACH PARAMETER, CHECK ALL TIMING CONSTRAINTS AND DECIDE WHERE 1 NEEDS TO BE ADDED
	
	always@(current_cyc) begin

		if(current_cyc % 2 == 0) begin
			case(current_cmd)
				ACT0: begin
					if(scheduler.size() > 0) begin
					isExec = 1;
					exec_cyc = current_cyc;
					temp_out = scheduler.pop_front();
					$display("At time %0d ACT0 %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.row,	temp_out.addr);
					$fwrite(fd_out,"At time %0d ACT0 %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.row,	temp_out.addr);
					current_cmd = ACT1;
					end
					else begin
					current_cmd = ACT0;
					end
				end
				ACT1: begin
					$display("At time %0d ACT1 %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.row,	temp_out.addr);
					$fwrite(fd_out,"At time %0d ACT1 %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.row,	temp_out.addr);
					isExec = 1;
					exec_cyc = exec_cyc + tRCD;
					wait (exec_cyc == current_cyc);
					current_cmd = (temp_out.opn ? WR0 : RD0);
				end
				RD0: begin
					$display("At time %0d RD0  %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					$fwrite(fd_out,"At time %0d RD0  %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					isExec = 1;
					current_cmd = RD1;
				end
				RD1: begin
					$display("At time %0d RD1  %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					$fwrite(fd_out,"At time %0d RD1  %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					isExec = 1;
					exec_cyc = exec_cyc + tCAS + tBURST;
					wait (exec_cyc == current_cyc);
					current_cmd = PRE;
				end
				WR0: begin
					$display("At time %0d WR0  %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					$fwrite(fd_out,"At time %0d WR0  %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					isExec = 1;
					current_cmd = WR1;
				end
				WR1: begin
					$display("At time %0d WR1  %d %d %h Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					$fwrite(fd_out,"At time %0d WR1  %d %d %h Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.column,	temp_out.addr	);
					isExec = 1;
					exec_cyc = exec_cyc + tWCD + tBURST;		// CHECK SPEC SHEET IF WR NEEDS TO BE ADDED, NOT SURE IF WCD IS CORRECT
					wait (exec_cyc == current_cyc);
					current_cmd = PRE;
				end
				PRE: begin
					$display("At time %0d PRE  %d %d 	Addr: %h", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.addr					);
					$fwrite(fd_out,"At time %0d PRE  %d %d 	Addr: %h\n", current_cyc, temp_out.bank_group, temp_out.bank, temp_out.addr					);
					isExec = 0;
					// IF SAME BANK AND BANK GROUP ONLY!!!
					if (isAccess[temp_out.bank_group][temp_out.bank]) begin
						exec_cyc = exec_cyc + (tRP - isAccess[temp_out.bank_group][temp_out.bank]);
						wait(current_cyc == exec_cyc);
						isAccess[temp_out.bank_group][temp_out.bank] = current_cyc;
					end
					else begin
						isAccess[temp_out.bank_group][temp_out.bank] = current_cyc;
					end
					//void' (scheduler.pop_front());
					// exec_cyc += tRP;
					// wait(exec_cyc == current_cyc);
					current_cmd = ACT0;
				end
			endcase
			end
			//end
			/*else begin
				scheduler.pop_front();
			end*/
		if (temp_in == temp_out) begin
			if (isExec == 0) begin
				#2000;
				$fclose(fd_in);
				$fclose(fd_out);
				$stop;
			end
		end
	end
	
	// PRINT OUT SCHEDULER QUEUE IS FULL
	
	/*always@(current_cyc) begin
		if(scheduler.size() == 16)
			if (mode == "DEBUG")
			$fwrite(fd_out,"DEBUG mode: Scheduler full at time %0d.\n", current_cyc);
	end*/
	
	//	IF MODE DEBUG IN SINGLE PLACE

endmodule : dimm