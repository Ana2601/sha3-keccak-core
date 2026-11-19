`timescale 1ns/1ps
// Self-checking testbench: replays hashlib-generated vectors with randomised
// input stalls and compares every digest.
module tb_sha3;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [1:0]   mode;
    reg          in_valid = 0, in_keep = 0, in_last = 0;
    reg  [7:0]   in_data = 0;
    wire         in_ready, digest_valid, busy;
    wire [511:0] digest;

    sha3_core dut (
        .clk(clk), .rst_n(rst_n), .mode_i(mode),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .in_keep(in_keep), .in_last(in_last),
        .digest_valid(digest_valid), .digest_o(digest), .busy_o(busy)
    );

    integer fd, r, n, i, pass = 0, fail = 0, m, bits;
    integer cyc = 0, t0;
    longint total_bytes = 0, total_cycles = 0;
    reg [7:0]   msg [0:4095];
    reg [511:0] exp, mask, got;
    string vec_file;

    always @(posedge clk) cyc <= cyc + 1;

    task automatic send_beat(input [7:0] d, input keep, input last);
        begin
            // random idle cycles exercise the valid/ready handshake
            while ($urandom_range(0, 9) == 0) @(posedge clk);
            in_valid <= 1; in_data <= d; in_keep <= keep; in_last <= last;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 0;
        end
    endtask

    initial begin
        if (!$value$plusargs("vectors=%s", vec_file)) vec_file = "build/vectors.txt";
        fd = $fopen(vec_file, "r");
        if (fd == 0) begin $display("cannot open %s", vec_file); $fatal; end
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%d %d", m, n);
            if (r != 2) break;
            for (i = 0; i < n; i = i + 1) r = $fscanf(fd, "%h", msg[i]);
            r = $fscanf(fd, "%h", exp);
            mode = m[1:0];
            t0 = cyc;
            if (n == 0) send_beat(8'h00, 1'b0, 1'b1);
            else for (i = 0; i < n; i = i + 1) send_beat(msg[i], 1'b1, i == n - 1);
            while (!digest_valid) @(posedge clk);
            total_bytes  = total_bytes + n;
            total_cycles = total_cycles + (cyc - t0);
            case (m)
                0: bits = 224;
                1: bits = 256;
                2: bits = 384;
                default: bits = 512;
            endcase
            mask = (bits == 512) ? {512{1'b1}} : ((512'd1 << bits) - 1);
            got  = digest & mask;
            if (got === exp) pass = pass + 1;
            else begin
                fail = fail + 1;
                $display("FAIL mode=%0d len=%0d\n  got %h\n  exp %h", m, n, got, exp);
            end
            @(posedge clk);
        end

        $display("SHA3: %0d passed, %0d failed (%0d bytes in %0d cycles incl. random stalls)",
                 pass, fail, total_bytes, total_cycles);
        if (fail != 0 || pass == 0) $fatal(1, "TEST FAILED");
        $display("TEST PASSED");
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "timeout");
    end
endmodule
