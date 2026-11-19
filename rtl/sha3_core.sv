// SHA-3 (FIPS 202) hash core: SHA3-224/256/384/512 selectable at run time.
//
//  * Byte-stream input with valid/ready back-pressure; `in_last` marks the
//    final beat, `in_keep=0` on that beat means "no data byte" (empty message
//    or a message that ended on the previous beat).
//  * Multi-rate padding (0x06 ... 0x80) is done in hardware.
//  * Iterative Keccak-f[1600]: one round per clock, 24 clocks per block.
//  * `mode_i` is sampled with the first beat of a message.
module sha3_core (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1:0]   mode_i,      // 0: SHA3-224, 1: SHA3-256, 2: SHA3-384, 3: SHA3-512
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [7:0]   in_data,
    input  wire         in_keep,
    input  wire         in_last,

    output reg          digest_valid,   // one-cycle pulse
    output wire [511:0] digest_o,       // digest byte i at [8*i +: 8]; upper bytes unused for short modes
    output wire         busy_o
);
    localparam [2:0] S_ABSORB = 3'd0, S_PERM = 3'd1, S_PAD = 3'd2, S_DONE = 3'd3;

    reg [2:0]    st;
    reg [1599:0] state;
    reg [7:0]    ptr;          // next byte position inside the rate
    reg [4:0]    round;
    reg          final_blk;    // the block being permuted already contains the padding
    reg          pad_pending;  // last byte seen, padding still to be absorbed
    reg          first;        // next accepted beat is the first of a message
    reg [1:0]    mode_q;

    wire [1:0] mode_c = first ? mode_i : mode_q;

    function automatic [7:0] rate_bytes(input [1:0] m);
        case (m)
            2'd0: rate_bytes = 8'd144;
            2'd1: rate_bytes = 8'd136;
            2'd2: rate_bytes = 8'd104;
            default: rate_bytes = 8'd72;
        endcase
    endfunction

    function automatic [63:0] round_const(input [4:0] r);
        case (r)
            5'd0:  round_const = 64'h0000000000000001;
            5'd1:  round_const = 64'h0000000000008082;
            5'd2:  round_const = 64'h800000000000808A;
            5'd3:  round_const = 64'h8000000080008000;
            5'd4:  round_const = 64'h000000000000808B;
            5'd5:  round_const = 64'h0000000080000001;
            5'd6:  round_const = 64'h8000000080008081;
            5'd7:  round_const = 64'h8000000000008009;
            5'd8:  round_const = 64'h000000000000008A;
            5'd9:  round_const = 64'h0000000000000088;
            5'd10: round_const = 64'h0000000080008009;
            5'd11: round_const = 64'h000000008000000A;
            5'd12: round_const = 64'h000000008000808B;
            5'd13: round_const = 64'h800000000000008B;
            5'd14: round_const = 64'h8000000000008089;
            5'd15: round_const = 64'h8000000000008003;
            5'd16: round_const = 64'h8000000000008002;
            5'd17: round_const = 64'h8000000000000080;
            5'd18: round_const = 64'h000000000000800A;
            5'd19: round_const = 64'h800000008000000A;
            5'd20: round_const = 64'h8000000080008081;
            5'd21: round_const = 64'h8000000000008080;
            5'd22: round_const = 64'h0000000080000001;
            default: round_const = 64'h8000000080008008;
        endcase
    endfunction

    wire [1599:0] round_out;
    keccak_round u_round (
        .state_i (state),
        .rc_i    (round_const(round)),
        .state_o (round_out)
    );

    wire [7:0] rate   = rate_bytes(mode_c);
    wire       accept = in_valid && in_ready;
    wire       fills  = in_keep && (ptr == rate - 8'd1);

    assign in_ready = (st == S_ABSORB);
    assign busy_o   = (st != S_ABSORB) || !first;
    assign digest_o = state[511:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st           <= S_ABSORB;
            state        <= 1600'd0;
            ptr          <= 8'd0;
            round        <= 5'd0;
            final_blk    <= 1'b0;
            pad_pending  <= 1'b0;
            first        <= 1'b1;
            mode_q       <= 2'd0;
            digest_valid <= 1'b0;
        end else begin
            digest_valid <= 1'b0;
            case (st)
                S_ABSORB: if (accept) begin
                    if (first) begin
                        mode_q <= mode_i;
                        first  <= 1'b0;
                    end
                    // A new message always starts from the all-zero state.
                    if (in_keep)
                        state <= (first ? 1600'd0 : state) ^ ({1592'd0, in_data} << {ptr, 3'b000});
                    else if (first)
                        state <= 1600'd0;
                    if (in_keep) ptr <= fills ? 8'd0 : ptr + 8'd1;
                    pad_pending <= in_last;
                    final_blk   <= 1'b0;
                    round       <= 5'd0;
                    if (fills)        st <= S_PERM;
                    else if (in_last) st <= S_PAD;
                end

                S_PAD: begin
                    // domain-separation suffix 0x06 at ptr, final 0x80 at rate-1
                    state <= state ^ ({1592'd0, 8'h06} << {ptr, 3'b000})
                                   ^ ({1592'd0, 8'h80} << {rate - 8'd1, 3'b000});
                    pad_pending <= 1'b0;
                    final_blk   <= 1'b1;
                    round       <= 5'd0;
                    st          <= S_PERM;
                end

                S_PERM: begin
                    state <= round_out;
                    round <= round + 5'd1;
                    if (round == 5'd23) begin
                        if (final_blk)        st <= S_DONE;
                        else if (pad_pending) st <= S_PAD;
                        else                  st <= S_ABSORB;
                    end
                end

                S_DONE: begin
                    digest_valid <= 1'b1;
                    ptr          <= 8'd0;
                    first        <= 1'b1;
                    final_blk    <= 1'b0;
                    st           <= S_ABSORB;
                end

                default: st <= S_ABSORB;
            endcase
        end
    end
endmodule
