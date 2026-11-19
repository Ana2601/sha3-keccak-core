// One round of Keccak-f[1600] (theta, rho, pi, chi, iota) - purely combinational.
// Lane (x,y) lives at state[64*(x+5*y) +: 64], FIPS 202 bit ordering.
module keccak_round (
    input  wire [1599:0] state_i,
    input  wire [63:0]   rc_i,
    output wire [1599:0] state_o
);
    function automatic integer rho_off(input integer x, input integer y);
        case (x + 5 * y)
            0:  rho_off = 0;   1:  rho_off = 1;   2:  rho_off = 62;  3:  rho_off = 28;  4:  rho_off = 27;
            5:  rho_off = 36;  6:  rho_off = 44;  7:  rho_off = 6;   8:  rho_off = 55;  9:  rho_off = 20;
            10: rho_off = 3;   11: rho_off = 10;  12: rho_off = 43;  13: rho_off = 25;  14: rho_off = 39;
            15: rho_off = 41;  16: rho_off = 45;  17: rho_off = 15;  18: rho_off = 21;  19: rho_off = 8;
            20: rho_off = 18;  21: rho_off = 2;   22: rho_off = 61;  23: rho_off = 56;  24: rho_off = 14;
            default: rho_off = 0;
        endcase
    endfunction

    wire [63:0] a [0:24];
    wire [63:0] c [0:4];
    wire [63:0] d [0:4];
    wire [63:0] t [0:24];   // after theta
    wire [63:0] b [0:24];   // after rho + pi
    wire [63:0] e [0:24];   // after chi

    genvar x, y;
    generate
        for (y = 0; y < 5; y = y + 1) begin : g_unpack_y
            for (x = 0; x < 5; x = x + 1) begin : g_unpack_x
                assign a[x+5*y] = state_i[64*(x+5*y) +: 64];
            end
        end

        for (x = 0; x < 5; x = x + 1) begin : g_theta_c
            assign c[x] = a[x] ^ a[x+5] ^ a[x+10] ^ a[x+15] ^ a[x+20];
        end
        for (x = 0; x < 5; x = x + 1) begin : g_theta_d
            assign d[x] = c[(x+4)%5] ^ {c[(x+1)%5][62:0], c[(x+1)%5][63]};
        end

        for (y = 0; y < 5; y = y + 1) begin : g_rp_y
            for (x = 0; x < 5; x = x + 1) begin : g_rp_x
                localparam integer R = rho_off(x, y);
                assign t[x+5*y] = a[x+5*y] ^ d[x];
                // pi: B[y][(2x+3y)%5] = rol(A[x][y], r[x][y])
                if (R == 0) begin : g_r0
                    assign b[y + 5*((2*x+3*y)%5)] = t[x+5*y];
                end else begin : g_rn
                    assign b[y + 5*((2*x+3*y)%5)] = {t[x+5*y][63-R:0], t[x+5*y][63:64-R]};
                end
            end
        end

        for (y = 0; y < 5; y = y + 1) begin : g_chi_y
            for (x = 0; x < 5; x = x + 1) begin : g_chi_x
                assign e[x+5*y] = b[x+5*y] ^ (~b[(x+1)%5 + 5*y] & b[(x+2)%5 + 5*y]);
            end
        end

        for (y = 0; y < 5; y = y + 1) begin : g_pack_y
            for (x = 0; x < 5; x = x + 1) begin : g_pack_x
                if (x == 0 && y == 0) begin : g_iota
                    assign state_o[63:0] = e[0] ^ rc_i;
                end else begin : g_plain
                    assign state_o[64*(x+5*y) +: 64] = e[x+5*y];
                end
            end
        end
    endgenerate
endmodule
