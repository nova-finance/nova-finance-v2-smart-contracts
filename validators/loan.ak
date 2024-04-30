use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, WithdrawFrom,
  find_script_outputs,
}
use aiken/transaction/credential.{Inline, ScriptCredential}
use aiken/transaction/value.{quantity_of}
use types.{
  CollateralDatum, LoanAndInterestAmount, OfferLoanDatum, ValidateLoanInfo,
}
use utils.{get_inputs_from_script, get_lower_bound, resolve_output_reference}

type LoanRedeemer {
  CancelLoan(Int)
  GetLoan(Int)
}

type Redeemer {
  action: LoanRedeemer,
}

fn get_total_repay_amount(
  list: List<Input>,
  inputs_from_script_validator: List<Input>,
) -> LoanAndInterestAmount {
  list.foldl(
    inputs_from_script_validator,
    LoanAndInterestAmount { loan_amount: 0, interest_amount: 0 },
    fn(input: Input, acc: LoanAndInterestAmount) {
      expect InlineDatum(loan_datum) = input.output.datum
      expect loan_datum_typed: OfferLoanDatum = loan_datum
      let interest_amount: Int = loan_datum_typed.interest_amount
      let loan_amount: Int =
        quantity_of(
          input.output.value,
          loan_datum_typed.loan_asset.policy_id,
          loan_datum_typed.loan_asset.asset_name,
        )

      LoanAndInterestAmount {
        loan_amount: acc.loan_amount + loan_amount,
        interest_amount: acc.interest_amount + interest_amount,
      }
    },
  )
}

fn get_inputs_loan_info(
  inputs_from_script: List<Input>,
) -> List<ValidateLoanInfo> {
  list.foldl(
    inputs_from_script,
    [],
    fn(input, inputs_loan) {
      let output: Output = input.output
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: OfferLoanDatum = loan_offer_datum

      // when we find a duplicate loan coming from the same lender, we will update the loan amount and collateral amount by summing them up
      when
        list.find(
          inputs_loan,
          fn(input_loan: ValidateLoanInfo) {
            input_loan.lender_address_hash == loan_offer_datum_typed.lender_address_hash && input_loan.loan_asset == loan_offer_datum_typed.loan_asset && input_loan.collateral_asset == loan_offer_datum_typed.collateral_asset && input_loan.interest_asset == loan_offer_datum_typed.interest_asset && input_loan.loan_duration == loan_offer_datum_typed.loan_duration
          },
        )
      is {
        Some(duplicate_loan) -> {
          let new_input_loan_info =
            ValidateLoanInfo {
              loan_amount: duplicate_loan.loan_amount + quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              loan_asset: loan_offer_datum_typed.loan_asset,
              collateral_amount: loan_offer_datum_typed.collateral_amount + duplicate_loan.collateral_amount,
              collateral_asset: loan_offer_datum_typed.collateral_asset,
              interest_amount: loan_offer_datum_typed.interest_amount + duplicate_loan.interest_amount,
              interest_asset: loan_offer_datum_typed.interest_asset,
              lender_address_hash: loan_offer_datum_typed.lender_address_hash,
              loan_duration: loan_offer_datum_typed.loan_duration,
            }

          let removed_duplicate_collateral_list =
            list.filter(
              inputs_loan,
              fn(input_loan: ValidateLoanInfo) {
                input_loan.lender_address_hash != loan_offer_datum_typed.lender_address_hash
              },
            )

          [new_input_loan_info, ..removed_duplicate_collateral_list]
        }

        None -> {
          let input_loan_info =
            ValidateLoanInfo {
              loan_amount: quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              loan_asset: loan_offer_datum_typed.loan_asset,
              collateral_amount: loan_offer_datum_typed.collateral_amount,
              collateral_asset: loan_offer_datum_typed.collateral_asset,
              interest_amount: loan_offer_datum_typed.interest_amount,
              interest_asset: loan_offer_datum_typed.interest_asset,
              lender_address_hash: loan_offer_datum_typed.lender_address_hash,
              loan_duration: loan_offer_datum_typed.loan_duration,
            }

          [input_loan_info, ..inputs_loan]
        }
      }
    },
  )
}

