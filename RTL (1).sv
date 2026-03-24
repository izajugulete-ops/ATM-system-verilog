//--------------ATM MACHINE PROJECT------------------

module atm_machine (
    input  logic        clk,
    input  logic        rst,

    input  logic        card_inserted,
    input  logic [1:0]  acc_select,
    input  logic [3:0]  entered_pin,
    input  logic        pin_submit,

    input  logic        withdraw_req,
    input  logic        deposit_req,
    input  logic        balance_req,
    input  logic        exit_req,

    input  logic [15:0] amount,

    output logic        pin_ok,
    output logic        locked,
    output logic        transaction_done,
    output logic        insufficient_balance,
    output logic        atm_cash_low,

    output logic [15:0] balance,
    output logic [15:0] atm_cash,
    output logic [2:0]  state_out
);

    parameter int NUM_ACCOUNTS     = 3;
    parameter int MAX_PIN_ATTEMPTS = 3;
    parameter int MINI_STMT_SIZE   = 5;

    // Account database
    logic [3:0]  stored_pins      [NUM_ACCOUNTS];
    logic [15:0] account_balances [NUM_ACCOUNTS];
    logic [1:0]  wrong_count      [NUM_ACCOUNTS];
    logic        acc_locked       [NUM_ACCOUNTS];

    // Mini statement
    logic [15:0] last_txn_amount [NUM_ACCOUNTS][MINI_STMT_SIZE];
    logic [2:0]  last_txn_type   [NUM_ACCOUNTS][MINI_STMT_SIZE];
    logic [2:0]  txn_index       [NUM_ACCOUNTS];

    parameter int TXN_WITHDRAW = 1;
    parameter int TXN_DEPOSIT  = 2;
    parameter int TXN_BALANCE  = 3;

    // ATM cash
    logic [15:0] atm_cash_reg;

    // FSM states
    typedef enum logic [2:0] {
        IDLE          = 3'b000,
        CARD_INSERTED = 3'b001,
        PIN_CHECK     = 3'b010,
        MENU          = 3'b011,
        WITHDRAW      = 3'b100,
        DEPOSIT       = 3'b101,
        BALANCE_STATE = 3'b110,
        EXIT_STATE    = 3'b111
    } state_t;

    state_t state, next_state;

    // Next state logic
    always_comb begin
        next_state = state;

        case (state)

            IDLE: begin
                if (card_inserted)
                    next_state = CARD_INSERTED;
            end

            CARD_INSERTED: begin
                next_state = PIN_CHECK;
            end

            PIN_CHECK: begin
                if (pin_submit) begin
                    if (acc_locked[acc_select])
                        next_state = IDLE;
                    else if (entered_pin == stored_pins[acc_select])
                        next_state = MENU;
                    else
                        next_state = PIN_CHECK;
                end
            end

            MENU: begin
                if (withdraw_req)
                    next_state = WITHDRAW;
                else if (deposit_req)
                    next_state = DEPOSIT;
                else if (balance_req)
                    next_state = BALANCE_STATE;
                else if (exit_req)
                    next_state = EXIT_STATE;
            end

            WITHDRAW:      next_state = MENU;
            DEPOSIT:       next_state = MENU;
            BALANCE_STATE: next_state = MENU;
            EXIT_STATE:    next_state = IDLE;

            default: next_state = IDLE;

        endcase
    end

    // Mini statement update task
    task automatic update_statement(
        input int acc,
        input int ttype,
        input logic [15:0] amt
    );
        int idx;
        begin
            idx = txn_index[acc];

            last_txn_type[acc][idx]   <= ttype[2:0];
            last_txn_amount[acc][idx] <= amt;

            if (txn_index[acc] == MINI_STMT_SIZE-1)
                txn_index[acc] <= 0;
            else
                txn_index[acc] <= txn_index[acc] + 1;
        end
    endtask

    // SINGLE always_ff for ALL sequential registers
    integer i, j;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // FSM reset
            state <= IDLE;

            // Output reset
            pin_ok               <= 0;
            locked               <= 0;
            transaction_done     <= 0;
            insufficient_balance <= 0;
            atm_cash_low         <= 0;

            // Init pins
            stored_pins[0] <= 4'b1010;
            stored_pins[1] <= 4'b0101;
            stored_pins[2] <= 4'b1111;

            // Init balances
            account_balances[0] <= 16'd5000;
            account_balances[1] <= 16'd9000;
            account_balances[2] <= 16'd3000;

            // Init counters + lock + statements
            for (i = 0; i < NUM_ACCOUNTS; i++) begin
                wrong_count[i] <= 0;
                acc_locked[i]  <= 0;
                txn_index[i]   <= 0;

                for (j = 0; j < MINI_STMT_SIZE; j++) begin
                    last_txn_amount[i][j] <= 16'd0;
                    last_txn_type[i][j]   <= 3'd0;
                end
            end

            // ATM cash init
            atm_cash_reg <= 16'd20000;
        end
        else begin
            // State update
            state <= next_state;

            // default outputs every clock
            pin_ok               <= 0;
            transaction_done     <= 0;
            insufficient_balance <= 0;
            atm_cash_low         <= 0;

            locked <= acc_locked[acc_select];

            case (state)

                PIN_CHECK: begin
                    if (pin_submit) begin
                        if (acc_locked[acc_select]) begin
                            locked <= 1;
                        end
                        else if (entered_pin == stored_pins[acc_select]) begin
                            pin_ok <= 1;
                            wrong_count[acc_select] <= 0;
                        end
                        else begin
                            wrong_count[acc_select] <= wrong_count[acc_select] + 1;

                            if (wrong_count[acc_select] + 1 >= MAX_PIN_ATTEMPTS) begin
                                acc_locked[acc_select] <= 1;
                                locked <= 1;
                            end
                        end
                    end
                end

                WITHDRAW: begin
                    if ((account_balances[acc_select] >= amount) &&
                        (atm_cash_reg >= amount)) begin

                        account_balances[acc_select] <= account_balances[acc_select] - amount;
                        atm_cash_reg <= atm_cash_reg - amount;

                        transaction_done <= 1;

                        update_statement(acc_select, TXN_WITHDRAW, amount);

                        if ((atm_cash_reg - amount) < 16'd2000)
                            atm_cash_low <= 1;
                    end
                    else begin
                        insufficient_balance <= 1;
                    end
                end

                DEPOSIT: begin
                    account_balances[acc_select] <= account_balances[acc_select] + amount;
                    atm_cash_reg <= atm_cash_reg + amount;

                    transaction_done <= 1;
                    update_statement(acc_select, TXN_DEPOSIT, amount);
                end

                BALANCE_STATE: begin
                    transaction_done <= 1;
                    update_statement(acc_select, TXN_BALANCE, account_balances[acc_select]);
                end

                default: begin
                    // no action
                end

            endcase
        end
    end

    // Outputs
    assign balance   = account_balances[acc_select];
    assign atm_cash  = atm_cash_reg;
    assign state_out = state;
endmodule
