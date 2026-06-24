//----------------------------------------------------------------------------
//          _    _           Family:    aRVern System IPs
//         / \__/ \          Module:    probes_instructions
//        /   /\   \         --------------------------------------------
//    ===/   /=========      Copyright: (c) 2026, aRVern-dev
//      /   / RV \   \       Contact:   arvernsilicon@gmail.com
//     /___/______\___\      GitHub:    https://github.com/Arvern-Silicon
//
// SPDX-License-Identifier: BSD-3-Clause
// Full license text is available in the LICENSE file at the repository root.
//----------------------------------------------------------------------------
// File Name          : probes_instructions.v
// Module Description : Instruction-stream disassembler / asphalt.log producer.
//----------------------------------------------------------------------------

`ifndef ARV_CPU_INST
  `define ARV_CPU_INST dut
`endif

module probes_instructions #(
  // Clock period in nanoseconds — used for the time(ns) trace column.
  // Default matches the standard 1MHz simulation clock (#500 half-period).
  parameter CLK_PERIOD_NS = 1000
);

//..................................................................
// Auto-select compressed or standard instruction
//..................................................................
  function [8*64-1:0] instruction_str;
      input    [31:0] instr;
      input    [31:0] pc;

      reg  [8*64-1:0] decoded_str;
      reg       [1:0] opcode_low;
      reg      [15:0] c_half;

      begin

          // Compressed instructions have bits[1:0] != 2'b11
          if (instr[1:0] != 2'b11)
              decoded_str = c_instruction_str(instr[15:0]);
          else
              decoded_str = x_instruction_str(instr[31:0]);

          instruction_str = decoded_str;
      end
  endfunction

//..................................................................
// Decode standard instruction
//..................................................................
  function  [8*64-1:0] x_instruction_str;
      input     [31:0] instr;

      // Fields
      reg  [6:0] opcode;
      reg  [4:0] rd;
      reg  [2:0] funct3;
      reg  [4:0] rs1;
      reg  [4:0] rs2;
      reg  [6:0] funct7;
      reg [11:0] funct12;

      // Immediate extraction
      reg [31:0] imm_i;
      reg [31:0] imm_s;
      reg [31:0] imm_b;
      reg [31:0] imm_u;
      reg [31:0] imm_j;

      reg [8*64-1:0] decoded_str;

      begin

          // Fields
          opcode      = instr[6:0];
          rd          = instr[11:7];
          funct3      = instr[14:12];
          rs1         = instr[19:15];
          rs2         = instr[24:20];
          funct7      = instr[31:25];
          funct12     = instr[31:20];

          // Immediate extraction
          imm_i       = {{20{instr[31]}}, instr[31:20]};
          imm_s       = {{20{instr[31]}}, instr[31:25], instr[11:7]};
          imm_b       = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
          imm_u       = {instr[31:12], 12'b0};
          imm_j       = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};


          decoded_str = "UNKNOWN";
          case (opcode)
              // ------------------ R-type ------------------
              7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                  // M extension (funct7=0x01)
                  case (funct3)
                    3'b000:   $sformat(decoded_str, "MUL x%0d,x%0d,x%0d",   rd, rs1, rs2);
                    3'b001:   $sformat(decoded_str, "MULH x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b010:   $sformat(decoded_str, "MULHSU x%0d,x%0d,x%0d",rd, rs1, rs2);
                    3'b011:   $sformat(decoded_str, "MULHU x%0d,x%0d,x%0d", rd, rs1, rs2);
                    3'b100:   $sformat(decoded_str, "DIV x%0d,x%0d,x%0d",   rd, rs1, rs2);
                    3'b101:   $sformat(decoded_str, "DIVU x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b110:   $sformat(decoded_str, "REM x%0d,x%0d,x%0d",   rd, rs1, rs2);
                    3'b111:   $sformat(decoded_str, "REMU x%0d,x%0d,x%0d",  rd, rs1, rs2);
                  endcase
                end else if (funct7 == 7'b0010000) begin
                  // Zba extension: address generation instructions
                  case (funct3)
                    3'b010:   $sformat(decoded_str, "SH1ADD x%0d,x%0d,x%0d", rd, rs1, rs2);  // (rs1 << 1) + rs2
                    3'b100:   $sformat(decoded_str, "SH2ADD x%0d,x%0d,x%0d", rd, rs1, rs2);  // (rs1 << 2) + rs2
                    3'b110:   $sformat(decoded_str, "SH3ADD x%0d,x%0d,x%0d", rd, rs1, rs2);  // (rs1 << 3) + rs2
                    default:  decoded_str = "UNKNOWN";
                  endcase
                end else if (funct7 == 7'b0100000) begin
                  // Base ISA + Zbb logical-with-NOT
                  case (funct3)
                    3'b000:   $sformat(decoded_str, "SUB x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b111:   $sformat(decoded_str, "ANDN x%0d,x%0d,x%0d", rd, rs1, rs2);  // Zbb: rs1 & ~rs2
                    3'b110:   $sformat(decoded_str, "ORN x%0d,x%0d,x%0d",  rd, rs1, rs2);  // Zbb: rs1 | ~rs2
                    3'b100:   $sformat(decoded_str, "XNOR x%0d,x%0d,x%0d", rd, rs1, rs2);  // Zbb: rs1 ^ ~rs2
                    default:  decoded_str = "UNKNOWN";
                  endcase
                end else if (funct7 == 7'b0000101) begin
                  // Zbb: MIN/MAX instructions and Zbc: carry-less multiply
                  case (funct3)
                    3'b001:   $sformat(decoded_str, "CLMUL x%0d,x%0d,x%0d",  rd, rs1, rs2);  // Zbc: carry-less multiply (low)
                    3'b010:   $sformat(decoded_str, "CLMULR x%0d,x%0d,x%0d", rd, rs1, rs2);  // Zbc: carry-less multiply (reversed)
                    3'b011:   $sformat(decoded_str, "CLMULH x%0d,x%0d,x%0d", rd, rs1, rs2);  // Zbc: carry-less multiply (high)
                    3'b100:   $sformat(decoded_str, "MIN x%0d,x%0d,x%0d",    rd, rs1, rs2);  // Zbb: signed min
                    3'b101:   $sformat(decoded_str, "MINU x%0d,x%0d,x%0d",   rd, rs1, rs2);  // Zbb: unsigned min
                    3'b110:   $sformat(decoded_str, "MAX x%0d,x%0d,x%0d",    rd, rs1, rs2);  // Zbb: signed max
                    3'b111:   $sformat(decoded_str, "MAXU x%0d,x%0d,x%0d",   rd, rs1, rs2);  // Zbb: unsigned max
                    default:  decoded_str = "UNKNOWN";
                  endcase
                end else if (funct7 == 7'b0110000) begin
                  // Zbb: rotate instructions
                  case (funct3)
                    3'b001:   $sformat(decoded_str, "ROL x%0d,x%0d,x%0d",  rd, rs1, rs2);   // rotate left
                    3'b101:   $sformat(decoded_str, "ROR x%0d,x%0d,x%0d",  rd, rs1, rs2);   // rotate right
                    default:  decoded_str = "UNKNOWN";
                  endcase
                end else if (funct7 == 7'b0000100 && funct3 == 3'b100 && rs2 == 5'b00000) begin
                  $sformat(decoded_str, "ZEXT.H x%0d,x%0d", rd, rs1);  // Zbb: zero-extend halfword
                end else if (funct7 == 7'b0100100 && funct3 == 3'b001) begin
                  $sformat(decoded_str, "BCLR x%0d,x%0d,x%0d", rd, rs1, rs2);   // Zbs: clear bit
                end else if (funct7 == 7'b0100100 && funct3 == 3'b101) begin
                  $sformat(decoded_str, "BEXT x%0d,x%0d,x%0d", rd, rs1, rs2);   // Zbs: extract bit
                end else if (funct7 == 7'b0110100 && funct3 == 3'b001) begin
                  $sformat(decoded_str, "BINV x%0d,x%0d,x%0d", rd, rs1, rs2);   // Zbs: invert bit
                end else if (funct7 == 7'b0010100 && funct3 == 3'b001) begin
                  $sformat(decoded_str, "BSET x%0d,x%0d,x%0d", rd, rs1, rs2);   // Zbs: set bit
                end else begin
                  // Base ISA
                  case (funct3)
                    3'b000:   $sformat(decoded_str, "ADD x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b111:   $sformat(decoded_str, "AND x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b110:   $sformat(decoded_str, "OR x%0d,x%0d,x%0d",   rd, rs1, rs2);
                    3'b100:   $sformat(decoded_str, "XOR x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b001:   $sformat(decoded_str, "SLL x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b101:   if (funct7 == 7'b0100000)
                                $sformat(decoded_str, "SRA x%0d,x%0d,x%0d", rd, rs1, rs2);
                              else
                                $sformat(decoded_str, "SRL x%0d,x%0d,x%0d", rd, rs1, rs2);
                    3'b010:   $sformat(decoded_str, "SLT x%0d,x%0d,x%0d",  rd, rs1, rs2);
                    3'b011:   $sformat(decoded_str, "SLTU x%0d,x%0d,x%0d", rd, rs1, rs2);
                  endcase
                end
              end

              // ------------------ I-type ------------------
              7'b0010011: begin
                case (funct3)
                  3'b000: $sformat(decoded_str, "ADDI x%0d,x%0d,%0d",     rd, rs1, $signed(imm_i));  // signed
                  3'b010: $sformat(decoded_str, "SLTI x%0d,x%0d,%0d",     rd, rs1, $signed(imm_i));  // signed
                  3'b011: $sformat(decoded_str, "SLTIU x%0d,x%0d,0x%0h",  rd, rs1, imm_i);           // unsigned
                  3'b100: $sformat(decoded_str, "XORI x%0d,x%0d,0x%0h", rd, rs1, imm_i);
                  3'b110: $sformat(decoded_str, "ORI x%0d,x%0d,0x%0h",    rd, rs1, imm_i);           // unsigned
                  3'b111: $sformat(decoded_str, "ANDI x%0d,x%0d,0x%0h",   rd, rs1, imm_i);           // unsigned
                  3'b001: begin
                    // SLLI, Zbb count/sign-extend, and Zbs BCLRI/BINVI/BSETI
                    if (funct12 == 12'b011000000000)
                      $sformat(decoded_str, "CLZ x%0d,x%0d", rd, rs1);     // Zbb: count leading zeros
                    else if (funct12 == 12'b011000000001)
                      $sformat(decoded_str, "CTZ x%0d,x%0d", rd, rs1);     // Zbb: count trailing zeros
                    else if (funct12 == 12'b011000000010)
                      $sformat(decoded_str, "CPOP x%0d,x%0d", rd, rs1);    // Zbb: count population (set bits)
                    else if (funct12 == 12'b011000000100)
                      $sformat(decoded_str, "SEXT.B x%0d,x%0d", rd, rs1);  // Zbb: sign-extend byte
                    else if (funct12 == 12'b011000000101)
                      $sformat(decoded_str, "SEXT.H x%0d,x%0d", rd, rs1);  // Zbb: sign-extend halfword
                    else if (funct7 == 7'b0100100)
                      $sformat(decoded_str, "BCLRI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);  // Zbs: clear bit immediate
                    else if (funct7 == 7'b0110100)
                      $sformat(decoded_str, "BINVI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);  // Zbs: invert bit immediate
                    else if (funct7 == 7'b0010100)
                      $sformat(decoded_str, "BSETI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);  // Zbs: set bit immediate
                    else
                      $sformat(decoded_str, "SLLI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);
                  end
                  3'b101: begin
                    // SRLI, SRAI, Zbb rotates/byte-ops, and Zbs BEXTI
                    if (funct12 == 12'b011010011000)
                      $sformat(decoded_str, "REV8 x%0d,x%0d", rd, rs1);    // Zbb: reverse bytes (endian swap)
                    else if (funct12 == 12'b001010000111)
                      $sformat(decoded_str, "ORC.B x%0d,x%0d", rd, rs1);   // Zbb: OR-combine bytes
                    else if (funct7 == 7'b0110000)
                      $sformat(decoded_str, "RORI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);  // Zbb: rotate right immediate
                    else if (funct7 == 7'b0100100)
                      $sformat(decoded_str, "BEXTI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]); // Zbs: extract bit immediate
                    else if (funct7 == 7'b0100000)
                      $sformat(decoded_str, "SRAI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);
                    else
                      $sformat(decoded_str, "SRLI x%0d,x%0d,0x%0h", rd, rs1, instr[24:20]);
                  end
                endcase
              end

              // ------------------ Loads & Stores ------------------
              7'b0000011: begin
                case (funct3)
                  3'b000: $sformat(decoded_str, "LB x%0d,%0d(x%0d)",  rd,  $signed(imm_i), rs1); // signed offset
                  3'b001: $sformat(decoded_str, "LH x%0d,%0d(x%0d)",  rd,  $signed(imm_i), rs1); // signed offset
                  3'b010: $sformat(decoded_str, "LW x%0d,%0d(x%0d)",  rd,  $signed(imm_i), rs1); // signed offset
                  3'b100: $sformat(decoded_str, "LBU x%0d,%0d(x%0d)", rd,  $signed(imm_i), rs1); // signed offset
                  3'b101: $sformat(decoded_str, "LHU x%0d,%0d(x%0d)", rd,  $signed(imm_i), rs1); // signed offset
                  default: decoded_str = "UNKNOWN";
                endcase
              end
              7'b0100011: begin
                case (funct3)
                  3'b000: $sformat(decoded_str, "SB x%0d,%0d(x%0d)", rs2, $signed(imm_s), rs1);
                  3'b001: $sformat(decoded_str, "SH x%0d,%0d(x%0d)", rs2, $signed(imm_s), rs1);
                  3'b010: $sformat(decoded_str, "SW x%0d,%0d(x%0d)", rs2, $signed(imm_s), rs1);
                  default: decoded_str = "UNKNOWN";
                endcase
              end

              // ------------------ Branches ------------------
              7'b1100011: begin
                case (funct3)
                  3'b000: $sformat(decoded_str, "BEQ x%0d,x%0d,%0d",    rs1, rs2, $signed(imm_b));
                  3'b001: $sformat(decoded_str, "BNE x%0d,x%0d,%0d",    rs1, rs2, $signed(imm_b));
                  3'b100: $sformat(decoded_str, "BLT x%0d,x%0d,%0d",    rs1, rs2, $signed(imm_b));
                  3'b101: $sformat(decoded_str, "BGE x%0d,x%0d,%0d",    rs1, rs2, $signed(imm_b));
                  3'b110: $sformat(decoded_str, "BLTU x%0d,x%0d,0x%0h", rs1, rs2, imm_b); // unsigned
                  3'b111: $sformat(decoded_str, "BGEU x%0d,x%0d,0x%0h", rs1, rs2, imm_b); // unsigned
                  default: decoded_str = "UNKNOWN";
                endcase
              end

              // ------------------ MISCMEM-FENCE ------------------
              7'b0001111: begin
                case (funct3)
                  3'b000: if (funct12 == {4'b1000, 4'b0011, 4'b0011})
                            decoded_str = "FENCE.TSO";
                          else if (funct12 == {4'b0000, 4'b0001, 4'b0000})
                            decoded_str = "PAUSE";
                          else if (instr[31:28] == 4'b0000) begin
                            $sformat(decoded_str, "FENCE %s%s%s%s,%s%s%s%s", instr[27] ? "i" : "",
                                                                             instr[26] ? "o" : "",
                                                                             instr[25] ? "r" : "",
                                                                             instr[24] ? "w" : "",
                                                                             instr[23] ? "i" : "",
                                                                             instr[22] ? "o" : "",
                                                                             instr[21] ? "r" : "",
                                                                             instr[20] ? "w" : "");
                          end
                          else
                            decoded_str = "FENCE";
                  3'b001: decoded_str = "FENCE.I";
                  3'b100: decoded_str = "UNKNOWN";
                  3'b101: decoded_str = "UNKNOWN";
                  3'b110: decoded_str = "UNKNOWN";
                  3'b111: decoded_str = "UNKNOWN";
                  default: decoded_str = "UNKNOWN";
                endcase
              end

              // ------------------ Jumps & Upper immediates ------------------
              7'b1101111: $sformat(decoded_str, "JAL x%0d,%0d",        rd, $signed(imm_j));
              7'b1100111: $sformat(decoded_str, "JALR x%0d,%0d(x%0d)", rd, $signed(imm_i), rs1);
              7'b0110111: $sformat(decoded_str, "LUI x%0d,0x%0h",      rd, imm_u);
              7'b0010111: $sformat(decoded_str, "AUIPC x%0d,0x%0h",    rd, imm_u);

              // --------------------------- SYSTEM ---------------------------
              7'b1110011: begin
                case (funct3)
                  3'b000: begin
                    if (funct12==12'h000)
                        decoded_str = "ECALL";
                    else if (funct12==12'h001)
                        decoded_str = "EBREAK";
                    else if (funct12==12'h302)
                        decoded_str = "MRET";
                    else if (funct12==12'h102)
                        decoded_str = "SRET";
                    else if (funct12==12'h105)
                        decoded_str = "WFI";
                    else if (funct12==12'h702)
                        decoded_str = "MNRET";
                    else
                        decoded_str = "UNKNOWN";
                  end
                  3'b001: $sformat(decoded_str, "CSRRW x%0d,x%0d,@%0h",  rd, rs1, funct12);
                  3'b010: $sformat(decoded_str, "CSRRS x%0d,x%0d,@%0h",  rd, rs1, funct12);
                  3'b011: $sformat(decoded_str, "CSRRC x%0d,x%0d,@%0h",  rd, rs1, funct12);
                  3'b100: decoded_str = "UNKNOWN";
                  3'b101: $sformat(decoded_str, "CSRRWI x%0d,#%0h,@%0h", rd, rs1, funct12);
                  3'b110: $sformat(decoded_str, "CSRRSI x%0d,#%0h,@%0h", rd, rs1, funct12);
                  3'b111: $sformat(decoded_str, "CSRRCI x%0d,#%0h,@%0h", rd, rs1, funct12);
                endcase
              end

              // ------------------ Default for unknown opcodes ------------------
              default: decoded_str = "UNKNOWN";

            endcase

          // Some aliases
          case (decoded_str)
            "ADDI x0,x0,0" : decoded_str = "NOP";
          endcase

          x_instruction_str = (instr==32'h00000000) ? "-" : decoded_str;

      end
  endfunction

//..................................................................
// Decode compressed instruction
//..................................................................
  function [8*64-1:0] c_instruction_str;
    input [15:0] c_instr;

    // Common fields
    reg [1:0]  opcode;
    reg [2:0]  funct3;
    reg [4:0]  rd, rs1, rs2;
    reg [4:0]  rd_rs1p, rs1p, rs2p;
    reg [31:0] imm;
    reg [8*64-1:0] decoded_str;
    reg [7:0] stack_adj_base;
    reg [7:0] stack_adj_total;

    begin
      // Extract fixed fields
      opcode  = c_instr[1:0];
      funct3  = c_instr[15:13];

      // Compressed register aliases (x8–x15)
      rd_rs1p = {2'b01, c_instr[9:7]};
      rs1p    = {2'b01, c_instr[9:7]};
      rs2p    = {2'b01, c_instr[4:2]};

      // Standard registers (used by some C formats)
      rd      = c_instr[11:7];
      rs1     = c_instr[11:7];
      rs2     = c_instr[6:2];

      decoded_str = "UNKNOWN_C";

      //------------------------------------------------------------
      // Quadrant 0 (opcode[1:0] == 2'b00)
      //------------------------------------------------------------
      if (opcode == 2'b00) begin
        case (funct3)
          3'b000: $sformat(decoded_str, "C.ADDI4SPN x%0d, sp, 0x%0h", rs2p, {c_instr[10:7], c_instr[12:11], c_instr[5], c_instr[6], 2'b00});
          3'b010: $sformat(decoded_str, "C.LW x%0d, 0x%0h(x%0d)",     rs2p, {c_instr[5], c_instr[12:10], c_instr[6], 2'b00}, rs1p);
          3'b100: begin
            // Zcb extension: additional load/store instructions
            case (c_instr[12:10])
              3'b000: $sformat(decoded_str, "C.LBU x%0d, 0x%0h(x%0d)",  rs2p, {c_instr[5], c_instr[6]}, rs1p);
              3'b001: if (c_instr[6] == 1'b0)
                        $sformat(decoded_str, "C.LHU x%0d, 0x%0h(x%0d)", rs2p, {c_instr[5], 1'b0}, rs1p);
                      else
                        $sformat(decoded_str, "C.LH x%0d, 0x%0h(x%0d)",  rs2p, {c_instr[5], 1'b0}, rs1p);
              3'b010: $sformat(decoded_str, "C.SB x%0d, 0x%0h(x%0d)",   rs2p, {c_instr[5], c_instr[6]}, rd_rs1p);
              3'b011: $sformat(decoded_str, "C.SH x%0d, 0x%0h(x%0d)",   rs2p, {c_instr[5], 1'b0}, rd_rs1p);
              default: decoded_str = "ILLEGAL_C0_ZCB";
            endcase
          end
          3'b110: $sformat(decoded_str, "C.SW x%0d, 0x%0h(x%0d)",     rs2p,    {c_instr[5], c_instr[12:10], c_instr[6], 2'b00}, rd_rs1p);
          default: decoded_str = "ILLEGAL_C0";
        endcase
      end

      //------------------------------------------------------------
      // Quadrant 1 (opcode[1:0] == 2'b01)
      //------------------------------------------------------------
      else if (opcode == 2'b01) begin
        case (funct3)
          3'b000: begin
            if (rd == 0 && c_instr[6:2] == 5'b00000) decoded_str = "C.NOP";
            else $sformat(decoded_str, "C.ADDI x%0d, %0d", rd, $signed({{26{c_instr[12]}}, c_instr[12], c_instr[6:2]}));
          end
          3'b001: $sformat(decoded_str, "C.JAL %0d", $signed({{21{c_instr[12]}}, c_instr[12], c_instr[8], c_instr[10:9], c_instr[6], c_instr[7], c_instr[2], c_instr[11], c_instr[5:3], 1'b0}));
          3'b010: $sformat(decoded_str, "C.LI x%0d, %0d",   rd, $signed({{26{c_instr[12]}}, c_instr[12], c_instr[6:2]}));
          3'b011: begin
            if (rd == 5'd2) $sformat(decoded_str, "C.ADDI16SP sp, %0d", $signed({{23{c_instr[12]}}, c_instr[12], c_instr[4:3], c_instr[5], c_instr[2], c_instr[6], 4'b0}));
            else            $sformat(decoded_str, "C.LUI x%0d, 0x%0h",  rd, {c_instr[12], c_instr[6:2]});
          end
          3'b100: begin
            // This funct3 handles several arithmetic subops including Zcb extensions
            if (c_instr[11:10] == 2'b00)      $sformat(decoded_str, "C.SRLI x%0d, %0d", rs1p, {c_instr[12], c_instr[6:2]});
            else if (c_instr[11:10] == 2'b01) $sformat(decoded_str, "C.SRAI x%0d, %0d", rs1p, {c_instr[12], c_instr[6:2]});
            else if (c_instr[11:10] == 2'b10) $sformat(decoded_str, "C.ANDI x%0d, %0d", rs1p, $signed({{26{c_instr[12]}}, c_instr[12], c_instr[6:2]}));
            else begin
              // c_instr[11:10] == 2'b11
              case ({c_instr[12], c_instr[6:5]})
                3'b000: $sformat(decoded_str, "C.SUB x%0d, x%0d", rd_rs1p, rs2p);
                3'b001: $sformat(decoded_str, "C.XOR x%0d, x%0d", rd_rs1p, rs2p);
                3'b010: $sformat(decoded_str, "C.OR x%0d, x%0d",  rd_rs1p, rs2p);
                3'b011: $sformat(decoded_str, "C.AND x%0d, x%0d", rd_rs1p, rs2p);
                3'b111: begin
                  // Zcb unary operations: c_instr[12]=1, c_instr[6:5]=2'b11
                  case (c_instr[4:2])
                    3'b000: $sformat(decoded_str, "C.ZEXT.B x%0d", rd_rs1p);  // c_instr[6:2]=5'b11000
                    3'b001: $sformat(decoded_str, "C.SEXT.B x%0d", rd_rs1p);  // c_instr[6:2]=5'b11001
                    3'b010: $sformat(decoded_str, "C.ZEXT.H x%0d", rd_rs1p);  // c_instr[6:2]=5'b11010
                    3'b011: $sformat(decoded_str, "C.SEXT.H x%0d", rd_rs1p);  // c_instr[6:2]=5'b11011
                    3'b101: $sformat(decoded_str, "C.NOT x%0d",    rd_rs1p);  // c_instr[6:2]=5'b11101
                    default: decoded_str = "ILLEGAL_C1_ZCB";
                  endcase
                end
                3'b110: $sformat(decoded_str, "C.MUL x%0d, x%0d", rd_rs1p, rs2p);  // Zcb: c_instr[12]=1, c_instr[6:5]=2'b10
                default: decoded_str = "ILLEGAL_C_ARITH";
              endcase
            end
          end
          3'b101: $sformat(decoded_str, "C.J  %0d",               $signed({{21{c_instr[12]}}, c_instr[12], c_instr[8],   c_instr[10:9], c_instr[6], c_instr[7], c_instr[2], c_instr[11], c_instr[5:3], 1'b0}));
          3'b110: $sformat(decoded_str, "C.BEQZ x%0d, %0d", rs1p, $signed({{23{c_instr[12]}}, c_instr[12], c_instr[6:5], c_instr[2], c_instr[11:10], c_instr[4:3], 1'b0}));
          3'b111: $sformat(decoded_str, "C.BNEZ x%0d, %0d", rs1p, $signed({{23{c_instr[12]}}, c_instr[12], c_instr[6:5], c_instr[2], c_instr[11:10], c_instr[4:3], 1'b0}));
          default: decoded_str = "ILLEGAL_C1";
        endcase
      end

      //------------------------------------------------------------
      // Quadrant 2 (opcode[1:0] == 2'b10)
      //------------------------------------------------------------
      else if (opcode == 2'b10) begin
        case (funct3)
          3'b000: $sformat(decoded_str, "C.SLLI x%0d, %0d",       rd, {c_instr[12], c_instr[6:2]});
          3'b010: $sformat(decoded_str, "C.LWSP x%0d, 0x%0h(sp)", rd, {c_instr[3:2], c_instr[12], c_instr[6:4], 2'b00});
          3'b100: begin
            if (c_instr[12] == 1'b1 && rd == 0 && rs2 == 0)  decoded_str = "C.EBREAK";
            else if (c_instr[12] == 1'b0 && rs2 != 0)        $sformat(decoded_str, "C.MV x%0d, x%0d", rd, rs2);
            else if (c_instr[12] == 1'b1 && rs2 != 0)        $sformat(decoded_str, "C.ADD x%0d, x%0d", rd, rs2);
            else if (c_instr[12] == 1'b0 && rs2 == 0)        $sformat(decoded_str, "C.JR x%0d", rs1);
            else if (c_instr[12] == 1'b1 && rs2 == 0)        $sformat(decoded_str, "C.JALR x%0d", rs1);
            else                                             decoded_str = "ILLEGAL_C2";
          end
          3'b110:  $sformat(decoded_str, "C.SWSP x%0d, 0x%0h(sp)", rs2, {c_instr[8:7], c_instr[12:9], 2'b00});
          3'b101: begin
            // Compute Zcmp stack adjustment for push/pop instructions (RV32)
            // stack_adj = stack_adj_base(rlist) + spimm * 16
            case (c_instr[7:4])
              4'd4, 4'd5, 4'd6, 4'd7:     stack_adj_base = 8'd16;
              4'd8, 4'd9, 4'd10, 4'd11:   stack_adj_base = 8'd32;
              4'd12, 4'd13, 4'd14:        stack_adj_base = 8'd48;
              4'd15:                       stack_adj_base = 8'd64;
              default:                     stack_adj_base = 8'd16;
            endcase
            stack_adj_total = stack_adj_base + {2'b00, c_instr[3:2], 4'b0000};

            // Zcmp and Zcmt instructions (use funct6 = bits[15:10])
            case (c_instr[15:10])
              6'b101000: if (c_instr[9:7] == 3'b000)                                                                     // Zcmt
                             $sformat(decoded_str, "CM.JT %0d",   c_instr[9:2]);                                        // index 0..31
                         else
                             $sformat(decoded_str, "CM.JALT %0d", c_instr[9:2]);                                        // index 32..255
              6'b101011: begin
                if (c_instr[6:5] == 2'b11)      $sformat(decoded_str, "CM.MVA01S x%0d,x%0d",  // Zcmp: a0=s(r1s'), a1=s(r2s')
                    (c_instr[9:7] <= 3'd1) ? 5'd8  + {2'b0,c_instr[9:7]} : 5'd16 + {2'b0,c_instr[9:7]},
                    (c_instr[4:2] <= 3'd1) ? 5'd8  + {2'b0,c_instr[4:2]} : 5'd16 + {2'b0,c_instr[4:2]});
                else if (c_instr[6:5] == 2'b01) $sformat(decoded_str, "CM.MVSA01 x%0d,x%0d",  // Zcmp: s(r1s')=a0, s(r2s')=a1
                    (c_instr[9:7] <= 3'd1) ? 5'd8  + {2'b0,c_instr[9:7]} : 5'd16 + {2'b0,c_instr[9:7]},
                    (c_instr[4:2] <= 3'd1) ? 5'd8  + {2'b0,c_instr[4:2]} : 5'd16 + {2'b0,c_instr[4:2]});
                else                            decoded_str = "ILLEGAL_C2_ZCMP";
              end
              6'b101110: begin  // CM.PUSH ([9:8]=00) or CM.POP ([9:8]=10)
                // rlist encoding: 4={ra}, 5={ra,s0}, 6={ra,s0-s1}, ..., 15={ra,s0-s11}
                if (c_instr[9:8] == 2'b00) begin  // CM.PUSH
                  if (c_instr[7:4] == 4'd4)
                    $sformat(decoded_str, "CM.PUSH {ra}, -%0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd5)
                    $sformat(decoded_str, "CM.PUSH {ra, s0}, -%0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd15)
                    $sformat(decoded_str, "CM.PUSH {ra, s0-s11}, -%0d", stack_adj_total);
                  else
                    $sformat(decoded_str, "CM.PUSH {ra, s0-s%0d}, -%0d", (c_instr[7:4]-4'd5), stack_adj_total);
                end else if (c_instr[9:8] == 2'b10) begin  // CM.POP
                  if (c_instr[7:4] == 4'd4)
                    $sformat(decoded_str, "CM.POP {ra}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd5)
                    $sformat(decoded_str, "CM.POP {ra, s0}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd15)
                    $sformat(decoded_str, "CM.POP {ra, s0-s11}, %0d", stack_adj_total);
                  else
                    $sformat(decoded_str, "CM.POP {ra, s0-s%0d}, %0d", (c_instr[7:4]-4'd5), stack_adj_total);
                end else
                  decoded_str = "ILLEGAL_C2_ZCMP";
              end
              6'b101111: begin  // CM.POPRETZ ([9:8]=00) or CM.POPRET ([9:8]=10)
                // rlist encoding: 4={ra}, 5={ra,s0}, 6={ra,s0-s1}, ..., 15={ra,s0-s11}
                if (c_instr[9:8] == 2'b10) begin  // CM.POPRET
                  if (c_instr[7:4] == 4'd4)
                    $sformat(decoded_str, "CM.POPRET {ra}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd5)
                    $sformat(decoded_str, "CM.POPRET {ra, s0}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd15)
                    $sformat(decoded_str, "CM.POPRET {ra, s0-s11}, %0d", stack_adj_total);
                  else
                    $sformat(decoded_str, "CM.POPRET {ra, s0-s%0d}, %0d", (c_instr[7:4]-4'd5), stack_adj_total);
                end else if (c_instr[9:8] == 2'b00) begin  // CM.POPRETZ
                  if (c_instr[7:4] == 4'd4)
                    $sformat(decoded_str, "CM.POPRETZ {ra}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd5)
                    $sformat(decoded_str, "CM.POPRETZ {ra, s0}, %0d", stack_adj_total);
                  else if (c_instr[7:4] == 4'd15)
                    $sformat(decoded_str, "CM.POPRETZ {ra, s0-s11}, %0d", stack_adj_total);
                  else
                    $sformat(decoded_str, "CM.POPRETZ {ra, s0-s%0d}, %0d", (c_instr[7:4]-4'd5), stack_adj_total);
                end else
                  decoded_str = "ILLEGAL_C2_ZCMP";
              end
              default:   decoded_str = "ILLEGAL_C2_ZCMP_ZCMT";
            endcase
          end
          default: decoded_str = "ILLEGAL_C2";
        endcase
      end

      else begin
        decoded_str = "NOT_COMPRESSED";
      end

      c_instruction_str = decoded_str;
    end
  endfunction


  //................................ INSTRUCTION DECODING STAGE ..................................

  reg   [8*64-1:0] instr_id; // 64-character string buffer
  wire      [31:0] pc_id;
  wire      [31:0] bin_id;

  // When a UOP instruction with a branch (cm.jt, cm.jalt, cm.popret, cm.popretz) is executing,
  // the instruction visible in the ID stage will be killed by the branch — hide it.
  wire uop_branch_active = `ARV_CPU_INST.arv_decode_inst.ex_uop_has_branch;

  assign pc_id    = `ARV_CPU_INST.arv_decode_inst.id_pc_i;
  assign bin_id   = `ARV_CPU_INST.arv_decode_inst.id_instruction_i;
  always @(pc_id or bin_id or `ARV_CPU_INST.arv_decode_inst.id_instruction_valid_i or uop_branch_active)
      if (uop_branch_active)
          instr_id = "---";
      else if (`ARV_CPU_INST.arv_decode_inst.id_instruction_valid_i)
          instr_id = (bin_id==32'h00000000) ? "idle" : instruction_str(bin_id, pc_id);
      else
          instr_id = "---";   // fetch not yet valid (e.g. second cycle of misaligned 32-bit fetch)

  //...................................... EXECUTION STAGE .......................................

  wire  [8*64-1:0] instr_ex; // 64-character string buffer
  reg       [31:0] pc_ex;
  reg       [31:0] bin_ex;

  // Combined ready signal for all execution units
  // This automatically handles ALU, load-store, µop sequencer, and any future execution units
  wire ex_all_ready = `ARV_CPU_INST.arv_decode_inst.ex_alu_ready_i &
                      `ARV_CPU_INST.arv_decode_inst.ex_ldst_ready_i &
                      `ARV_CPU_INST.arv_decode_inst.ex_uop_ready_i;

  // Dispatch condition: advance EX only when pipeline dispatches a real instruction,
  // and not during a UOP-branch cycle (the ID instruction is about to be squashed).
  wire ex_dispatch = `ARV_CPU_INST.arv_decode_inst.id_instruction_request_o &
                     `ARV_CPU_INST.arv_decode_inst.id_opcode_valid           &
                     ~uop_branch_active;

  always @(posedge `ARV_CPU_INST.arv_decode_inst.hclk_i or negedge `ARV_CPU_INST.arv_decode_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_decode_inst.hresetn_i)  pc_ex  <= 32'h00000000;
    else if (ex_dispatch)                pc_ex  <= pc_id;
    else if (ex_all_ready)               pc_ex  <= 32'h00000000;

  always @(posedge `ARV_CPU_INST.arv_decode_inst.hclk_i or negedge `ARV_CPU_INST.arv_decode_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_decode_inst.hresetn_i)  bin_ex <= 32'h00000000;
    else if (ex_dispatch)                bin_ex <= bin_id;
    else if (ex_all_ready)               bin_ex <= 32'h00000000;

  // Distinguish pipeline bubbles (redirect penalty) from truly idle EX stage.
  // id_branch_detect_o fires on the dispatch cycle; bin_ex clears one cycle later,
  // so delay by 1 to align the bubble flag with the empty slot.
  reg  id_branch_detect_dly;
  always @(posedge `ARV_CPU_INST.arv_decode_inst.hclk_i or negedge `ARV_CPU_INST.arv_decode_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_decode_inst.hresetn_i) id_branch_detect_dly <= 1'b0;
    else                                id_branch_detect_dly <= `ARV_CPU_INST.arv_decode_inst.id_branch_detect_o;

  reg  branch_bubble;
  always @(posedge `ARV_CPU_INST.arv_decode_inst.hclk_i or negedge `ARV_CPU_INST.arv_decode_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_decode_inst.hresetn_i) branch_bubble <= 1'b0;
    else if (ex_dispatch)               branch_bubble <= 1'b0;  // real instruction arrived
    else if (id_branch_detect_dly)      branch_bubble <= 1'b1;  // empty slot after redirect

  assign instr_ex = (bin_ex != 32'h00000000) ? instruction_str(bin_ex, pc_ex) :
                    branch_bubble             ? "---"
                                              : "idle";

  //........................................ WRITE-BACK ..........................................

  wire  [8*64-1:0] instr_wb; // 64-character string buffer
  reg       [31:0] pc_wb;
  reg       [31:0] bin_wb;

  always @(posedge `ARV_CPU_INST.arv_load_store_inst.hclk_i or negedge `ARV_CPU_INST.arv_load_store_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_load_store_inst.hresetn_i)      pc_wb  <= 32'h00000000;
    else if (`ARV_CPU_INST.arv_load_store_inst.aph_valid)  pc_wb  <= pc_ex;
    else if (`ARV_CPU_INST.arv_load_store_inst.dph_last)   pc_wb  <= 32'h00000000;

  always @(posedge `ARV_CPU_INST.arv_load_store_inst.hclk_i or negedge `ARV_CPU_INST.arv_load_store_inst.hresetn_i)
    if (!`ARV_CPU_INST.arv_load_store_inst.hresetn_i)      bin_wb <= 32'h00000000;
    else if (`ARV_CPU_INST.arv_load_store_inst.aph_valid)  bin_wb <= bin_ex;
    else if (`ARV_CPU_INST.arv_load_store_inst.dph_last)   bin_wb <= 32'h00000000;

  assign instr_wb = (bin_wb==32'h00000000) ? "idle" : instruction_str(bin_wb, pc_wb);

  //..............................................................................................

  //................................ EXECUTION TRACE LOGGER .....................................
  //
  // Logs one line per dispatched instruction to asphalt.log.
  // Disabled by defining NOTRACE (e.g. during regressions) to avoid large files.
  //
  // Column format (space-separated):
  //   cycle  pc  instr  mnemonic  mem  mem_addr  mem_data  tgt_reg  sz  br
  //
  //   cycle    : clock cycle at dispatch
  //   pc       : program counter (hex)
  //   instr    : raw instruction encoding (hex)
  //   mnemonic : decoded instruction string (left-aligned, 32-char pad)
  //   mem      : R (load), W (store), or - (no memory access)
  //   mem_addr : AHB address (hex) or -
  //   mem_data : raw AHB bus data (hex) or -.
  //              NOTE: for loads (LB/LBU/LH/LHU), this is the full 32-bit
  //              bus word; see tgt_reg for the sign/zero-extended byte/half.
  //   tgt_reg  : destination register: x<n>=0x<val> for loads/ALU writes,
  //              [x<n>] for store source register, or - if none.
  //   sz       : instruction size in bytes (2=compressed, 4=standard)
  //   br       : branch outcome: T=taken, N=not-taken, - for non-branches
  //   priv     : privilege mode at dispatch: M=machine, S=supervisor, U=user
  //
  //   Zcmp multi-memory instructions (CM.PUSH/POP/POPRET/POPRETZ, CM.JT/JALT)
  //   append a trailing comment: # <N> mem ops
  //
  // Post-processing tips:
  //   - CPI per instruction: gap in cycle between consecutive lines
  //   - Instruction mix:     histogram on mnemonic field (awk/python)
  //   - Hot PCs:             sort+count on pc field
  //..............................................................................................

`ifndef NOTRACE

  integer      trace_fd;
  reg   [63:0] trace_cycle;

  wire         trace_clk    = `ARV_CPU_INST.arv_decode_inst.hclk_i;
  wire         trace_resetn = `ARV_CPU_INST.arv_decode_inst.hresetn_i;
  wire         trace_valid  = `ARV_CPU_INST.arv_decode_inst.id_instruction_request_o &
                              `ARV_CPU_INST.arv_decode_inst.id_opcode_valid            &
                              ~uop_branch_active;

  // Privilege mode at instruction decode stage
  wire   [1:0] trace_priv   = `ARV_CPU_INST.arv_decode_inst.id_priv_mode_i;

  // Trap detection signals from CSR/traps module
  wire         trace_trap_taken  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_taken;
  wire         trace_trap_is_irq = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_irq;
  wire         trace_trap_is_nmi = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_is_nmi;
  wire   [4:0] trace_trap_cause  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.trap_cause_latched;
  wire         trace_mret_taken  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mret_taken;
  wire         trace_sret_taken  = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.sret_taken;
  wire         trace_mnret_taken = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mnret_taken;
  // irqkill: trap_kill_muldiv/uop fires combinatorially in the same cycle as trap_taken
  // (because the kill makes pipeline_drained_for_irq immediately true), so
  // muldiv_kill_suppress/uop_kill_suppress — which are registered — are still 0 at
  // that posedge.  OR in the combinatorial kill outputs to catch this first-cycle case.
  wire         trace_kill_muldiv = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.muldiv_kill_suppress
                                 | `ARV_CPU_INST.trap_kill_muldiv;
  wire         trace_kill_uop    = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.uop_kill_suppress
                                 | `ARV_CPU_INST.trap_kill_uop;

  // Detect load/store from instruction encoding at dispatch time.
  // Compressed Q0: funct3=010 (C.LW), 110 (C.SW), 100 (Zcb C.LBU/LH/LHU/SB/SH)
  // Compressed Q2: funct3=010 (C.LWSP), 110 (C.SWSP)
  // Standard:      opcode=0000011 (LOAD), 0100011 (STORE)
  wire trace_is_ls = (bin_id[1:0] == 2'b11) ?
                       (bin_id[6:0] == 7'b0000011 || bin_id[6:0] == 7'b0100011)
                   : (bin_id[1:0] == 2'b00) ?
                       (bin_id[15:13] == 3'b010 || bin_id[15:13] == 3'b110 || bin_id[15:13] == 3'b100)
                   : (bin_id[1:0] == 2'b10) ?
                       (bin_id[15:13] == 3'b010 || bin_id[15:13] == 3'b110)
                   : 1'b0;

  // Detect conditional branch at dispatch time.
  // Standard: opcode=1100011 (BEQ/BNE/BLT/BGE/BLTU/BGEU)
  // Compressed Q1: funct3=110 (C.BEQZ), 111 (C.BNEZ)
  wire trace_is_branch = (bin_id[1:0] == 2'b11) ?
                            (bin_id[6:0] == 7'b1100011)
                        : (bin_id[1:0] == 2'b01) ?
                            (bin_id[15:13] == 3'b110 || bin_id[15:13] == 3'b111)
                        : 1'b0;

  // Register write signals from the execute stage.
  // These are valid 1 cycle after dispatch (or later for multi-cycle instructions).
  // CSR write data takes priority when both ALU and CSR writes coincide.
  wire        trace_wr_en   = `ARV_CPU_INST.ex_alu_reg_dest_wr | `ARV_CPU_INST.ex_csr_reg_dest_wr;
  wire  [4:0] trace_wr_addr = `ARV_CPU_INST.ex_reg_dest_sel;
  wire [31:0] trace_wr_data = `ARV_CPU_INST.ex_csr_reg_dest_wr ? `ARV_CPU_INST.ex_csr_reg_dest_wdata
                                                      : `ARV_CPU_INST.ex_alu_reg_dest_wdata;

  // Pending LS instruction buffer: dispatch info is saved here and the log
  // line is only emitted once the AHB data phase completes (dph_last), at
  // which point both address and data are known.
  reg          trace_ls_pending;
  reg   [63:0] trace_ls_cycle;
  reg   [31:0] trace_ls_pc;
  reg   [31:0] trace_ls_bin;
  reg   [31:0] trace_ls_addr;   // saved at aph_valid (combinational signal)
  reg          trace_ls_rw;     // 0=load, 1=store

  // Pending non-LS instruction buffer: emit is deferred until the execute-stage
  // register write is visible (trace_wr_en, 1 cycle after dispatch) or until
  // the next instruction dispatches — whichever comes first.
  // Both events can coincide in back-to-back execution; the single always block
  // handles this via NBA priority (emit fires in step 3, new buffer in step 4).
  reg          trace_nls_pending;
  reg   [63:0] trace_nls_cycle;
  reg   [31:0] trace_nls_pc;
  reg   [31:0] trace_nls_bin;
  reg          trace_nls_is_branch;
  reg          trace_nls_branch_taken;
  reg    [4:0] trace_nls_memops;       // Zcmp/Zcmt: number of hidden memory ops
  reg    [4:0] trace_ls_store_src;     // store source register number
  reg    [1:0] trace_ls_priv;         // privilege mode at dispatch
  reg    [1:0] trace_nls_priv;        // privilege mode at dispatch
  reg [8*20-1:0] trace_tgt_buf;      // temporary buffer for tgt_reg formatting

  // Simulation timestamp: cycle * CLK_PERIOD_NS.
  // $time/$stime/%t all produce 0 in Icarus Verilog's $fwrite; cycle arithmetic works.

  // Source register values (captured at dispatch from forwarded register file)
  wire   [4:0] trace_rs1_sel = `ARV_CPU_INST.id_reg_src1_sel;
  wire  [31:0] trace_rs1_val = `ARV_CPU_INST.id_reg_src1_rdata_w_fwd;
  wire   [4:0] trace_rs2_sel = `ARV_CPU_INST.id_reg_src2_sel;
  wire  [31:0] trace_rs2_val = `ARV_CPU_INST.id_reg_src2_rdata_w_fwd;
  reg    [4:0] trace_nls_rs1_sel;
  reg   [31:0] trace_nls_rs1_val;
  reg    [4:0] trace_nls_rs2_sel;
  reg   [31:0] trace_nls_rs2_val;
  reg          trace_nls_has_rs1;       // instruction reads rs1 as a register (not imm/unused)
  reg          trace_nls_has_rs2;       // instruction reads rs2 as a register

  // CSR write data
  wire  [31:0] trace_csr_wr_data = `ARV_CPU_INST.arv_csr_top_inst.register_value_nxt;
  reg          trace_nls_is_csr;        // buffered CSR instruction
  reg   [11:0] trace_nls_csr_addr;      // CSR address (bin[31:20])
  reg   [31:0] trace_nls_csr_wdata;     // CSR write data saved one cycle after dispatch
  reg          trace_nls_csr_data_valid;// csr_wdata has been captured

  // Store width (for extracting actual stored value from AHB bus data)
  reg    [1:0] trace_ls_store_width;    // 0=byte, 1=half, 2=word

  // WFI tracking
  reg          trace_nls_is_wfi;        // buffered instruction was WFI

  // Trap save state (mepc/mcause) for annotation on first handler instruction
  wire  [31:0] trace_mepc_save = `ARV_CPU_INST.arv_csr_top_inst.arv_csr_traps_inst.mepc_save_value;
  reg   [31:0] trace_trap_mepc_buf;
  reg   [31:0] trace_trap_mcause_buf;
  reg   [31:0] trace_nls_mepc;
  reg   [31:0] trace_nls_mcause;
  reg   [31:0] trace_ls_mepc;
  reg   [31:0] trace_ls_mcause;

  // Trap cause buffering: when a trap is taken, the cause is saved here
  // and annotated on the first instruction dispatched after the trap.
  reg          trace_trap_pending;    // a trap was taken, next dispatch gets annotated
  reg          trace_trap_was_irq;    // buffered: was it an interrupt?
  reg          trace_trap_was_nmi;    // buffered: was it an NMI?
  reg          trace_trap_had_kill;   // buffered: a muldiv/uop kill fired before this trap
  reg    [4:0] trace_trap_cause_buf;  // buffered: cause code
  // Per-instruction trap annotation buffers
  reg          trace_nls_trap_valid;
  reg          trace_nls_trap_is_irq;
  reg          trace_nls_trap_is_nmi;
  reg          trace_nls_trap_had_kill;
  reg    [4:0] trace_nls_trap_cause;
  reg          trace_ls_trap_valid;
  reg          trace_ls_trap_is_irq;
  reg          trace_ls_trap_is_nmi;
  reg          trace_ls_trap_had_kill;
  reg    [4:0] trace_ls_trap_cause;
  reg    [1:0] trace_nls_xret;        // 0=none, 1=MRET, 2=SRET, 3=MNRET

  // $sformat stores strings right-justified in the reg buffer (chars at LSBs,
  // nulls at MSBs). Printing with %s in $fdisplay emits the nulls first as
  // spaces, making the text appear right-aligned. This task finds the highest
  // non-null byte and prints characters left-to-right, giving left-alignment.
  task fwrite_str_lj;
    input integer    fd;
    input [8*64-1:0] str;
    input integer    width;   // pad with spaces to this minimum width
    integer          i;
    integer          str_end;
    begin
      str_end = -1;
      for (i = 0; i < 64; i = i + 1)
        if (str[i*8 +: 8] != 8'h00) str_end = i;
      for (i = str_end; i >= 0; i = i - 1)
        $fwrite(fd, "%s", str[i*8 +: 8]);
      for (i = str_end + 1; i < width; i = i + 1)
        $fwrite(fd, " ");
    end
  endtask

  // Convert privilege mode bits to a single ASCII character
  function [7:0] priv_char;
    input [1:0] mode;
    begin
      case (mode)
        2'b11:   priv_char = "M";
        2'b01:   priv_char = "S";
        2'b00:   priv_char = "U";
        default: priv_char = "?";
      endcase
    end
  endfunction

  // Format trap cause into trace_tgt_buf as mnemonic string
  // Use fwrite_str_lj afterwards for padded output.
  function [8*16-1:0] trap_cause_str;
    input         is_nmi;
    input         is_irq;
    input   [4:0] cause;
    begin
      trap_cause_str = {16{8'h00}};
      if (is_nmi) begin
        trap_cause_str = "NMI";
      end else if (is_irq) begin
        case (cause)
          5'd1:    trap_cause_str = "IRQ:SSW";
          5'd3:    trap_cause_str = "IRQ:MSW";
          5'd5:    trap_cause_str = "IRQ:STMR";
          5'd7:    trap_cause_str = "IRQ:MTMR";
          5'd9:    trap_cause_str = "IRQ:SEXT";
          5'd11:   trap_cause_str = "IRQ:MEXT";
          default: begin
            // Platform IRQs: causes 16-31 → "IRQ:P16" to "IRQ:P31"
            trap_cause_str = {16{8'h00}};
            trap_cause_str[7*8 +: 8] = "I";
            trap_cause_str[6*8 +: 8] = "R";
            trap_cause_str[5*8 +: 8] = "Q";
            trap_cause_str[4*8 +: 8] = ":";
            trap_cause_str[3*8 +: 8] = "P";
            trap_cause_str[2*8 +: 8] = "0" + (cause / 10);
            trap_cause_str[1*8 +: 8] = "0" + (cause % 10);
          end
        endcase
      end else begin
        case (cause)
          5'd0:    trap_cause_str = "EXC:IADM";
          5'd1:    trap_cause_str = "EXC:IACF";
          5'd2:    trap_cause_str = "EXC:ILLI";
          5'd3:    trap_cause_str = "EXC:EBRK";
          5'd4:    trap_cause_str = "EXC:LDAM";
          5'd5:    trap_cause_str = "EXC:LDAF";
          5'd6:    trap_cause_str = "EXC:STAM";
          5'd7:    trap_cause_str = "EXC:STAF";
          5'd8:    trap_cause_str = "EXC:ECALL";
          5'd9:    trap_cause_str = "EXC:ECALL";
          5'd11:   trap_cause_str = "EXC:ECALL";
          default: trap_cause_str = "EXC:????";
        endcase
      end
    end
  endfunction

  initial begin
    trace_fd          = $fopen("asphalt.log", "w");
    $timeformat(-9, 0, " ns", 10); // for $display/%t messages elsewhere in testbench
    trace_cycle       = 64'd0;
    trace_ls_pending  = 1'b0;
    trace_nls_pending = 1'b0;
    trace_trap_pending     = 1'b0;
    trace_nls_trap_valid   = 1'b0;
    trace_ls_trap_valid    = 1'b0;
    trace_nls_rs1_sel        = 5'd0;
    trace_nls_rs1_val        = 32'd0;
    trace_nls_rs2_sel        = 5'd0;
    trace_nls_rs2_val        = 32'd0;
    trace_nls_has_rs1        = 1'b0;
    trace_nls_has_rs2        = 1'b0;
    trace_nls_is_csr         = 1'b0;
    trace_nls_csr_addr       = 12'd0;
    trace_nls_csr_wdata      = 32'd0;
    trace_nls_csr_data_valid = 1'b0;
    trace_ls_store_width     = 2'd2;
    trace_nls_is_wfi         = 1'b0;
    trace_trap_mepc_buf      = 32'd0;
    trace_trap_mcause_buf    = 32'd0;
    trace_nls_mepc           = 32'd0;
    trace_nls_mcause         = 32'd0;
    trace_ls_mepc            = 32'd0;
    trace_ls_mcause          = 32'd0;
    $fdisplay(trace_fd, "# ######################################################################################################################################################################");
    $fdisplay(trace_fd, "# arvern Instruction Trace");
    $fdisplay(trace_fd, "# ######################################################################################################################################################################");
    $fdisplay(trace_fd, "#");
    $fdisplay(trace_fd, "#        cycle     : clock cycle at instruction dispatch");
    $fdisplay(trace_fd, "#        pc        : program counter");
    $fdisplay(trace_fd, "#        instr     : raw instruction encoding (hex)");
    $fdisplay(trace_fd, "#        mnemonic  : decoded instruction");
    $fdisplay(trace_fd, "#        mem       : memory operation (R=read, W=write, -=none)");
    $fdisplay(trace_fd, "#        mem_addr  : memory access address");
    $fdisplay(trace_fd, "#        mem_data  : memory read/write data");
    $fdisplay(trace_fd, "#        tgt_reg   : destination register and value, or [xN]=0xVAL for store (value extracted from AHB bus)");
    $fdisplay(trace_fd, "#        sz        : instruction size in bytes (2=compressed, 4=standard)");
    $fdisplay(trace_fd, "#        br        : branch outcome (T=taken, N=not-taken, -=not a branch)");
    $fdisplay(trace_fd, "#        trap      : trap event on this instruction:");
    $fdisplay(trace_fd, "#                     IRQ:MTMR  machine timer interrupt");
    $fdisplay(trace_fd, "#                     IRQ:MSW   machine software interrupt");
    $fdisplay(trace_fd, "#                     IRQ:MEXT  machine external interrupt");
    $fdisplay(trace_fd, "#                     IRQ:STMR  supervisor timer interrupt");
    $fdisplay(trace_fd, "#                     IRQ:SSW   supervisor software interrupt");
    $fdisplay(trace_fd, "#                     IRQ:SEXT  supervisor external interrupt");
    $fdisplay(trace_fd, "#                     IRQ:Pnn   platform interrupt (nn=16..31)");
    $fdisplay(trace_fd, "#                     EXC:ECALL environment call");
    $fdisplay(trace_fd, "#                     EXC:EBRK  breakpoint");
    $fdisplay(trace_fd, "#                     EXC:ILLI  illegal instruction");
    $fdisplay(trace_fd, "#                     EXC:IADM  instruction address misaligned");
    $fdisplay(trace_fd, "#                     EXC:IACF  instruction access fault");
    $fdisplay(trace_fd, "#                     EXC:LDAM  load address misaligned");
    $fdisplay(trace_fd, "#                     EXC:LDAF  load access fault");
    $fdisplay(trace_fd, "#                     EXC:STAM  store address misaligned");
    $fdisplay(trace_fd, "#                     EXC:STAF  store access fault");
    $fdisplay(trace_fd, "#                     NMI       non-maskable interrupt (Smrnmi)");
    $fdisplay(trace_fd, "#                     MRET      return from machine trap");
    $fdisplay(trace_fd, "#                     SRET      return from supervisor trap");
    $fdisplay(trace_fd, "#                     MNRET     return from NMI handler (Smrnmi)");
    $fdisplay(trace_fd, "#        priv      : privilege mode (M=machine, S=supervisor, U=user)");
    $fdisplay(trace_fd, "#        time(ns)  : simulation time in nanoseconds (cycle * CLK_PERIOD_NS=%0d)", CLK_PERIOD_NS);
    $fdisplay(trace_fd, "#        note      : optional annotations:");
    $fdisplay(trace_fd, "#                     # kill:NMI  NMI killed an in-progress muldiv/uop before taking this NMI");
    $fdisplay(trace_fd, "#                     # kill:IRQ  IRQ killed an in-progress muldiv/uop before taking this IRQ");
    $fdisplay(trace_fd, "#                     # N mem ops Zcmp/Zcmt hidden memory operations");
    $fdisplay(trace_fd, "#                     # csr:0xADDR:=0xVAL  value written to CSR (register variants only)");
    $fdisplay(trace_fd, "#                     # rs1:xN=0xVAL       source register 1 value at dispatch");
    $fdisplay(trace_fd, "#                     rs2:xN=0xVAL        source register 2 value at dispatch");
    $fdisplay(trace_fd, "#                     # mepc=0x... mcause=0x...  trap save state (first instruction of handler only)");
    $fdisplay(trace_fd, "#                     # wfi-end: N cycles  on WFI line: wait duration before IRQ woke core");
    $fdisplay(trace_fd, "#");
    $fdisplay(trace_fd, "# ######################################################################################################################################################################");
    $fdisplay(trace_fd, "#");
    $fdisplay(trace_fd, "# %-10s  %-12s  %-10s  %-10s  %-32s  %-4s  %-10s  %-10s  %-20s  %-2s  %-2s  %-9s  %-4s  %s",
              "cycle", "time(ns)", "pc", "instr", "mnemonic", "mem", "mem_addr", "mem_data", "tgt_reg", "sz", "br", "trap", "priv", "note");
  end

  // Cycle counter (separate block, no conflict with trace logic)
  always @(posedge trace_clk or negedge trace_resetn)
    if (!trace_resetn) trace_cycle <= 64'd0;
    else               trace_cycle <= trace_cycle + 64'd1;

  // Main trace logic — single always block to avoid races on pending flags.
  //
  // Priority within a clock edge:
  //   1. aph_valid  : save LS address (no conflict)
  //   2. dph_last   : emit buffered LS line, clear ls_pending
  //   3. nls emit   : flush buffered non-LS when trace_wr_en fires OR next
  //                   dispatch arrives; clear nls_pending (NBA overridden by
  //                   step 4 if a new non-LS dispatches on the same edge)
  //   4. dispatch   : buffer new LS or non-LS instruction
  always @(posedge trace_clk or negedge trace_resetn) begin
    if (!trace_resetn) begin
      trace_ls_pending  <= 1'b0;
      trace_ls_cycle    <= 64'd0;
      trace_ls_pc       <= 32'd0;
      trace_ls_bin      <= 32'd0;
      trace_ls_addr     <= 32'd0;
      trace_ls_rw       <= 1'b0;
      trace_nls_pending      <= 1'b0;
      trace_nls_cycle        <= 64'd0;
      trace_nls_pc           <= 32'd0;
      trace_nls_bin          <= 32'd0;
      trace_nls_is_branch    <= 1'b0;
      trace_nls_branch_taken <= 1'b0;
      trace_nls_memops       <= 5'd0;
      trace_ls_store_src     <= 5'd0;
      trace_ls_priv          <= 2'b11;
      trace_nls_priv         <= 2'b11;
      trace_trap_pending     <= 1'b0;
      trace_nls_trap_valid   <= 1'b0;
      trace_ls_trap_valid    <= 1'b0;
      trace_nls_rs1_sel        <= 5'd0;
      trace_nls_rs1_val        <= 32'd0;
      trace_nls_rs2_sel        <= 5'd0;
      trace_nls_rs2_val        <= 32'd0;
      trace_nls_has_rs1        <= 1'b0;
      trace_nls_has_rs2        <= 1'b0;
      trace_nls_is_csr         <= 1'b0;
      trace_nls_csr_addr       <= 12'd0;
      trace_nls_csr_wdata      <= 32'd0;
      trace_nls_csr_data_valid <= 1'b0;
      trace_ls_store_width     <= 2'd2;
      trace_nls_is_wfi         <= 1'b0;
      trace_trap_mepc_buf      <= 32'd0;
      trace_trap_mcause_buf    <= 32'd0;
      trace_nls_mepc           <= 32'd0;
      trace_nls_mcause         <= 32'd0;
      trace_ls_mepc            <= 32'd0;
      trace_ls_mcause          <= 32'd0;
    end else begin
      // Capture trap cause when a trap is taken; will be emitted on the
      // next dispatched instruction (first instruction of the handler).
      if (trace_trap_taken) begin
        trace_trap_pending   <= 1'b1;
        trace_trap_was_irq   <= trace_trap_is_irq;
        trace_trap_was_nmi   <= trace_trap_is_nmi;
        trace_trap_had_kill  <= trace_kill_muldiv | trace_kill_uop;
        trace_trap_cause_buf <= trace_trap_cause;
        trace_trap_mepc_buf   <= trace_mepc_save;
        trace_trap_mcause_buf <= {trace_trap_is_irq, 26'h0000000, trace_trap_cause};
      end

      // 0.5. CSR write data: one cycle after CSR dispatch the execute stage has
      //      register_value_nxt ready. Capture it once (first capture wins).
      if (trace_nls_pending && trace_nls_is_csr && !trace_nls_csr_data_valid) begin
        trace_nls_csr_wdata      <= trace_csr_wr_data;
        trace_nls_csr_data_valid <= 1'b1;
      end

      // 1. AHB address phase: capture address and direction before they change
      if (`ARV_CPU_INST.arv_load_store_inst.aph_valid) begin
        trace_ls_addr <= `ARV_CPU_INST.arv_load_store_inst.data_haddr_o;
        trace_ls_rw   <= `ARV_CPU_INST.arv_load_store_inst.data_hwrite_o;
      end

      // 2. AHB data phase: emit the buffered LS instruction line
      if (`ARV_CPU_INST.arv_load_store_inst.dph_last && trace_ls_pending) begin
        $fwrite(trace_fd, "%-12d  %-12d  0x%08h  0x%08h  ",
                trace_ls_cycle, trace_ls_cycle * CLK_PERIOD_NS, trace_ls_pc, trace_ls_bin);
        fwrite_str_lj(trace_fd, instruction_str(trace_ls_bin, trace_ls_pc), 32);
        if (trace_ls_rw) begin
          case (trace_ls_store_width)
            2'd0: $sformat(trace_tgt_buf, "[x%0d]=0x%02h",  trace_ls_store_src,
                           `ARV_CPU_INST.arv_load_store_inst.data_hwdata_o[7:0]);
            2'd1: $sformat(trace_tgt_buf, "[x%0d]=0x%04h",  trace_ls_store_src,
                           `ARV_CPU_INST.arv_load_store_inst.data_hwdata_o[15:0]);
            default: $sformat(trace_tgt_buf, "[x%0d]=0x%08h", trace_ls_store_src,
                              `ARV_CPU_INST.arv_load_store_inst.data_hwdata_o);
          endcase
          $fwrite(trace_fd, "  %-4s  0x%08h  0x%08h  ",
                  "W", trace_ls_addr, `ARV_CPU_INST.arv_load_store_inst.data_hwdata_o);
        end else begin
          $sformat(trace_tgt_buf, "x%0d=0x%08h",
                  `ARV_CPU_INST.arv_load_store_inst.wb_reg_dest_sel_o,
                  `ARV_CPU_INST.arv_load_store_inst.wb_load_reg_dest_wdata_o);
          $fwrite(trace_fd, "  %-4s  0x%08h  0x%08h  ",
                  "R", trace_ls_addr, `ARV_CPU_INST.arv_load_store_inst.data_hrdata_i);
        end
        fwrite_str_lj(trace_fd, {{(64-20){8'h00}}, trace_tgt_buf}, 20);
        $fwrite(trace_fd, "  %-2d  %-2s  ",
                (trace_ls_bin[1:0] != 2'b11) ? 32'd2 : 32'd4,
                "-");
        if (trace_ls_trap_valid)
          fwrite_str_lj(trace_fd, {{(64-16){8'h00}}, trap_cause_str(trace_ls_trap_is_nmi, trace_ls_trap_is_irq, trace_ls_trap_cause)}, 9);
        else
          $fwrite(trace_fd, "%-9s", "-");
        $fwrite(trace_fd, "  %-4s", priv_char(trace_ls_priv));
        if (trace_ls_trap_valid && !trace_ls_trap_is_nmi)
          $fwrite(trace_fd, "  # mepc=0x%08h mcause=0x%08h", trace_ls_mepc, trace_ls_mcause);
        if (trace_ls_trap_valid && trace_ls_trap_had_kill)
          $fwrite(trace_fd, "  # kill:%s", trace_ls_trap_is_nmi ? "NMI" : "IRQ");
        $fwrite(trace_fd, "\n");
        trace_ls_pending <= 1'b0;
      end

      // 2b. Branch cancel correction: id_branch_detect_o is speculative
      //     (always-taken); id_branch_cancel_o fires 1 cycle later if the
      //     branch was actually not-taken.  Correct the latched outcome
      //     before the NLS emit consumes it.
      if (trace_nls_pending && trace_nls_is_branch && `ARV_CPU_INST.arv_decode_inst.id_branch_cancel_o)
        trace_nls_branch_taken <= 1'b0;

      // 3. Non-LS emit: flush when execute-stage write is seen OR next dispatch.
      //    If trace_wr_en is 0 (branch, CSR-no-rd, etc.) but a new dispatch
      //    arrives, emit with "-" so the log stays in program order.
      if (trace_nls_pending && (trace_wr_en || trace_valid)) begin
        $fwrite(trace_fd, "%-12d  %-12d  0x%08h  0x%08h  ",
                trace_nls_cycle, trace_nls_cycle * CLK_PERIOD_NS, trace_nls_pc, trace_nls_bin);
        fwrite_str_lj(trace_fd, instruction_str(trace_nls_bin, trace_nls_pc), 32);
        if (trace_wr_en) begin
          $sformat(trace_tgt_buf, "x%0d=0x%08h", trace_wr_addr, trace_wr_data);
          $fwrite(trace_fd, "  %-4s  %-10s  %-10s  ", "-", "-", "-");
          fwrite_str_lj(trace_fd, {{(64-20){8'h00}}, trace_tgt_buf}, 20);
        end else
          $fwrite(trace_fd, "  %-4s  %-10s  %-10s  %-20s",
                  "-", "-", "-", "-");
        // sz, br, and priv columns
        // Guard against same-cycle cancel: check both the latched flag
        // AND the live cancel wire for robustness.
        $fwrite(trace_fd, "  %-2d  %-2s  ",
                (trace_nls_bin[1:0] != 2'b11) ? 32'd2 : 32'd4,
                trace_nls_is_branch ?
                  ((trace_nls_branch_taken && !`ARV_CPU_INST.arv_decode_inst.id_branch_cancel_o) ? "T" : "N")
                  : "-");
        if (trace_nls_trap_valid)
          fwrite_str_lj(trace_fd, {{(64-16){8'h00}}, trap_cause_str(trace_nls_trap_is_nmi, trace_nls_trap_is_irq, trace_nls_trap_cause)}, 9);
        else if (trace_nls_xret == 2'd1)
          $fwrite(trace_fd, "%-9s", "MRET");
        else if (trace_nls_xret == 2'd2)
          $fwrite(trace_fd, "%-9s", "SRET");
        else if (trace_nls_xret == 2'd3)
          $fwrite(trace_fd, "%-9s", "MNRET");
        else
          $fwrite(trace_fd, "%-9s", "-");
        $fwrite(trace_fd, "  %-4s", priv_char(trace_nls_priv));
        // Zcmp/Zcmt: annotate hidden memory operations
        if (trace_nls_memops > 0)
          $fwrite(trace_fd, "  # %0d mem ops", trace_nls_memops);
        // Kill annotation: a muldiv/uop was aborted before this trap entry
        if (trace_nls_trap_valid && trace_nls_trap_had_kill)
          $fwrite(trace_fd, "  # kill:%s", trace_nls_trap_is_nmi ? "NMI" : "IRQ");
        // CSR write value annotation
        if (trace_nls_is_csr) begin
          if (trace_wr_en)
            $fwrite(trace_fd, "  # csr:0x%03h:=0x%08h", trace_nls_csr_addr, trace_csr_wr_data);
          else if (trace_nls_csr_data_valid)
            $fwrite(trace_fd, "  # csr:0x%03h:=0x%08h", trace_nls_csr_addr, trace_nls_csr_wdata);
        end
        // Source register annotation
        if (trace_nls_has_rs1 && trace_nls_rs1_sel != 5'd0)
          $fwrite(trace_fd, "  # rs1:x%0d=0x%08h", trace_nls_rs1_sel, trace_nls_rs1_val);
        if (trace_nls_has_rs2 && trace_nls_rs2_sel != 5'd0)
          $fwrite(trace_fd, "  rs2:x%0d=0x%08h", trace_nls_rs2_sel, trace_nls_rs2_val);
        // Trap save state on first instruction of handler
        if (trace_nls_trap_valid && !trace_nls_trap_is_nmi)
          $fwrite(trace_fd, "  # mepc=0x%08h mcause=0x%08h", trace_nls_mepc, trace_nls_mcause);
        $fwrite(trace_fd, "\n");
        // WFI end annotation: immediately after WFI line, before next instruction
        if (trace_nls_is_wfi)
          $fwrite(trace_fd, "# wfi-end: %0d cycles (resume at cycle %0d)\n",
                  trace_cycle - trace_nls_cycle, trace_cycle);
        trace_nls_pending        <= 1'b0;
        trace_nls_csr_data_valid <= 1'b0;
      end

      // 4. Instruction dispatch: buffer for deferred emit
      if (trace_valid) begin
        if (!trace_is_ls) begin
          trace_nls_cycle        <= trace_cycle;
          trace_nls_pc           <= pc_id;
          trace_nls_bin          <= bin_id;
          trace_nls_pending      <= 1'b1;
          trace_nls_is_branch    <= trace_is_branch;
          trace_nls_branch_taken <= `ARV_CPU_INST.arv_decode_inst.id_branch_detect_o;
          trace_nls_priv         <= trace_priv;
          // Transfer trap annotation to this instruction if pending
          trace_nls_trap_valid    <= trace_trap_pending;
          trace_nls_trap_is_irq   <= trace_trap_was_irq;
          trace_nls_trap_is_nmi   <= trace_trap_was_nmi;
          trace_nls_trap_had_kill <= trace_trap_had_kill;
          trace_nls_trap_cause    <= trace_trap_cause_buf;
          if (trace_trap_pending)
            trace_trap_pending   <= 1'b0;
          // Detect MRET/SRET/MNRET at dispatch
          trace_nls_xret <= trace_mret_taken  ? 2'd1 :
                            trace_sret_taken  ? 2'd2 :
                            trace_mnret_taken ? 2'd3 : 2'd0;
          // Zcmp/Zcmt memory op count (Q2, funct3=101)
          if (bin_id[1:0] == 2'b10 && bin_id[15:13] == 3'b101) begin
            case (bin_id[15:10])
              6'b101000: trace_nls_memops <= 5'd1;  // CM.JT/CM.JALT: 1 table load
              6'b101110, 6'b101111:                  // CM.PUSH/POP/POPRET/POPRETZ
                trace_nls_memops <= (bin_id[7:4] == 4'd15) ? 5'd13
                                 : {1'b0, bin_id[7:4]} - 5'd3;
              default: trace_nls_memops <= 5'd0;     // CM.MVA01S/MVSA01: no mem
            endcase
          end else
            trace_nls_memops <= 5'd0;
          // Source registers
          trace_nls_rs1_sel <= trace_rs1_sel;
          trace_nls_rs1_val <= trace_rs1_val;
          trace_nls_rs2_sel <= trace_rs2_sel;
          trace_nls_rs2_val <= trace_rs2_val;
          // has_rs1: false for LUI, AUIPC, JAL, and CSR immediate (CSRRWI/CSRRSI/CSRRCI funct3[2]=1)
          trace_nls_has_rs1 <= ~( (bin_id[1:0]==2'b11) &&
                                  (bin_id[6:0]==7'b0110111 ||   // LUI
                                   bin_id[6:0]==7'b0010111 ||   // AUIPC
                                   bin_id[6:0]==7'b1101111 ||   // JAL
                                   (bin_id[6:0]==7'b1110011 && bin_id[14])) );  // CSR imm funct3[2]
          // has_rs2: R-type, branches; compressed Q1 arithmetic; compressed Q2 MV/ADD
          trace_nls_has_rs2 <= ( (bin_id[1:0]==2'b11 && (bin_id[6:0]==7'b0110011 ||
                                                          bin_id[6:0]==7'b1100011)) ||
                                  (bin_id[1:0]==2'b01 && bin_id[15:13]==3'b100 && ~bin_id[12]) ||
                                  (bin_id[1:0]==2'b10 && bin_id[15:13]==3'b100) );
          // CSR instruction detection (any CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI, funct3!=000)
          trace_nls_is_csr         <= (bin_id[1:0]==2'b11) && (bin_id[6:0]==7'b1110011) &&
                                      (bin_id[14:12] != 3'b000);
          trace_nls_csr_addr       <= bin_id[31:20];
          trace_nls_csr_data_valid <= 1'b0;
          // WFI detection (standard only: 0x10500073)
          trace_nls_is_wfi <= (bin_id == 32'h10500073);
          // Trap save state for annotation on first handler instruction
          trace_nls_mepc   <= trace_trap_mepc_buf;
          trace_nls_mcause <= trace_trap_mcause_buf;
        end else begin
          trace_ls_cycle   <= trace_cycle;
          trace_ls_pc      <= pc_id;
          trace_ls_bin     <= bin_id;
          trace_ls_pending <= 1'b1;
          trace_ls_priv    <= trace_priv;
          // Transfer trap annotation to this instruction if pending
          trace_ls_trap_valid    <= trace_trap_pending;
          trace_ls_trap_is_irq   <= trace_trap_was_irq;
          trace_ls_trap_is_nmi   <= trace_trap_was_nmi;
          trace_ls_trap_had_kill <= trace_trap_had_kill;
          trace_ls_trap_cause    <= trace_trap_cause_buf;
          if (trace_trap_pending)
            trace_trap_pending  <= 1'b0;
          // Save store source register for later emit
          if (bin_id[1:0] == 2'b11)       trace_ls_store_src <= bin_id[24:20];
          else if (bin_id[1:0] == 2'b10)  trace_ls_store_src <= bin_id[6:2];   // C.SWSP
          else                            trace_ls_store_src <= {2'b01, bin_id[4:2]}; // C.SW/SB/SH
          // Store width (for tgt_reg value annotation)
          if (bin_id[1:0] == 2'b11) begin               // Standard store
            case (bin_id[13:12])                         // funct3[1:0]
              2'b00:   trace_ls_store_width <= 2'd0;     // SB
              2'b01:   trace_ls_store_width <= 2'd1;     // SH
              default: trace_ls_store_width <= 2'd2;     // SW
            endcase
          end else if (bin_id[1:0]==2'b00 && bin_id[15:13]==3'b100) begin  // Zcb Q0
            if      (bin_id[12:10] == 3'b010) trace_ls_store_width <= 2'd0;  // C.SB
            else if (bin_id[12:10] == 3'b011) trace_ls_store_width <= 2'd1;  // C.SH
            else                              trace_ls_store_width <= 2'd2;  // Zcb loads (unused)
          end else                            trace_ls_store_width <= 2'd2;  // C.SW / C.SWSP
          // Trap save state for annotation
          trace_ls_mepc   <= trace_trap_mepc_buf;
          trace_ls_mcause <= trace_trap_mcause_buf;
        end
      end

    end
  end

  // Flush any pending instruction at end of simulation and close the trace file.
  task trace_flush_and_close;
    begin
      if (trace_nls_pending) begin
        $fwrite(trace_fd, "%-12d  %-12d  0x%08h  0x%08h  ",
                trace_nls_cycle, trace_nls_cycle * CLK_PERIOD_NS, trace_nls_pc, trace_nls_bin);
        fwrite_str_lj(trace_fd, instruction_str(trace_nls_bin, trace_nls_pc), 32);
        $fwrite(trace_fd, "  %-4s  %-10s  %-10s  %-15s  %-2d  %-2s  %-9s  %-4s",
                "-", "-", "-", "-",
                (trace_nls_bin[1:0] != 2'b11) ? 32'd2 : 32'd4,
                trace_nls_is_branch ? (trace_nls_branch_taken ? "T" : "N") : "-",
                "-",
                priv_char(trace_nls_priv));
        if (trace_nls_memops > 0)
          $fwrite(trace_fd, "  # %0d mem ops", trace_nls_memops);
        $fwrite(trace_fd, "\n");
      end
      if (trace_ls_pending) begin
        $fwrite(trace_fd, "%-12d  %-12d  0x%08h  0x%08h  ",
                trace_ls_cycle, trace_ls_cycle * CLK_PERIOD_NS, trace_ls_pc, trace_ls_bin);
        fwrite_str_lj(trace_fd, instruction_str(trace_ls_bin, trace_ls_pc), 32);
        $fwrite(trace_fd, "  %-4s  0x%08h  %-10s  %-20s  %-2d  %-2s  %-9s  %-4s\n",
                trace_ls_rw ? "W" : "R", trace_ls_addr, "-", "-",
                (trace_ls_bin[1:0] != 2'b11) ? 32'd2 : 32'd4, "-",
                "-",
                priv_char(trace_ls_priv));
      end
      $fclose(trace_fd);
    end
  endtask

`endif

  //..............................................................................................


endmodule