fn get_outputs_collateral_info(
  script_outputs: List<Output>,
  total_repay_amount: LoanAndInterestAmount,
  ctx: ScriptContext,
) -> List<ValidateLoanInfo> {
  list.filter_map(
    script_outputs,
    fn(output: Output) {
      expect InlineDatum(collateral_datum) = output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      // Check the lend time in the datum is within the transaction validity range
      let lend_time_valid =
        collateral_datum_typed.lend_time == get_lower_bound(
          ctx.transaction.validity_range,
        )

      // Check the total loan and interest amount in the datum is what we calculated from the outputs
      let total_loan_amount_valid =
        collateral_datum_typed.total_loan_amount == total_repay_amount.loan_amount
      let total_interest_amount_valid =
        collateral_datum_typed.total_interest_amount == total_repay_amount.interest_amount

      let output_datum_valid =
        lend_time_valid && total_loan_amount_valid && total_interest_amount_valid

      if output_datum_valid {
        let output_collateral_info =
          ValidateLoanInfo {
            loan_amount: collateral_datum_typed.loan_amount,
            loan_asset: collateral_datum_typed.loan_asset,
            collateral_amount: quantity_of(
              output.value,
              collateral_datum_typed.collateral_asset.policy_id,
              collateral_datum_typed.collateral_asset.asset_name,
            ),
            collateral_asset: collateral_datum_typed.collateral_asset,
            interest_amount: collateral_datum_typed.interest_amount,
            interest_asset: collateral_datum_typed.interest_asset,
            lender_address_hash: collateral_datum_typed.lender_address_hash,
            loan_duration: collateral_datum_typed.loan_duration,
          }
        Some(output_collateral_info)
      } else {
        None
      }
    },
  )
}

fn loan_is_valid(
  ctx: ScriptContext,
  collateral_validator_hash: ByteArray,
  loan_validator_hash: ByteArray,
) -> Bool {
  // Get all outputs going to the collateral validator
  let outputs_to_collateral_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, collateral_validator_hash)
  // Get all inputs coming from own validator
  let inputs_from_script_validator: List<Input> =
    get_inputs_from_script(ctx.transaction.inputs, loan_validator_hash)

  // Get the total loan and interest amount the borrower must repay
  let total_repay_amount: LoanAndInterestAmount =
    get_total_repay_amount(ctx.transaction.inputs, inputs_from_script_validator)

  // Construct a list of ValidateLoanInfo for all inputs coming from own validator
  let inputs_loan_info: List<ValidateLoanInfo> =
    get_inputs_loan_info(inputs_from_script_validator)

  // Construct a list of ValidateLoanInfo for all outputs going to the loan validator
  let outputs_collateral_info: List<ValidateLoanInfo> =
    get_outputs_collateral_info(
      outputs_to_collateral_validator,
      total_repay_amount,
      ctx,
    )

  // Check if the loan info in the inputs matches the loan info in the outputs
  let info_difference =
    list.difference(inputs_loan_info, outputs_collateral_info)
  let info_matches = list.length(info_difference) == 0
  info_matches
}

validator(collateral_validator_hash: ByteArray) {
  fn spend(
    datum: OfferLoanDatum,
    redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer.action is {
      CancelLoan(_) -> {
        // To cancel a loan, the lender must sign the transaction
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        must_be_signed_by_lender
      }

      GetLoan(_) -> {
        expect ScriptContext { transaction: tx, purpose: Spend(own_ref) } = ctx

        let Transaction { inputs, withdrawals, .. } = tx

        let Output { address: own_addr, .. } =
          resolve_output_reference(inputs, own_ref)

        let own_withdrawal = Inline(own_addr.payment_credential)

        // Arbitrary withdrawal from this script is required.
        dict.has_key(withdrawals, own_withdrawal)
      }
    }
  }

  fn withdraw(_redeemer: Int, ctx: ScriptContext) {
    expect ScriptContext { transaction: _tx, purpose: WithdrawFrom(stake_cred) } =
      ctx

    expect Inline(ScriptCredential(loan_validator_hash)) = stake_cred
    loan_is_valid(ctx, collateral_validator_hash, loan_validator_hash)
  }
}
