//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    instruction_pc_checker
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : instruction_pc_checker.v
// Module Description : Cross-checks the dispatched PC against the fetched instruction stream.
//----------------------------------------------------------------------------

`ifdef CHECKER_EN

module instruction_pc_checker #(
    parameter ROM_SIZE_BYTES = 64*1024  // ROM size in bytes (passed from testbench)
) (
    // Clock and reset
    input  wire        hclk_i,
    input  wire        hresetn_i,

    // Decoder inputs to check
    input  wire [31:0] id_instruction_i,
    input  wire        id_instruction_valid_i,
    input  wire        id_instruction_request_i,  // Instruction actually being consumed by decode
    input  wire [31:0] id_pc_i,

    // Report trigger
    input  wire        report_trigger_i,

    // Dynamic enable/disable control
    input  wire        checker_enable_i
);

// Memory to store expected data
// Size: Matches ROM size from testbench (ROM_SIZE / 2 since minimum instruction is 2 bytes)
// Format: [33:0] = {valid, is_compressed, instruction[31:0]}
// Note: Using half-word addressing to support compressed instructions at 2-byte boundaries
parameter MEM_SIZE = ROM_SIZE_BYTES / 2;  // Convert bytes to half-word entries
parameter ROM_BASE_ADDR = 32'h20000000;  // ROM base address
reg [33:0] expected_data [0:MEM_SIZE-1];

// Counters
integer total_checks;
integer checker_enabled;
integer num_entries_loaded;
integer mismatch_count;  // Local counter to track when to stop simulation

// File loading variables
integer checker_file;
integer scan_result;
reg [31:0] file_pc;
reg [31:0] file_inst;
integer file_is_compressed;
integer mem_idx;
integer i;  // Loop variable

// Checking variables
reg [33:0] exp_data;
reg        exp_valid;
reg        exp_is_compressed;
reg [31:0] exp_inst;
reg        act_is_compressed;
reg [31:0] inst_to_check;
reg [31:0] exp_inst_to_check;
reg        mismatch;

// Initialize and load checker data
initial begin

    // Initialize
    total_checks = 0;
    checker_enabled = 0;
    num_entries_loaded = 0;
    mismatch_count = 0;

    // Note: Memory is implicitly initialized to 'x' or '0' by simulator
    // We rely on the valid bit (bit 33) to determine if entry is loaded

    // Try to load checker data file
    checker_file = $fopen("./checker_data.mem", "r");
    if (checker_file != 0) begin
        $display("INFO-VERILOG: [Instruction/PC Checker] Loading checker data...");

        // Read all entries from file
        // Skip initial comment lines and read data lines starting with '@'
        begin : load_loop
        while (!$feof(checker_file)) begin
            scan_result = $fscanf(checker_file, "@%h %h %d",
                                  file_pc, file_inst, file_is_compressed);

            if (scan_result == 3) begin
                // Calculate memory index: subtract ROM base, then divide by 2 (half-word address)
                // This supports compressed instructions on 2-byte boundaries
                mem_idx = ((file_pc - ROM_BASE_ADDR) >> 1) & (MEM_SIZE - 1);

                // Store: {valid=1, is_compressed, instruction}
                expected_data[mem_idx] = {1'b1, file_is_compressed[0], file_inst};
                num_entries_loaded = num_entries_loaded + 1;
            end else begin
                // Skip this line if scan failed (e.g., comment or blank line)
                scan_result = $fgetc(checker_file);  // Read and discard until newline
                while (scan_result != "\n" && scan_result != -1) begin
                    scan_result = $fgetc(checker_file);
                end
            end
        end
        end // load_loop

        $fclose(checker_file);
        checker_enabled = 1;
        $display("INFO-VERILOG: [Instruction/PC Checker] Loaded %0d instruction entries", num_entries_loaded);
    end else begin
        $display("INFO-VERILOG: [Instruction/PC Checker] Disabled - checker_data.mem not found");
    end
end

// Report generation when triggered
always @(posedge report_trigger_i) begin
    if (checker_enabled) begin
        $display("");
        $display(" ===============================================");
        $display("| [Instruction/PC Checker] Summary              |");
        $display("|   Total instruction/PC pairs checked: %0d", total_checks);
        $display(" ===============================================");
    end
end

// Instruction checking logic
always @(posedge hclk_i) begin
    if (hresetn_i && id_instruction_valid_i && id_instruction_request_i && checker_enabled && checker_enable_i) begin

        // Only check instructions fetched from ROM — SRAM addresses may hold
        // runtime-generated code (e.g. self-modifying code) that is not in
        // checker_data.mem, so silently skip them.
        if (id_pc_i < ROM_BASE_ADDR || id_pc_i >= (ROM_BASE_ADDR + ROM_SIZE_BYTES*2)) begin
            // PC outside ROM range — skip
        end else begin

        // Calculate memory index for current PC: subtract ROM base, then divide by 2 (half-word address)
        // This supports compressed instructions on 2-byte boundaries
        mem_idx = ((id_pc_i - ROM_BASE_ADDR) >> 1) & (MEM_SIZE - 1);

        // Get expected data from memory
        exp_data = expected_data[mem_idx];
        exp_valid = exp_data[33];

        // Check if we have expected data for this PC (valid bit == 1)
        if (exp_valid === 1'b1) begin
            exp_is_compressed = exp_data[32];
            exp_inst = exp_data[31:0];

            // Determine if actual instruction is compressed
            // Compressed instructions have bits [1:0] != 2'b11
            act_is_compressed = (id_instruction_i[1:0] != 2'b11);

            // Prepare instructions for comparison
            if (act_is_compressed) begin
                // Compressed: compare lower 16 bits
                inst_to_check = {16'h0000, id_instruction_i[15:0]};
                exp_inst_to_check = {16'h0000, exp_inst[15:0]};
            end else begin
                // Standard: compare full 32 bits
                inst_to_check = id_instruction_i;
                exp_inst_to_check = exp_inst;
            end

            // Check for mismatch
            mismatch = (inst_to_check != exp_inst_to_check) ||
                       (act_is_compressed != exp_is_compressed);

            total_checks = total_checks + 1;

            if (mismatch) begin
                // Increment the testbench's global error counter
                tb_arvern.error = tb_arvern.error + 1;
                mismatch_count = mismatch_count + 1;

                $display("ERROR-VERILOG: [Instruction/PC Checker] Mismatch detected! (%t)", $time);
                $display("  PC:                    0x%08x", id_pc_i);
                $display("  Expected instruction:  0x%08x (%s)",
                         exp_inst,
                         exp_is_compressed ? "compressed" : "standard");
                $display("  Actual instruction:    0x%08x (%s)",
                         id_instruction_i,
                         act_is_compressed ? "compressed" : "standard");
                $display("");

                // Stop simulation if too many mismatches
                if (mismatch_count >= 40) begin
                    $display("");
                    $display(" ===============================================");
                    $display("|               SIMULATION STOPPED              |");
                    $display("|      [Instruction/PC Checker] Too many        |");
                    $display("|      mismatches detected (%0d errors)", mismatch_count);
                    $display(" ===============================================");
                    $display("");
                    $finish;
                end
            end
        end else begin
            // PC not found in checker data - this is an error
            tb_arvern.error = tb_arvern.error + 1;
            mismatch_count = mismatch_count + 1;

            $display("ERROR-VERILOG: [Instruction/PC Checker] Unexpected PC not in checker data! (%t)", $time);
            $display("  PC:          0x%08x", id_pc_i);
            $display("  Instruction: 0x%08x", id_instruction_i);
            $display("");

            // Stop simulation if too many mismatches
            if (mismatch_count >= 40) begin
                $display("");
                $display(" ===============================================");
                $display("|               SIMULATION STOPPED              |");
                $display("|      [Instruction/PC Checker] Too many        |");
                $display("|      mismatches detected (%0d errors)", mismatch_count);
                $display(" ===============================================");
                $display("");
                $finish;
            end
        end
        end // else: PC within ROM range
    end
end

endmodule

`endif // CHECKER_EN
