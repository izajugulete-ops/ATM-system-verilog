//--------------ATM MACHINE PROJECT WITH CHANGE PIN------------------

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
    input  logic        change_pin_req, // Semnal nou pentru schimbare PIN
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

    logic [3:0]  stored_pins      [NUM_ACCOUNTS];
    logic [15:0] account_balances [NUM_ACCOUNTS]; 
    logic [1:0]  wrong_count      [NUM_ACCOUNTS];
    logic        acc_locked       [NUM_ACCOUNTS]; 
    
    logic [15:0] atm_cash_reg;

    typedef enum logic [2:0] {
        IDLE          = 3'b000,
        CARD_INSERTED = 3'b001,
        PIN_CHECK     = 3'b010,
        MENU          = 3'b011,
        WITHDRAW      = 3'b100,
        DEPOSIT       = 3'b101,
        BALANCE_STATE = 3'b110,
        CHANGE_PIN    = 3'b111  // Stare nouă
    } state_t; 

    state_t state, next_state; 

    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE:          if (card_inserted) next_state = CARD_INSERTED; 
            CARD_INSERTED: next_state = PIN_CHECK;
            PIN_CHECK:     if (pin_submit) begin
                               if (acc_locked[acc_select]) next_state = IDLE; 
                               else if (entered_pin == stored_pins[acc_select]) next_state = MENU; 
                           end
            MENU: begin
                if (withdraw_req)      next_state = WITHDRAW; 
                else if (deposit_req)  next_state = DEPOSIT;
                else if (balance_req)  next_state = BALANCE_STATE; 
                else if (change_pin_req) next_state = CHANGE_PIN; // Tranziție nouă
                else if (exit_req)     next_state = IDLE;
            end
            WITHDRAW, DEPOSIT, BALANCE_STATE, CHANGE_PIN: next_state = MENU;
            default: next_state = IDLE;
        endcase
    end

    // Sequential logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; 
            atm_cash_reg <= 16'd20000; 
            stored_pins[0] <= 4'b1010; stored_pins[1] <= 4'b0101; stored_pins[2] <= 4'b1111; 
            account_balances[0] <= 16'd5000; account_balances[1] <= 16'd9000; account_balances[2] <= 16'd3000; 
            for(int i=0; i<NUM_ACCOUNTS; i++) begin acc_locked[i] <= 0; wrong_count[i] <= 0; end 
        end else begin
            state <= next_state;
            transaction_done <= 0;
            
            case (state)
                PIN_CHECK: begin
                    if (pin_submit && !acc_locked[acc_select]) begin
                        if (entered_pin == stored_pins[acc_select]) begin
                            pin_ok <= 1;
                            wrong_count[acc_select] <= 0; 
                        end else begin
                            wrong_count[acc_select] <= wrong_count[acc_select] + 1;
                            if (wrong_count[acc_select] + 1 >= MAX_PIN_ATTEMPTS) acc_locked[acc_select] <= 1; 
                        end
                    end
                end
                
                CHANGE_PIN: begin
                    stored_pins[acc_select] <= amount[3:0]; // Salvăm noul PIN
                    transaction_done <= 1;
                end

                WITHDRAW: begin
                    if (account_balances[acc_select] >= amount && atm_cash_reg >= amount) begin
                        account_balances[acc_select] <= account_balances[acc_select] - amount; 
                        atm_cash_reg <= atm_cash_reg - amount;
                        transaction_done <= 1; 
                    end
                end
                
                DEPOSIT: begin
                    account_balances[acc_select] <= account_balances[acc_select] + amount; 
                    atm_cash_reg <= atm_cash_reg + amount;
                    transaction_done <= 1;
                end
            endcase
        end
    end

    assign balance   = account_balances[acc_select]; 
    assign atm_cash  = atm_cash_reg; 
    assign state_out = state;

endmodule
