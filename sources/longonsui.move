module 0x0::loan_manager {  // or use your specific address
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::event;
    
    // Error codes
    const EInsufficientCollateral: u64 = 0;
    const EInvalidRepaymentAmount: u64 = 1;
    const ELoanDefaulted: u64 = 2;
    const EInvalidLoanAmount: u64 = 3;
    const EInsufficientLiquidity: u64 = 4;

    // Constants
    const COLLATERAL_PERCENTAGE: u64 = 10;
    const INSTALLMENTS: u64 = 10;
    const MAX_MISSED_PAYMENTS: u64 = 3;
    const SECONDS_PER_MONTH: u64 = 2592000;

    public struct LendingPool has key {
        id: UID,
        usdc_balance: Balance<USDC>,
        total_interest_rate: u64,
        locked_until: u64,
    }

    public struct Loan has key {
        id: UID,
        borrower: address,
        main_asset_amount: u64,
        monthly_payment: u64,
        remaining_payments: u64,
        last_payment_time: u64,
        missed_payments: u64,
        collateral: Balance<USDC>,
        locked_asset: Balance<WBTC>,
    }

    public struct USDC has drop {}
    public struct WBTC has drop {}

    public struct LoanCreated has copy, drop {
        loan_id: ID,
        borrower: address,
        amount: u64,
    }

    public struct RepaymentMade has copy, drop {
        loan_id: ID,
        amount: u64,
        remaining_payments: u64,
    }

    // Initialize lending pool
    public fun create_lending_pool(ctx: &mut TxContext) {
        let lending_pool = LendingPool {
            id: object::new(ctx),
            usdc_balance: balance::zero(),
            total_interest_rate: 5, // 5% interest rate
            locked_until: 0,
        };
        transfer::share_object(lending_pool);
    }

    // Lender deposits USDC
    public fun deposit_usdc(
        pool: &mut LendingPool,
        usdc: Coin<USDC>,
        lock_time: u64,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&usdc);
        let usdc_balance = coin::into_balance(usdc);
        balance::join(&mut pool.usdc_balance, usdc_balance);
        pool.locked_until = lock_time;
    }

    // Create a loan
    public fun create_loan(
        pool: &mut LendingPool,
        collateral: Coin<USDC>,
        main_asset_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let collateral_balance = coin::into_balance(collateral);
        let collateral_amount = balance::value(&collateral_balance);
        
        // Verify collateral is 10% of loan amount
        assert!(
            collateral_amount >= (main_asset_amount * COLLATERAL_PERCENTAGE) / 100,
            EInsufficientCollateral
        );

        // Calculate monthly payment (90% of main asset divided by 10 months)
        let monthly_payment = (main_asset_amount * 90) / (100 * INSTALLMENTS);

        let loan = Loan {
            id: object::new(ctx),
            borrower: tx_context::sender(ctx),
            main_asset_amount,
            monthly_payment,
            remaining_payments: INSTALLMENTS,
            last_payment_time: clock::timestamp_ms(clock),
            missed_payments: 0,
            collateral: collateral_balance,
            locked_asset: balance::zero(), // Will be filled after swap
        };

        // TODO: Implement swap USDC to WBTC logic here
        
        transfer::transfer(loan, tx_context::sender(ctx));
    }

    // Make loan repayment
    public fun make_repayment(
    loan: &mut Loan,
    payment: Coin<USDC>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let payment_amount = coin::value(&payment);
    assert!(payment_amount >= loan.monthly_payment, EInvalidRepaymentAmount);
    
    // Check if payment is on time
    let current_time = clock::timestamp_ms(clock);
    if (current_time - loan.last_payment_time > SECONDS_PER_MONTH) {
        loan.missed_payments = loan.missed_payments + 1;
    };
    
    // Check for default
    assert!(loan.missed_payments < MAX_MISSED_PAYMENTS, ELoanDefaulted);
    
    // Process payment
    loan.remaining_payments = loan.remaining_payments - 1;
    loan.last_payment_time = current_time;
    
    // Add payment to loan's collateral balance
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut loan.collateral, payment_balance);
    
    // Release 10% of locked asset to borrower
    // TODO: Implement asset release logic
    
    // Emit repayment event
    event::emit(RepaymentMade {
        loan_id: object::id(loan),
        amount: payment_amount,
        remaining_payments: loan.remaining_payments,
    });
}


    // Handle loan default
    public fun handle_default(
    loan: &mut Loan,
    pool: &mut LendingPool,
        ctx: &mut TxContext
    ) {
        assert!(loan.missed_payments >= MAX_MISSED_PAYMENTS, ELoanDefaulted);
        
    // Swap remaining WBTC to USDC and return to pool
    // TODO: Implement swap logic
    
    // Return remaining collateral to borrower
    let collateral = balance::withdraw_all(&mut loan.collateral);
    transfer::public_transfer(coin::from_balance(collateral, ctx), loan.borrower);
}
}